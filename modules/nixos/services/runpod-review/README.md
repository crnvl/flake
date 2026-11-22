# shimmers GPU review trial

`~/gpu-review` on chambers/corridors uses a stock Qwen3.8-27B text reviewer.
The first chat request leases **one Secure Cloud RTX A5000**. Discovery and
opening the SSH tunnel are free. Review inputs (including pasted code and
conversation history) go through Runpod's HTTPS proxy to the Pod. There is
no shell, MCP, tool execution or automatic fallback in the review workspace.

## Prepare (no paid requests)

1. Rebuild shimmers and the desktop. Point `review-weights.shimme.rs` at
   shimmers (the existing wildcard normally suffices) and allow ACME to issue
   its certificate. The chat endpoint itself is only an SSH-forwarded socket.
2. On shimmers, run `sudo systemctl start runpod-review-weights`. This is a
   one-time 16.6 GB verified download to `/var/lib/runpod-review-weights`, not
   a Pod allocation. Wait for success before using the reviewer.
3. Create a Runpod API key with `catalog:read`, `pods:read`, `pods:write`.
   Leave automatic balance reload off for the $10 trial. On **shimmers**, store
   the raw key in a root-owned mode-0600 file (enter it only in the hidden prompt):

   ```sh
   sudo install -d -m 0700 /etc/runpod-review
   sudo sh -c 'umask 077; systemd-ask-password "Runpod API key:" > /etc/runpod-review/api-key'
   sudo systemctl start runpod-review
   systemctl is-active runpod-review runpod-review-reap.timer
   ```

   Alternatively, provision `hosts/shimmers/secrets/runpod-review-key.age` (raw
   key, recipient policy in `secrets.nix`) and rebuild. Only the control service
   and cleanup jobs on shimmers receive this credential. Do not remove it while
   a managed Pod exists; the reaper needs it to terminate the Pod.
4. On the desktop, `systemctl --user restart runpod-review-tunnel` (use a
   previously verified SSH host key for `shimme.rs`). Check
   `curl -fsS http://127.0.0.1:18091/v1/models`. This must work before testing
   chat and does **not** contact Runpod. Verify that
   `curl -sS -o /dev/null -w '%{http_code}\n' https://review-weights.shimme.rs/stock.gguf`
   returns 404 without a token.

## First paid test

Run `opencode ~/gpu-review` and send a short review prompt. While the request
is pending look for `shimmers-review-…` in the Runpod console. Each fresh Pod
pulls only the pinned stock GGUF over HTTPS with a single-lease bearer,
verifies the hash, then serves an authenticated 32k single-slot GPU model.
Only temporary container storage is requested. Cold start includes the
transfer and load; no persistent Runpod volume is needed. If capacity or the
price check fails there is no upgrade to a more expensive card. Runpod's HTTP
proxy can time out if the engine takes over 100s to send its first bytes;
start the trial with a short prompt.

The timer runs every 30s. It **terminates** the Pod 10 minutes after the last
request completes (including streaming), or after 30 minutes of unsuccessful
startup. Hard limits take precedence over active requests: two hours per
lease and six hours total per UTC month. At the $0.30/hour compute ceiling
six hours is about $1.80, plus disk, tax and timer/API delays. These are local
controls, not a provider-enforced spending limit: if shimmers is offline,
its credentials fail or Runpod is unreachable, billing can continue. Check
the console after the first test to confirm the Pod disappears.

For immediate release, stop the gateway to prevent new requests and run:

```sh
sudo systemctl stop runpod-review
sudo systemctl start runpod-review-release
```

Restart `runpod-review` when needed. A delete failure leaves the lease marked
for retry. If a creation response was lost, the reaper searches by its unique
persisted name; there are no blind create retries. If Runpod never created it,
the controller stays blocked. Stop the gateway, confirm the named Pod is absent
in the console, and clear **only** `lease` to `null` in
`/var/lib/runpod-review/state.json` under the `gate` file lock (preserve
`history`). That file contains temporary access tokens; do not share it.

Offline lifecycle tests: run `python -m unittest -v test_review` from this
directory with `aiohttp` and `httpx` installed. No credentials or GPU required.
