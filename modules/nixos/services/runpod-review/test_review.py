import concurrent.futures
import fcntl
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import time
import unittest
from unittest.mock import Mock, patch

import httpx
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

import gateway
import lease as rp


class LeaseTest(unittest.TestCase):
    def setUp(self):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.now = 1795287000
        self.api = Mock()
        self.api.create.return_value = {'id': 'abcd1234', 'cloud': 'SECURE', 'cost': 0.27,
                                        'gpu': {'id': rp.GPU, 'count': 1}}
        self.control = rp.Controller(self.api, Path(tmp.name), lambda: self.now)
        self.control.resume()

    def test_concurrent_cold_requests_and_idle(self):
        with concurrent.futures.ThreadPoolExecutor(4) as pool:
            leases = list(pool.map(lambda _: self.control.ensure(), range(4)))
        self.api.create.assert_called_once()
        self.control.touch(leases[0], ready=True)
        self.assertFalse(self.control.read()['lease']['download'])
        self.now += 1200
        with self.control.lock('requests', fcntl.LOCK_SH):
            self.control.reap()
            self.api.delete.assert_not_called()
            self.control.touch(leases[0])
        self.now += rp.IDLE - 1
        self.control.reap()
        self.api.delete.assert_not_called()
        self.now += 1
        self.control.reap()
        self.api.delete.assert_called_once_with('abcd1234')
        self.assertIsNone(self.control.read()['lease'])

    def test_lost_create_response_and_restart(self):
        self.api.create.side_effect = httpx.ReadTimeout('no reply')
        with self.assertRaises(httpx.ReadTimeout):
            self.control.ensure()
        recovered = rp.Controller(self.api, self.control.dir, lambda: self.now)
        with self.assertRaises(rp.Unavailable):
            recovered.ensure()
        self.now += rp.IDLE
        self.api.find.return_value = 'orphan123'
        recovered.reap()
        self.api.delete.assert_called_once_with('orphan123')
        self.api.create.assert_called_once()

    def test_hard_deadline_even_if_busy_and_delete_retry(self):
        self.control.ensure()
        self.now += rp.LIFETIME
        self.api.delete.side_effect = [httpx.ConnectError('down'), None]
        with self.control.lock('requests', fcntl.LOCK_SH):
            with self.assertRaises(httpx.ConnectError):
                self.control.reap()
            with self.assertRaises(rp.Unavailable):
                self.control.ensure()
            self.control.reap()
        self.assertEqual(self.control.read()['history'], [[self.now-rp.LIFETIME, self.now]])

    def test_monthly_budget_and_unexpected_price(self):
        self.control.save({'lease': None, 'history': [[self.now-rp.MONTHLY, self.now]], 'paused': False})
        with self.assertRaises(rp.Unavailable):
            self.control.ensure()
        self.api.create.assert_not_called()
        self.now += 32 * 86400
        self.api.create.return_value['cost'] = 0.99
        with self.assertRaises(rp.Unavailable):
            self.control.ensure()
        self.api.delete.assert_called_once_with('abcd1234')

    def test_pause_requires_explicit_resume_and_survives_delete_failure(self):
        self.control.ensure()
        self.api.delete.side_effect = httpx.ConnectError('offline')
        with self.assertRaises(httpx.ConnectError):
            self.control.pause()
        self.assertTrue(self.control.status()['paused'])
        with self.assertRaises(rp.Unavailable):
            self.control.ensure()
        self.api.delete.side_effect = None
        self.control.reap()
        with self.assertRaises(rp.Unavailable):
            self.control.ensure()
        self.control.resume()
        self.control.ensure()
        self.assertEqual(self.api.create.call_count, 2)

    def test_initial_state_is_paused_and_status_never_allocates(self):
        (self.control.dir/'state.json').unlink()
        self.assertTrue(self.control.status()['paused'])
        with self.assertRaises(rp.Unavailable):
            self.control.ensure()
        self.api.create.assert_not_called()

    def test_catalog_checks_secure_capacity_with_cuda_floor(self):
        def transport(request):
            self.assertEqual(dict(request.url.params), {'product': 'POD', 'include': 'AVAILABILITY', 'cloud': 'SECURE', 'minCudaVersion': '12.8'})
            return httpx.Response(200, json={'gpus': [{'id': rp.GPU, 'secure': True, 'price': {'secure': .27}, 'availability': 'LOW'}]})
        api = rp.Api('dummy-key')
        with httpx.Client(base_url='https://api.runpod.io/v2/', transport=httpx.MockTransport(transport)) as client:
            api.http = client
            api.check_price()


class GatewayTest(unittest.IsolatedAsyncioTestCase):
    async def test_free_discovery_and_paid_stream_with_mock_transport(self):
        requests = []
        def upstream(req):
            requests.append(req)
            if req.url.path == '/v1/models':
                return httpx.Response(200, json={'data': [{'id': rp.MODEL}]})
            return httpx.Response(200, headers={'content-type': 'text/event-stream'}, content=b'data: [DONE]\n\n')

        with TemporaryDirectory() as temp, patch.object(rp, 'WEIGHT', Path(temp)/'test.gguf'), patch.object(rp, 'SIZE', 4):
            api = Mock()
            api.create.return_value = {'id': 'abc1', 'cost': .27, 'cloud': 'SECURE', 'gpu': {'id': rp.GPU, 'count': 1}}
            c = rp.Controller(api, Path(temp))
            c.resume()
            async with httpx.AsyncClient(transport=httpx.MockTransport(upstream)) as http:
                g = gateway.Gateway(c, http)
                app = web.Application()
                app.router.add_get('/v1/models', g.models)
                app.router.add_post('/v1/chat/completions', g.chat)
                async with TestClient(TestServer(app)) as client:
                    headers = {'Host': '127.0.0.1:18091', gateway.LOCAL_HEADER: '1'}
                    body = {'model': rp.MODEL, 'messages': [{'role':'user','content':'Review this documentation.'}], 'stream': True}
                    self.assertEqual((await client.get('/v1/models')).status, 200)
                    self.assertEqual((await client.post('/v1/chat/completions', json=body)).status, 403)
                    self.assertEqual((await client.post('/v1/chat/completions', headers=headers, json=body)).status, 409)
                    rp.WEIGHT.write_bytes(b'test')
                    self.assertEqual((await client.post('/v1/chat/completions', headers=headers, json={**body, 'tool_choice': 'required'})).status, 400)
                    api.create.assert_not_called()
                    c.pause()
                    paused = await client.post('/v1/chat/completions', headers=headers, json=body)
                    self.assertEqual(paused.status, 403)
                    self.assertIn('GPU review is paused', await paused.text())
                    api.create.assert_not_called()
                    c.resume()
                    resp = await client.post('/v1/chat/completions', headers=headers, json={**body, 'tools': [{'type': 'function'}], 'tool_choice': 'auto'})
                    self.assertEqual(await resp.read(), b'data: [DONE]\n\n')
                    self.assertEqual(requests[-1].url.host, 'abc1-8080.proxy.runpod.net')
                    self.assertNotIn('tools', json.loads(requests[-1].content))
                    self.assertNotIn('tool_choice', json.loads(requests[-1].content))
                    self.assertEqual(requests[-1].headers['Authorization'], 'Bearer '+c.read()['lease']['bearer'])
                    self.assertTrue(c.read()['lease']['ready'])
                    api.create.assert_called_once()

    async def test_weights_require_current_lease_token(self):
        c = Mock()
        c.read.return_value = {'lease': {'deadline': time.time()+30,'download':'one-lease-only'}}
        app = web.Application()
        app.router.add_get('/model.gguf', gateway.Gateway(c, None).weights)
        async with TestClient(TestServer(app)) as client:
            self.assertEqual((await client.get('/model.gguf')).status, 404)
            hdr = {'Authorization': 'Bearer one-lease-only'}
            resp = await client.get('/model.gguf', headers=hdr)
            self.assertEqual(resp.headers['X-Accel-Redirect'], '/_private/model.gguf')
            c.read.return_value['lease']['download'] = ''
            self.assertEqual((await client.get('/model.gguf', headers=hdr)).status, 404)

    def test_thinking_is_optional_and_bounded(self):
        request = {'model': rp.MODEL, 'messages': [{'role': 'user', 'content': 'Review this code.'}]}
        self.assertFalse(gateway.chat_body(request)['chat_template_kwargs']['enable_thinking'])
        thinking = gateway.chat_body({**request, 'chat_template_kwargs': {'enable_thinking': True, 'other': 'ignored'}, 'reasoning_budget': 99999})
        self.assertEqual(thinking['reasoning_budget'], 512)
        self.assertEqual(thinking['chat_template_kwargs'], {'enable_thinking': True})
