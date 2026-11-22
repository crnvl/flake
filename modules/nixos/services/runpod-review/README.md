# Qwen3.6 on an on-demand GPU, through OpenCode

The Rust `runpod-gateway` serves the **same HauhauCS Qwen3.6-35B-A3B
Uncensored IQ4_XS weights** previously served by llama-swap on shimmers' CPU.
The existing `shimmers/qwen3.6-35b-a3b-uncensored` model ID stays valid.
shimmers stores the 18.7 GB GGUF, manages the paid lease and relays requests;
inference runs in **one Secure Cloud GPU Pod**: A5000 preferred, A40 fallback.
CPU serving is removed
on the next server rebuild. The old files are not deleted or re-downloaded.

## Setup without spending Runpod credit

1. Update/rebuild shimmers and both desktop devices. Pause/release any old
   GPU lease before updating (`gpu-review-stop`). Rust reads the Python
   controller's state and budget history. A legacy model lease is released,
   not reused for inference with different weights.
2. Keep the Runpod key with `catalog:read`, `pods:read`, `pods:write` in the
   existing root-owned `/etc/runpod-review/api-key` (mode 0600), or provision
   `hosts/shimmers/secrets/runpod-review-key.age`. It never reaches desktops
   or the Pod. Do not remove it while a managed Pod exists.
3. Run **`gpu-review-prepare`** on the desktop. It verifies the checksum of
   `/var/lib/llm/models/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-IQ4_XS.gguf`
   and starts the gateway. This does **not** allocate a Pod. A fresh shimmers
   host downloads the pinned original GGUF through `llm-model-fetch` first.
4. `review-weights.shimme.rs` must resolve to shimmers and have its ACME
   certificate. The HTTPS download endpoint authorizes a per-lease bearer
   and serves only that model; no directory listing or storage credentials.
   The chat endpoint is an SSH-forwarded Unix socket, not public.

## Interactive use

```sh
gpu-review          # permits requests, opens OpenCode in ~/gpu-review
gpu-review-status   # allocation/deadline/idle status; no paid request
gpu-review-stop     # optional immediate release + persistent pause
```

`~/gpu-review` now runs the same `redteam` agent and tools as `~/redteam`,
not the old text-only reviewer. The Runpod key and lease controls stay on
shimmers; OpenCode tools execute on **your desktop**, not in the GPU Pod.
The existing model can also be selected in `/models` in other projects.
`gpu-review` enables the gateway first; when it is paused, requests fail
with a non-retryable error. Merely opening the launcher or listing models
does not allocate compute. Your first prompt starts billing.

**Privacy boundary changed:** all model prompts, code, tool outputs,
reasoning and auxiliary summaries using this route are processed on Runpod,
not solely on Hetzner. `~/redteam` still restricts provider selection to
`shimmers`, but that provider is now a relay to the GPU. The optional
publicdocs helper remains a separate opt-in public-reference service.

The first response includes copying the existing GGUF from Hetzner and
loading it. The Pod checks its checksum, enables full CUDA offload, uses
64k context, and emits native JSON tool calls through the gateway. The
64k context is smaller than the previous CPU server's 128k; long sessions
may compact earlier. Each response is capped at 4096 output tokens, with
1024 thinking tokens. Select `#instant` to disable thinking; `#thinking`
explicitly enables it. Inference speed is not yet benchmarked on this path.

## Automatic cleanup and cost guards

- **Two-minute idle termination**, checked every 30 seconds. No need to run
  the stop command each time. Active streams and queued callers hold shared
  cross-process locks; disconnects release them and update the idle clock.
- **30-minute maximum lease**, including transfer/startup. This deadline
  takes priority over active work and can interrupt a request. The Pod's
  container process also has a bounded runtime.
- **Six GPU-hours per UTC month**, including startup and idle time, with
  **$0.60/hour compute ceiling** checked before and after allocation. The
  A5000 is selected first when available; otherwise the A40 is used if within
  the ceiling. No other GPU is selected. No persistent Runpod volume.
- A separate systemd reaper works even if the Rust HTTP gateway crashes.
  Failed deletes stay marked for retry; an ambiguous create is reconciled
  by its durable unique name before another allocation is allowed.

A 30-minute lease is at most about $0.30 planned compute (about $0.135 on
the A5000 at $0.27/hour, or $0.295 on the A40 at $0.59/hour), plus temporary
disk, tax and cleanup delays. These are **local controls, not a guaranteed
provider-enforced spending cap**. If shimmers is offline, credentials fail
or Runpod's API is unreachable, billing can continue. Keep Runpod auto-pay
off for the trial and verify deletion in its console after first use.

`gpu-review-stop` pauses new allocations even when deletion fails. It stays
paused across reboots until `gpu-review` is explicitly run again. Never
clear `/var/lib/runpod-review/state.json` to reset the budget or abandon an
allocation: it contains the identity and temporary tokens needed for cleanup.
`sudo runpod-review-status` prints only safe status, not those tokens.

## Rust development / tests (no paid GPU)

```sh
cargo test --locked
cargo clippy --locked --all-targets -- -D warnings
```

Tests use local HTTP stand-ins. Nix builds via `rustPlatform.buildRustPackage`
with `Cargo.lock` and runs these tests; Python is not used for Runpod lifecycle,
proxying, status, or cleanup. `opencode-public-docs.py` is an unrelated MCP
helper and is deliberately left alone.
