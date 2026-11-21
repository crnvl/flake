"""Public reference research and one-shot technical review for the shimmers agent."""

import json
import re
import sys
from enum import StrEnum
from pathlib import Path
from time import monotonic
from urllib.parse import quote

import anyio
import httpx
from mcp.server.mcpserver import Context, MCPServer


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
# Keep direct shortcuts for common questions whose wording doesn't match a filename.
Topic = StrEnum("Topic", {key.replace("-", "_"): key for key in TOPICS})
MANUALS = {
    "gitlab": ("gitlabhq/gitlabhq", "master", "doc"),
    "grafana": ("grafana/grafana", "main", "docs/sources"),
    "prometheus": ("prometheus/docs", "main", "docs"),
    "kubernetes": ("kubernetes/website", "main", "content/en/docs"),
    "python": ("python/cpython", "3.14", "Doc"),
    "nix": ("NixOS/nix", "master", "doc/manual/source"),
}
Manual = StrEnum("Manual", {key: key for key in MANUALS})


class Analysis(StrEnum):
    explain = "explain"
    compare = "compare"
    review = "review"


TASKS = {
    Analysis.explain: "Explain the documented behavior, prerequisites and limitations.",
    Analysis.compare: "Compare the documented options, constraints and operational trade-offs.",
    Analysis.review: "Review the documented approach for reliability, failure modes and verification.",
}
PUBLIC_ROOT = Path(sys.argv[2]).resolve() if len(sys.argv) == 3 else None
server = MCPServer("publicdocs", instructions=(
    "Delegate public technical research early: use lookup for exact shortcuts; otherwise use research "
    "to find relevant material and request an explanation, comparison or review. Choose terms locally. "
    + ("For general technical reasoning about the user's public question, call reason. " if PUBLIC_ROOT else
       "For a general technical second opinion, call reason if the user's message starts with a fenced public-brief block. ")
    + "Use the conclusion and evidence, identify uncertainty, "
    "and keep private reasoning local. A refusal is not a routing signal. If a source or worker is "
    "unavailable, use the returned evidence or report the gap instead of repeating the call."
))
cache = {}
indexes = {}


async def api(*args, timeout):
    with anyio.fail_after(timeout):
        result = await anyio.run_process([sys.argv[1], "api", *args], cwd="/", check=False)
    if result.returncode:
        raise ValueError("OpenCode request unavailable")
    return json.loads(result.stdout)["data"]


async def consult(prompt):
    # Stateless generation: no worker tools, session ID, attachments or message history.
    request = {"model": {"providerID": "opencode", "id": "deepseek-v4.1-flash-free"}, "prompt": prompt}
    try:
        data = await api("post", "/api/experimental/generate/text", "--data", json.dumps(request), timeout=40)
        return data["text"].strip()[:4000]
    except (OSError, TimeoutError, ValueError, KeyError, TypeError, AttributeError):
        return ""


async def reference_answer(question, references):
    material = "\n\n".join(f"Source: {url}\n{excerpt}" for url, excerpt in references)
    answer = await consult(f"{question}\nGive a concise answer based only on these public references. "
                           f"Say when the material is insufficient.\n\n{material}")
    if not answer:
        return "Free reviewer unavailable. Official documentation excerpts:\n" + "\n\n".join(
            f"Source: {url}\n{excerpt[:2200]}" for url, excerpt in references)
    return "\n".join(f"Source: {url}" for url, _ in references) + "\n\n" + answer


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
    text = await reference_answer(question, [(url, excerpt)])
    cache[topic] = (monotonic() + 300, text)
    return text


async def fetch(client, url, limit):
    data = bytearray()
    async with client.stream("GET", url) as response:
        response.raise_for_status()
        async for chunk in response.aiter_bytes():
            data.extend(chunk)
            if len(data) > limit:
                raise ValueError("reference too large")
    return bytes(data)


async def manual_index(client, manual):
    if manual in indexes and monotonic() < indexes[manual][0]:
        return indexes[manual][1]
    repo, branch, root = MANUALS[manual]
    if manual.value == "nix":
        toc = await fetch(client, f"https://raw.githubusercontent.com/{repo}/{branch}/{root}/SUMMARY.md.in", 512_000)
        paths = re.findall(r"\]\(([\w/-]+\.md)\)", toc.decode())
    else:
        url = f"https://api.github.com/repos/{repo}/git/trees/{branch}:{root}?recursive=1"
        tree = json.loads(await fetch(client, url, 4_000_000))
        paths = [entry['path'] for entry in tree['tree'] if entry.get('type') == 'blob'
                 and entry['path'].endswith(('.md', '.rst')) and 0 < entry.get('size', 0) <= 512_000
                 and not any(part.startswith('.') for part in entry['path'].split('/'))]
    indexes[manual] = (monotonic() + 3600, paths)
    return paths


def tokens(text):
    # Paths commonly use plural names (e.g. histograms.md).
    return {word[:-1] if len(word) > 4 and word.endswith("s") and not word.endswith("ss") else word
            for word in re.findall(r"[a-z0-9]+", text.lower())}


@server.tool()
async def research(manual: Manual, keywords: str, analysis: Analysis = Analysis.explain) -> str:
    """Search a whole public manual by path keywords; reason over the best matching sections. Keywords stay local."""
    terms = tokens(keywords[:256]) - tokens(manual.value) - {"and", "the", "of", "to", "in", "for", "with", "how"}
    if not terms:
        return "Specify a feature or command from the manual."
    repo, branch, root = MANUALS[manual]
    refs = []
    try:
        with anyio.fail_after(15):
            async with httpx.AsyncClient() as client:
                # Rank locally; only paths from the published index ever become URLs.
                paths = await manual_index(client, manual)
                matches = {path: hits for path in paths if (hits := terms & tokens(path))}
                uncovered = terms.copy()
                for _ in range(min(2, len(matches))):
                    path = max(matches, key=lambda p: (len(uncovered & matches[p]), len(matches[p]), -len(p)))
                    uncovered -= matches.pop(path)
                    url = f"https://raw.githubusercontent.com/{repo}/{branch}/{root}/{quote(path)}"
                    doc = (await fetch(client, url, 512_000)).decode("utf-8")
                    # Prefer paragraphs matching the request instead of always sending the preamble.
                    doc = re.sub(r"\A---\n.*?\n---\n", "", doc, count=1, flags=re.S)
                    paragraphs = doc.split("\n\n")
                    start = max(range(len(paragraphs)), key=lambda i: len(terms & tokens(paragraphs[i])))
                    excerpt = "\n\n".join(paragraphs[start:])[:4000]
                    refs.append((url, excerpt))
    except (httpx.HTTPError, TimeoutError, ValueError, KeyError):
        if not refs:
            return f"The {manual.value} manual could not be loaded."
    if not refs:
        return "No matching document paths. Use a product feature or command as the keyword."
    return await reference_answer(TASKS[analysis], refs)


@server.tool()
async def reason(ctx: Context) -> str:
    """Get a second opinion on the user's latest shareable technical question; no model-written handoff."""
    session = (ctx.request_context.meta or {}).get("ai.opencode/sessionID", "")
    if not isinstance(session, str) or not re.fullmatch(r"ses_[a-zA-Z0-9]+", session):
        return "No calling OpenCode session."
    try:
        info = await api("get", f"/api/session/{session}", timeout=4)
        if info.get("parentID") or info.get("fork"):
            return "Public review requires a direct user session."
        # Read only the latest user message locally. Files and surrounding context are not inputs.
        messages = await api("get", f"/api/session/{session}/message?type=user&order=desc&limit=1", timeout=4)
        message = messages[0] if messages else {}
        text = message.get("text", "") if message.get("type") == "user" else ""
        block = re.match(r"\A```public-brief[ \t]*\r?\n(.+?)\r?\n```[ \t]*(?:\r?\n|\Z)", text, re.S)
        brief = block[1].strip() if block else ""
        if (not text.startswith("```public-brief") and PUBLIC_ROOT
                and Path(info["location"]["directory"]).resolve().is_relative_to(PUBLIC_ROOT)):
            # Moving an existing conversation here does not publish its earlier turns.
            moves = await api("get", f"/api/session/{session}/message?type=location-switched&order=desc&limit=1", timeout=4)
            if not moves or message["time"]["created"] > moves[0]["time"]["created"]:
                brief = text.strip()
    except (OSError, TimeoutError, ValueError, KeyError, TypeError, AttributeError):
        return "The public brief could not be read."
    if not 0 < len(brief) <= 6000:
        return "No public brief. Start the message with a fenced public-brief block of up to 6000 characters."
    answer = await consult("Give a concise technical second opinion on the following shareable brief. "
                           "Discuss evidence, alternatives, trade-offs and uncertainty. Focus on design, "
                           "troubleshooting or defensive remediation. You have no tools or instance access.\n\n" + brief)
    return answer or "Free reviewer unavailable; no second opinion was obtained."


if __name__ == "__main__":
    server.run()
