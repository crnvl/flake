"""Run with the MCP worker's Python: python -m unittest discover -s modules/home/tests."""

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, patch

spec = importlib.util.spec_from_file_location("publicdocs", Path(__file__).parents[1] / "opencode-public-docs.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class ReviewerInputTest(unittest.IsolatedAsyncioTestCase):
    async def handoff(self, text, *, public=False, directory="/private", moved=False, **info):
        ctx = SimpleNamespace(request_context=SimpleNamespace(meta={"ai.opencode/sessionID": "ses_test"}))
        session = {"location": {"directory": directory}, **info}
        message = {"text": text, "type": "user", "time": {"created": 1}, "files": ["private attachment"]}

        async def api(method, path, *, timeout):
            self.assertEqual(method, "get")
            return {
                "/api/session/ses_test": session,
                "/api/session/ses_test/message?type=user&order=desc&limit=1": [message],
                "/api/session/ses_test/message?type=location-switched&order=desc&limit=1":
                    [{"time": {"created": 2}}] if moved else [],
            }[path]

        reviewer = AsyncMock(return_value="second opinion")
        with patch.object(worker, "PUBLIC_ROOT", Path("/public") if public else None), \
             patch.object(worker, "api", api), patch.object(worker, "consult", reviewer):
            await worker.reason(ctx)
        if reviewer.await_count:
            reviewer.assert_awaited_once()
            payload = reviewer.await_args.args[0]
            self.assertNotIn("private attachment", payload)
            self.assertNotIn("private notes", payload)
            return payload
        return None

    async def test_private_message_exports_only_a_leading_closed_brief(self):
        self.assertIn("public question", await self.handoff("```public-brief\npublic question\n```\nprivate notes"))
        for text in ("private notes", "prefix\n```public-brief\ntext\n```", "```public-brief\nprivate notes"):
            self.assertIsNone(await self.handoff(text))

    async def test_public_mode_requires_direct_session_at_public_location(self):
        self.assertIn("public question", await self.handoff("public question", public=True, directory="/public/sub"))
        for args in ({"directory": "/public-other"}, {"directory": "/public", "moved": True},
                     {"directory": "/public", "parentID": "ses_parent"}, {"directory": "/public", "fork": {"sessionID": "ses_parent"}}):
            self.assertIsNone(await self.handoff("private notes", public=True, **args))
        self.assertIsNone(await self.handoff("```public-brief\nprivate notes", public=True, directory="/public"))
