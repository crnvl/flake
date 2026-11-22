# OpenCode V2 tool-loop guard

Home Manager installs this local, dependency-free server plugin on chambers and
corridors. It is enabled globally for the `shimmers` provider, including the
`redteam` and `public-docs` workspaces. Copilot is unchanged.

After three consecutive tool steps with the same tool, JSON arguments and result,
it stops the session before another model request. The third result stays in the
history with a loop-guard explanation, and a "Tool loop detected — run paused"
notice is queued without waking the session. Send a new prompt
to reset the streak and continue, or switch models. The plugin never resumes a run
on its own and never invokes a model.

Only successful results count. Tool timing metadata is ignored; changed inputs or
results break the streak. Duplicate callbacks and identical calls within one
assistant message count once. Session state is isolated, memory is bounded, and
only hashes/tool names are retained (not inputs or outputs).

This detects exact repeated-tool loops, not reasoning-only repetition, alternating
tool cycles or calls with changing arguments/results. Intentional polling with
unchanged results can also trigger it; a new user prompt explicitly permits retry.

Tests: `node --test modules/home/opencode-loop-guard/{guard,smoke}.test.js`.
The smoke test uses OpenCode V2 and a local HTTP model stand-in with fake tool
results. It checks that exactly three model calls happen, that interruption
does not auto-resume, and that a new user prompt resets the guard. Nix builds
run both tests; no npm install or paid model request is needed.
