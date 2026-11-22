"""One durable, named Runpod lease, shared by the gateway and an independent reaper."""

import contextlib
import datetime as dt
import fcntl
import json
import os
import re
import secrets
import time
from pathlib import Path

import httpx


GPU = 'NVIDIA RTX A5000'
MODEL = 'qwen3.8-27b-review'
IDLE = 600
BOOT = 1800
LIFETIME = 7200
MONTHLY = 6 * 3600   # trial allowance; includes initialization and idle time
MAX_PRICE = 0.30     # USD/hour, compute only
IMAGE = 'ghcr.io/ggml-org/llama.cpp@sha256:ac11e113c61a57b0b0b86414aa8e1b61b9512dcedf8083c5fdedb35b379342cf'
ORIGIN = 'review-weights.shimme.rs'
WEIGHTS = json.loads(Path(__file__).with_name('model.json').read_text())
SHA = WEIGHTS['sha256']
WEIGHT = Path('/var/lib/runpod-review-weights') / WEIGHTS['file']
SIZE = WEIGHTS['bytes']
STATE = Path('/var/lib/runpod-review')


class Unavailable(Exception):
    """Safe to show to the caller; never include API bodies, keys or prompts."""


class Api:
    def __init__(self, key):
        self.http = httpx.Client(base_url='https://api.runpod.io/v2/', timeout=20,
                                 headers={'Authorization': 'Bearer ' + key}, trust_env=False)

    def check_price(self):
        data = self.http.get('catalog/gpus', params={'product': 'POD'}).raise_for_status().json()
        if not any(g['id'] == GPU and g.get('secure') and 0 < g['price']['secure'] <= MAX_PRICE
                   for g in data['gpus']):
            raise Unavailable('A5000 unavailable within trial price ceiling')

    def create(self, lease):
        # The public HTTPS origin serves exactly one file, with a per-lease bearer.
        # No Hetzner account, storage credentials or Runpod keys enter the Pod.
        script = f'''set -eu
umask 077
curl --fail --silent --show-error --proto '=https' --max-time {BOOT - 180} \\
  -H "Authorization: Bearer $WEIGHTS_TOKEN" -o /tmp/review.gguf https://{ORIGIN}/stock.gguf
echo '{SHA}  /tmp/review.gguf' | sha256sum -c -
unset WEIGHTS_TOKEN
exec /app/llama-server --model /tmp/review.gguf --alias {MODEL} --host 0.0.0.0 --port 8080 \\
  --parallel 1 --ctx-size 32768 --n-gpu-layers 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 \\
  --reasoning off --no-ui --no-slots --log-disable'''
        return self.http.post('pods', json={
            'name': lease['name'], 'cloud': 'SECURE', 'gpu': {'id': GPU, 'count': 1, 'minCudaVersion': '12.8'},
            'image': IMAGE, 'disk': 40, 'mounts': {}, 'ports': ['8080/http'],
            'entrypoint': ['/bin/sh', '-c'], 'cmd': [script],
            'env': {'WEIGHTS_TOKEN': lease['download'], 'LLAMA_API_KEY': lease['bearer']},
        }).raise_for_status().json()

    def find(self, name):
        params = {}
        while True:
            data = self.http.get('pods', params=params).raise_for_status().json()
            for pod in data['pods']:
                if pod['name'] == name:
                    return pod['id']
            if not data['pagination']['hasNextPage']:
                return None
            params['cursor'] = data['pagination']['nextCursor']

    def delete(self, pod_id):
        if not re.fullmatch(r'[a-zA-Z0-9_-]+', pod_id):
            raise Unavailable('Unexpected Pod identifier')
        resp = self.http.delete(f'pods/{pod_id}')
        if resp.status_code != 404:
            resp.raise_for_status()


class Controller:
    def __init__(self, api, directory=STATE, clock=time.time):
        self.api, self.dir, self.now = api, directory, clock

    @contextlib.contextmanager
    def lock(self, name, flags=fcntl.LOCK_EX):
        with (self.dir / name).open('a') as fd:
            fcntl.flock(fd, flags)
            yield

    def read(self):
        try:
            return json.loads((self.dir / 'state.json').read_text())
        except FileNotFoundError:
            return {'lease': None, 'history': []}

    def save(self, state):
        tmp = self.dir / 'state.tmp'
        with tmp.open('w') as fd:
            json.dump(state, fd)
            fd.flush()
            os.fsync(fd.fileno())
        tmp.replace(self.dir / 'state.json')
        fd = os.open(self.dir, os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def ensure(self):
        with self.lock('gate'):
            state = self.read()
            now = self.now()
            lease = state['lease']
            if lease:
                if not lease.get('id') or lease.get('closing') or now >= lease['deadline']:
                    raise Unavailable('Previous GPU lease needs cleanup; no new Pod requested')
                return lease
            month = dt.datetime.fromtimestamp(now, dt.timezone.utc).replace(day=1, hour=0, minute=0, second=0, microsecond=0).timestamp()
            state['history'] = [(s, e) for s, e in state['history'] if e > month]
            left = MONTHLY - sum(e - max(s, month) for s, e in state['history'])
            if left < IDLE:
                raise Unavailable('GPU trial allowance exhausted for this UTC month')
            self.api.check_price()
            lease = {'name': 'shimmers-review-' + secrets.token_hex(12), 'start': now, 'last': now,
                     'deadline': now + min(left, LIFETIME), 'bearer': secrets.token_urlsafe(32),
                     'download': secrets.token_urlsafe(32)}
            state['lease'] = lease
            self.save(state)  # BEFORE the POST: a timeout must never create a second Pod.
            try:
                pod = self.api.create(lease)
            except httpx.HTTPStatusError as exc:
                if exc.response.status_code in (400, 401, 402, 403, 404, 413, 422, 429):
                    state['lease'] = None  # documented rejection before placement
                    self.save(state)
                raise Unavailable(f'Runpod rejected or could not confirm allocation ({exc.response.status_code})') from None
            lease['id'] = pod['id']
            self.save(state)
            if not (re.fullmatch('[a-zA-Z0-9]+', lease['id']) and pod.get('cloud') == 'SECURE'
                    and pod.get('gpu', {}).get('id') == GPU and pod['gpu'].get('count') == 1
                    and 0 < pod.get('cost', 0) <= MAX_PRICE):
                self._close(state)
                raise Unavailable('Allocated Pod did not match the requested GPU or price')
            return lease

    def touch(self, lease, *, ready=False):
        with self.lock('gate'):
            state = self.read()
            current = state['lease']
            if current and current['name'] == lease['name'] and not current.get('closing'):
                current['last'] = self.now()
                if ready:
                    current['ready'] = True
                    current['download'] = ''  # revoke transfer access as soon as weights are loaded
                self.save(state)

    def _close(self, state):
        lease = state['lease']
        lease.update(closing=True, download='')
        self.save(state)
        pod_id = lease.get('id') or self.api.find(lease['name'])
        if not pod_id:
            # Ambiguous create: keep the unique name and block allocation until reconciled.
            raise Unavailable('Create outcome unknown: verify the lease in the Runpod console')
        self.api.delete(pod_id)
        state['history'].append([lease['start'], self.now()])
        state['lease'] = None
        self.save(state)

    def reap(self, *, failed_name=None):
        with self.lock('gate'):
            state = self.read()
            lease = state['lease']
            if not lease:
                return
            now = self.now()
            if (lease.get('closing') or now >= lease['deadline'] or lease['name'] == failed_name
                    or (not lease.get('ready') and now >= lease['start'] + BOOT)):
                self._close(state)
            elif now >= lease['last'] + IDLE:
                try:
                    with self.lock('requests', fcntl.LOCK_EX | fcntl.LOCK_NB):
                        self._close(state)
                except BlockingIOError:
                    pass  # includes callers waiting for another stream to finish
