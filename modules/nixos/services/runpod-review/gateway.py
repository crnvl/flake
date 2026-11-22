"""A text-only OpenAI chat endpoint. Only a valid POST can allocate compute."""

import asyncio
import fcntl
import hmac
import logging
import os
import sys
import time
from pathlib import Path

import httpx
from aiohttp import web

import lease as rp


SOCKET = Path('/run/runpod-review/chat.sock')
LOCAL_HEADER = 'X-Shimmers-GPU-Review'


def chat_body(body):
    if not isinstance(body, dict) or body.get('model') != rp.MODEL:
        raise ValueError('Select the Qwen3.8 Aggressive GPU reviewer')
    # OpenCode sometimes advertises its built-ins even for a tool-less model.
    # Drop optional declarations via the explicit payload allowlist below;
    # refuse forced calls and transcripts with actual calls/results.
    if (body.get('tool_choice') not in (None, 'none', 'auto')
            or body.get('function_call') not in (None, 'none', 'auto') or body.get('n', 1) != 1):
        raise ValueError('Reviewer accepts a single text conversation without tools')
    msgs = body.get('messages')
    if not isinstance(msgs, list) or not 0 < len(msgs) <= 512:
        raise ValueError('Invalid messages')
    clean = []
    for msg in msgs:
        if (not isinstance(msg, dict) or msg.get('role') not in ('system', 'user', 'assistant')
                or msg.get('tool_calls') or msg.get('function_call')):
            raise ValueError('Only text messages are accepted')
        text = msg.get('content')
        if isinstance(text, list) and all(isinstance(p, dict) and p.get('type') == 'text' and isinstance(p.get('text'), str) for p in text):
            text = '\n'.join(p['text'] for p in text)
        if not isinstance(text, str):
            raise ValueError('Only text messages are accepted')
        clean.append({'role': msg['role'], 'content': text})
        if msg.get('role') == 'assistant' and 'reasoning_content' in msg:
            if not isinstance(msg['reasoning_content'], str):
                raise ValueError('Invalid reasoning history')
            clean[-1]['reasoning_content'] = msg['reasoning_content']
    limit = body.get('max_tokens', body.get('max_completion_tokens', 2048))
    if type(limit) is not int or limit <= 0 or type(body.get('stream', False)) is not bool:
        raise ValueError('Invalid completion options')
    result = {'model': rp.MODEL, 'messages': clean, 'max_tokens': min(limit, 2048), 'stream': body.get('stream', False)}
    thinking = body.get('chat_template_kwargs', {}).get('enable_thinking', False)
    if type(thinking) is not bool:
        raise ValueError('Invalid thinking setting')
    result['chat_template_kwargs'] = {'enable_thinking': thinking}
    if thinking:
        result['reasoning_budget'] = 512
    if result['stream'] and body.get('stream_options', {}).get('include_usage') is True:
        result['stream_options'] = {'include_usage': True}
    return result


class Gateway:
    def __init__(self, control, http):
        self.control, self.http = control, http
        self.slot = asyncio.Lock()

    async def models(self, request):
        return web.json_response({'object': 'list', 'data': [{'id': rp.MODEL, 'object': 'model', 'owned_by': 'shimmers'}]})

    async def weights(self, request):
        # nginx serves the bytes via its internal exact-match alias, never a user-supplied path.
        current = self.control.read()['lease']
        key = current and current.get('download')
        if not key or current['deadline'] <= time.time() or not hmac.compare_digest(
            request.headers.get('Authorization', '').encode(), f'Bearer {key}'.encode()
        ):
            raise web.HTTPNotFound()
        return web.Response(headers={'X-Accel-Redirect': '/_private/model.gguf'})

    async def ready(self, lease, url, headers):
        deadline = min(lease['deadline'], lease['start'] + rp.BOOT)
        while time.time() < deadline:
            current = self.control.read()['lease']
            if not current or current['name'] != lease['name'] or current.get('closing'):
                raise rp.Unavailable('Pod lease ended during startup')
            try:
                resp = await self.http.get(url + '/v1/models', headers=headers, timeout=5)
                if resp.is_success and any(m.get('id') == rp.MODEL for m in resp.json()['data']):
                    return
            except (httpx.HTTPError, KeyError, ValueError):
                pass  # assignment, TLS proxy, weight copy and model load are asynchronous
            await asyncio.sleep(5)
        raise rp.Unavailable('GPU startup deadline reached')

    async def chat(self, request):
        # This is a local SSH forward. Reject browser-originated requests, including DNS rebinding.
        if ('Origin' in request.headers or request.headers.get('Host') != '127.0.0.1:18091'
                or request.headers.get(LOCAL_HEADER) != '1'):
            raise web.HTTPForbidden()
        if request.content_type != 'application/json':
            raise web.HTTPUnsupportedMediaType()
        try:
            body = chat_body(await request.json())
        except (ValueError, AttributeError, TypeError) as exc:
            raise web.HTTPBadRequest(text='Invalid text review request') from exc
        if not rp.WEIGHT.is_file() or rp.WEIGHT.stat().st_size != rp.SIZE:
            raise web.HTTPConflict(text='Run gpu-review-prepare to cache the weights on shimmers first')

        try:
            # Take this BEFORE queueing: the reaper can distinguish active/pending work
            # from a dead client. A crashed process automatically releases its locks.
            with self.control.lock('requests', fcntl.LOCK_SH | fcntl.LOCK_NB):
                async with self.slot:
                    lease = await asyncio.to_thread(self.control.ensure)
                    url = f'https://{lease["id"]}-8080.proxy.runpod.net'
                    headers = {'Authorization': 'Bearer ' + lease['bearer']}
                    if not lease.get('ready'):
                        try:
                            await self.ready(lease, url, headers)
                            await asyncio.to_thread(self.control.touch, lease, ready=True)
                        except (Exception, asyncio.CancelledError):
                            await asyncio.to_thread(self.control.reap, failed_name=lease['name'])
                            raise
                    try:
                        async with self.http.stream('POST', url + '/v1/chat/completions', json=body, headers=headers) as upstream:
                            if not upstream.is_success:
                                raise rp.Unavailable(f'GPU inference returned HTTP {upstream.status_code}')
                            result = web.StreamResponse(headers={'Content-Type': upstream.headers['Content-Type'],
                                                                 'Cache-Control': 'no-store'})
                            await result.prepare(request)
                            async for chunk in upstream.aiter_bytes():
                                await result.write(chunk)
                            await result.write_eof()
                            return result
                    finally:
                        await asyncio.to_thread(self.control.touch, lease)
        except rp.Unavailable as exc:
            raise web.HTTPConflict(text=str(exc)) from None
        except (httpx.HTTPError, BlockingIOError):
            # Do not emit upstream error bodies/credentials or trigger blind client retries.
            raise web.HTTPConflict(text='Runpod unavailable; check the lease on shimmers') from None


async def serve(control):
    async with httpx.AsyncClient(timeout=httpx.Timeout(120, connect=10), trust_env=False) as http:
        gateway = Gateway(control, http)
        chat = web.Application(client_max_size=1024 * 1024)
        chat.add_routes([web.get('/v1/models', gateway.models), web.post('/v1/chat/completions', gateway.chat)])
        weights = web.Application()
        weights.add_routes([web.get('/model.gguf', gateway.weights)])
        c, w = [web.AppRunner(app, access_log=None, handler_cancellation=True) for app in (chat, weights)]
        await c.setup()
        await w.setup()
        SOCKET.unlink(missing_ok=True)
        await web.UnixSite(c, str(SOCKET)).start()
        SOCKET.chmod(0o660)
        await web.TCPSite(w, '127.0.0.1', 18092).start()
        await asyncio.Event().wait()


if __name__ == '__main__':
    if sys.argv[1:] == ['status']:
        import json
        print(json.dumps(rp.Controller(None).status(), indent=2))
        sys.exit(0)
    key = (Path(os.environ['CREDENTIALS_DIRECTORY']) / 'runpod-key').read_text().strip()
    if not key:
        sys.exit('Missing Runpod key')
    controller = rp.Controller(rp.Api(key))
    if sys.argv[1:] in (['reap'], ['release'], ['pause'], ['resume']):
        try:
            if sys.argv[1] == 'pause':
                controller.pause()
            elif sys.argv[1] == 'resume':
                controller.resume()
            else:
                lease = controller.read()['lease']
                controller.reap(failed_name=lease['name'] if lease and sys.argv[1] == 'release' else None)
        except (httpx.HTTPError, rp.Unavailable) as exc:
            logging.error('GPU cleanup unconfirmed (%s); timer will retry. Check Runpod console.', type(exc).__name__)
            sys.exit(1)
    else:
        asyncio.run(serve(controller))
