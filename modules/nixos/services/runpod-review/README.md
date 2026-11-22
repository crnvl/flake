# Interactive Qwen3.8 Aggressive trial through OpenCode

The flake installs an opt-in `~/gpu-review` workspace and commands on both
chambers and corridors. It runs the pinned HauhauCS Qwen3.8-27B Aggressive
Q4_K_P model on **one Secure Cloud A5000**, without changing the existing
CPU model or `~/redteam` configuration. It is a text-only chat/reviewer, not
an autonomous tool-using agent. Pasted text and chat history go to the Pod
through Runpod's HTTPS proxy. The API key remains on shimmers.

## One-time preparation — no GPU spend

1. Rebuild shimmers and the desktop. The `review-weights.shimme.rs` hostname
   must resolve to shimmers and have its ACME certificate. Only the weight
   download is public; the chat endpoint is an SSH-forwarded Unix socket.
2. Put the Runpod key (with `catalog:read`, `pods:read`, `pods:write`) into
   `/etc/runpod-review/api-key` on shimmers, root-owned and mode 0600. Keep
   Runpod auto-pay off. For a new key, enter it only into the hidden prompt:

   ```sh
   sudo install -d -m 0700 /etc/runpod-review
   sudo sh -c 'umask 077; systemd-ask-password "Runpod API key:" > /etc/runpod-review/api-key'
   ```

   Alternatively use `hosts/shimmers/secrets/runpod-review-key.age`, registered
   in `secrets.nix`, and rebuild. Never remove the key while a Pod exists.
3. On the desktop, run **`gpu-review-prepare`**. It downloads and verifies
   17.9 GB to `/var/lib/runpod-review-weights` on shimmers and starts the
   gateway. This does not create a Pod or spend Runpod credits. It can take
   several minutes. SSH must already trust the `shimme.rs` host key.

## Use it yourself

```sh
gpu-review          # enables allocation, opens OpenCode in ~/gpu-review
gpu-review-status   # reports paused/ready/Pod/deadline and estimated compute cost
gpu-review-stop     # pauses future allocations and terminates the managed Pod
```

**Only sending a prompt spends GPU credit.** The first prompt allocates the
Pod, transfers the weights from shimmers, and loads the model. It may be slow.
Subsequent messages reuse the running model. Opening OpenCode, the status
command, model discovery and the SSH tunnel do not allocate compute. No
benchmark script runs; you choose the prompts.

The model is `runpod-review/qwen3.8-27b-aggressive`. Thinking is disabled by
default for fast answers. In `/models`, choose its `thinking` variant to
compare reasoning (capped at 512 reasoning tokens within a 2048-token total
completion). Input context is 32k. These are experimental settings, not a
claim of proven cybersecurity performance or zero refusals.

Run `gpu-review-stop` when finished. Existing sessions cannot wake the Pod
again until you explicitly run `gpu-review`. It stays paused across reboots.
You may still use `opencode ~/gpu-review` when it is unpaused.

## Cost guards

- No A40 or expensive-card fallback: A5000 availability is checked before
  allocation, including Secure Cloud and CUDA compatibility. Price ceiling:
  **$0.30 per compute-hour**, actual rate checked again after allocation.
- **Two-minute idle cleanup**, starting after the last response finishes.
- **30-minute maximum lease**, including transfer and model load; it can
  interrupt a long response. Container runtime is bounded too.
- **Six GPU-hours per UTC month**, measured from allocation to deletion.
- Only temporary 40 GB container disk; no persistent Runpod storage.

At the ceiling, a 30-minute lease is approximately $0.15 compute, plus disk,
tax and cleanup delay. The reaper runs independently every 30 seconds. These
are local controls, **not a provider-enforced spending cap**: if shimmers is
offline, credentials fail or Runpod is unreachable, billing can continue.
Verify in the Runpod console after your first use that termination works.

If a create response is lost, the lease's unique name is saved first. No
second Pod is created until the old allocation is reconciled. Delete failures
remain marked for the reaper to retry. For an uncertain allocation, check
the console before clearing the lease; retain the budget history. State in
`/var/lib/runpod-review/state.json` contains temporary tokens — never share it.

Server equivalents: `sudo systemctl start runpod-review-pause`,
`sudo systemctl start runpod-review-resume`, and `sudo runpod-review-status`.
Resume does not allocate a Pod. Never delete the state directory to reset
the budget or abandon an allocation.

Offline tests: `python -m unittest -v test_review` from this directory with
`aiohttp` and `httpx`. Tests use a mock API; no key or paid GPU is needed.
