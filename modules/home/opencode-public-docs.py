"""A local MCP tool for offloading public documentation lookups from shimmers."""

import json
import sys
from enum import StrEnum
from time import monotonic

import anyio
import httpx
from mcp.server.mcpserver import MCPServer


GITLAB = "https://gitlab.com/gitlab-org/gitlab/-/raw/master/doc/"
TOPICS = {
    "gitlab-installed-version": (
        GITLAB + "administration/raketasks/maintenance.md",
        "## Gather GitLab and system information",
        "How does an administrator read the installed version? Distinguish installation types. "
        "The example output is not evidence of anyone's installed version.",
    ),
    "gitlab-upgrade-path": (
        GITLAB + "update/upgrade_paths.md", "## Required upgrade stops",
        "Explain how to plan an upgrade and account for required stops.",
    ),
    "gitlab-backup-exclusions": (
        GITLAB + "administration/backup_restore/backup_gitlab.md", "## Data not included in a backup",
        "List data the standard backup excludes and what an administrator must save separately.",
    ),
    "grafana-dashboard-provisioning": (
        "https://raw.githubusercontent.com/grafana/grafana/main/docs/sources/administration/provisioning/index.md",
        "## Dashboards", "Explain file-based dashboard provisioning and how updates take effect.",
    ),
    "prometheus-rule-tests": (
        "https://raw.githubusercontent.com/prometheus/prometheus/main/docs/configuration/unit_testing_rules.md",
        "## Test file format", "Explain the minimal test file for checking a Prometheus alert rule with promtool.",
    ),
}
# A closed schema: the caller selects a topic, never a prompt, URL or attachment.
Topic = StrEnum("Topic", {key.replace("-", "_"): key for key in TOPICS})
server = MCPServer("publicdocs", instructions=(
    "When a question matches a lookup topic, call publicdocs_lookup first, without waiting for the user. "
    "Use its cited documentation as reference. Only local evidence can establish an installed version. "
    "If the lookup is unavailable, report the missing evidence rather than repeating it."
))
cache = {}


@server.tool()
async def lookup(topic: Topic) -> str:
    """Summarize official public admin docs using a free model, without sending conversation or files."""
    if topic in cache and monotonic() < cache[topic][0]:
        return cache[topic][1]

    url, heading, question = TOPICS[topic]
    try:
        with anyio.fail_after(10):
            async with httpx.AsyncClient() as client:
                response = await client.get(url)
                response.raise_for_status()
                _, found, section = response.text.partition("\n" + heading + "\n")
        if not found:
            return f"Documentation section changed. Consult the source: {url}"
    except (httpx.HTTPError, TimeoutError):
        return f"Documentation unavailable. Source: {url}"

    section = section.split("\n## ", 1)[0]
    if topic == "gitlab-installed-version":
        section = section.partition("Example output:")[0]
    excerpt = (heading + "\n" + section).strip()[:8000]
    # The one-shot API starts no agent and attaches no session history, tools or project files.
    request = {
        "model": {"providerID": "opencode", "id": "deepseek-v4.1-flash-free"},
        "prompt": f"{question}\nAnswer briefly using only this official documentation excerpt:\n\n{excerpt}",
    }
    answer = ""
    try:
        with anyio.fail_after(40):
            result = await anyio.run_process([
                sys.argv[1], "api", "post", "/api/experimental/generate/text", "--data", json.dumps(request),
            ], cwd="/", check=False)
        if result.returncode == 0:
            answer = json.loads(result.stdout)["data"]["text"].strip()[:4000]
    except (OSError, TimeoutError, ValueError, KeyError, TypeError, AttributeError):
        pass
    if not answer:
        answer = "Free summary unavailable. Official documentation excerpt:\n" + excerpt[:3000]
    text = f"Source: {url}\n\n{answer}"
    cache[topic] = (monotonic() + 300, text)
    return text


if __name__ == "__main__":
    server.run()
