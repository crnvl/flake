# OpenCode V2 tool-loop guard

Home Manager installs this local, dependency-free server plugin on chambers and
corridors. It is enabled globally for the `shimmers` provider, including the
`redteam` and `public-docs` workspaces. Copilot is unchanged.

Within a rolling window of twelve tool steps, it pauses after either:

- **Three repeats of the same tool/action/result**, even with other commands in
  between. Identical tool errors count too, so a failed command can't run forever.
- **Five attempts at the same action**, even if its output fluctuates.

After the second matching result (or third repeated action) a transient system
warning asks the model to change strategy. At the pause threshold, the saved tool
result/error includes a loop-guard explanation and execution stops before another
model request. A "Tool loop detected — run paused" notice is queued without
waking the session. Send a new prompt to reset the history and continue, or switch
models. The plugin never resumes a run on its own and never invokes a model.

V2 shell structured output contains `wallTimeSeconds`, `shellID`, `pid` and
`outputPath` in addition to stdout/exit status. The comparison ignores those
bookkeeping fields and uses structured stdout rather than presentation content
with changing truncation paths. Shell descriptions/timeouts are also ignored;
commands, quoting, working directories, background flags, stdout and exit status
remain meaningful. Other tools' input/result data is compared without changes.

Duplicate callbacks and identical calls within one assistant message count once.
Background launches are not completed results. Session state is isolated, memory
is bounded, and only hashes/tool names are retained (not inputs or outputs).

This detects tool loops, not repetition inside a single generated response or
loops with continually changing actions. Intentional polling, even if it is
making slow progress, can trigger the five-attempt limit; a new user prompt
explicitly permits retry. This is a spending/workflow safeguard, not a repair for
the underlying model's reasoning or tool-use reliability.

Tests: `node --test modules/home/opencode-loop-guard/{guard,smoke}.test.js`.
The smoke test uses OpenCode V2 and a local HTTP model stand-in with fake tool
results. It checks exact repeats, real V2 shell output with varying bookkeeping,
alternating calls and tool errors. It also checks that the warning reaches the
model, interruption does not auto-resume, and a new user prompt resets the guard.
Nix builds run both tests; no npm install or paid model request is needed.
