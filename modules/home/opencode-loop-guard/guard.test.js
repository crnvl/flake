import assert from "node:assert/strict"
import test from "node:test"
import plugin from "./index.js"
import { LoopGuard } from "./guard.js"

function result(step, changes = {}) {
  return {
    sessionID: "ses_a",
    messageID: `msg_${step}`,
    id: `call_${step}`,
    tool: "shell",
    input: { command: "grep example bundle" },
    status: "completed",
    result: { content: "same unhelpful output", metadata: { duration: step } },
    ...changes,
  }
}

test("pauses after three unchanged tool steps, not two", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  for (let step = 1; step <= 2; step++) {
    guard.observe(result(step))
    assert.equal(guard.begin("ses_a"), undefined)
  }
  guard.observe(result(3))
  assert.equal(guard.begin("ses_a"), "shell")
  const stored = JSON.stringify([...guard.sessions])
  assert.ok(!stored.includes("grep example") && !stored.includes("unhelpful output"))
})

test("genuinely changed arguments, output or tool do not count as identical results", () => {
  for (const change of [
    { input: { command: "different" } },
    { result: { content: "progress" } },
    { tool: "read" },
    { status: "error", error: { message: "failure" } },
  ]) {
    const guard = new LoopGuard()
    guard.begin("ses_a")
    guard.observe(result(1))
    guard.observe(result(2))
    guard.observe(result(3, change))
    assert.equal(guard.begin("ses_a"), undefined)
  }
})

test("actual V2 shell output ignores changing timing, truncation paths and bookkeeping IDs", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  for (let step = 1; step <= 3; step++) {
    guard.observe(result(step, {
      input: { command: "grep example bundle", description: `search ${step}`, timeout: step * 1000 },
      result: {
        output: { output: "same stdout", exitCode: 0, wallTimeSeconds: step / 7, outputPath: `/tmp/${step}`, shellID: `shell_${step}`, pid: step },
        content: [{ type: "text", text: `preview stored at /tmp/${step}` }],
      },
    }))
  }
  assert.equal(guard.begin("ses_a"), "shell")
})

test("keeps shell exit status, working directory, command quoting and changing stdout meaningful", () => {
  for (const change of [
    { input: { command: "grep example bundle", workdir: "/other" } },
    { input: { command: "echo 'a  b'" } },
    { result: { output: { output: "changed stdout", exitCode: 0 } } },
    { result: { output: { output: "same stdout", exitCode: 1 } } },
  ]) {
    const guard = new LoopGuard()
    guard.begin("ses_a")
    for (let step = 1; step <= 2; step++) guard.observe(result(step, {
      result: { output: { output: "same stdout", exitCode: 0, wallTimeSeconds: step } },
    }))
    guard.observe(result(3, change))
    assert.equal(guard.begin("ses_a"), undefined)
  }
})

test("catches alternating A/B loops and interleaved calls within one model step", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  for (let step = 1; step <= 3; step++) {
    guard.observe(result(step, { input: { command: "A" } }))
    guard.observe(result(step, { input: { command: "B" } }))
  }
  assert.equal(guard.begin("ses_a"), "shell")
  assert.match(guard.reason("ses_a"), /3 times/)
})

test("same action with fluctuating output is bounded at five attempts", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  for (let step = 1; step <= 4; step++) {
    guard.observe(result(step, { result: { content: `still waiting ${step}` } }))
    assert.equal(guard.begin("ses_a"), undefined)
  }
  guard.observe(result(5, { result: { content: "still waiting 5" } }))
  assert.equal(guard.begin("ses_a"), "shell")
  assert.match(guard.reason("ses_a"), /output changed/)
})

test("repeated identical errors also stop", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  for (let step = 1; step <= 3; step++) guard.observe(result(step, {
    status: "error", error: { message: "command not found", metadata: { at: step } },
  }))
  assert.equal(guard.begin("ses_a"), "shell")
  assert.match(guard.reason("ses_a"), /same error/)
})

test("an unrelated call cannot erase a pending warning", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  guard.observe(result(1))
  guard.observe(result(2))
  guard.observe(result(2, { input: { command: "different command in the same step" } }))
  assert.equal(guard.warn("ses_a"), true)
  assert.equal(guard.warn("ses_a"), false)
})

test("a rolling window forgets old results and does not penalize new work", () => {
  const guard = new LoopGuard({ window: 4 })
  guard.begin("ses_a")
  guard.observe(result(1))
  guard.observe(result(2))
  for (let step = 3; step <= 10; step++) guard.observe(result(step, { input: { command: `new work ${step}` } }))
  guard.observe(result(11))
  assert.equal(guard.begin("ses_a"), undefined)
  assert.equal(guard.sessions.get("ses_a").steps.length, 4)
})

test("background launches are not completed output", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  for (let step = 1; step <= 5; step++) guard.observe(result(step, {
    result: { content: "command running", metadata: { status: "running" } },
  }))
  assert.equal(guard.begin("ses_a"), undefined)
})

test("ignores metadata and object key ordering but preserves array ordering", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  guard.observe(result(1, { input: { b: 2, a: 1 }, result: { output: { y: 2, x: 1 } } }))
  guard.observe(result(2, { input: { a: 1, b: 2 }, result: { output: { x: 1, y: 2 } } }))
  guard.observe(result(3, { input: { a: 1, b: 2 }, result: { output: { y: 2, x: 1 }, metadata: { changed: true } } }))
  assert.equal(guard.begin("ses_a"), "shell")
  guard.reset("ses_a")
  guard.begin("ses_a")
  guard.observe(result(1, { input: { items: [1, 2] } }))
  guard.observe(result(2, { input: { items: [2, 1] } }))
  guard.observe(result(3, { input: { items: [1, 2] } }))
  assert.equal(guard.begin("ses_a"), undefined)
})

test("does not count duplicate callbacks or parallel calls in one step", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  for (let call = 0; call < 5; call++) guard.observe(result(1, { id: `call_${call}` }))
  assert.equal(guard.begin("ses_a"), undefined)
  guard.observe(result(2))
  assert.equal(guard.begin("ses_a"), undefined)
  guard.observe(result(3))
  assert.equal(guard.begin("ses_a"), "shell")
})

test("session isolation, explicit reset and bounded memory", () => {
  const guard = new LoopGuard({ capacity: 2 })
  guard.begin("ses_a")
  guard.begin("ses_b")
  for (let step = 1; step <= 3; step++) guard.observe(result(step))
  assert.equal(guard.begin("ses_b"), undefined)
  assert.equal(guard.begin("ses_a"), "shell")
  guard.reset("ses_a")
  assert.equal(guard.begin("ses_a"), undefined)
  guard.begin("ses_c")
  assert.equal(guard.sessions.size, 2)
})

test("defensive handling of non-JSON results", () => {
  const guard = new LoopGuard()
  guard.begin("ses_a")
  guard.observe(result(1, { result: {} }))
  guard.observe(result(2, { result: { output: 1n } }))
  assert.equal(guard.begin("ses_a"), undefined)
})

test("plugin persists a notice, interrupts before dispatch and resets on user input", async () => {
  const hooks = {}
  const actions = []
  const ctx = {
    options: {},
    tool: { hook: async (name, callback) => {
      hooks[name] = callback
      return { dispose: async () => {} }
    } },
    session: {
      hook: async (name, callback) => {
        hooks[name] = callback
        return { dispose: async () => {} }
      },
      synthetic: async (input) => actions.push(["notice", input]),
      interrupt: async (input) => actions.push(["interrupt", input]),
    },
  }
  const cleanup = await plugin.setup(ctx)
  const request = { sessionID: "ses_a", model: { providerID: "shimmers" }, system: [] }
  await hooks.context(request)
  for (let step = 1; step <= 3; step++) hooks["execute.after"](result(step))
  await assert.rejects(hooks.context(request), /Tool loop guard paused/)
  assert.equal(actions[0][0], "notice")
  assert.equal(actions[0][1].resume, false)
  assert.deepEqual(actions[1], ["interrupt", { sessionID: "ses_a", resume: false }])
  hooks.prompt({ sessionID: "ses_a" })
  await hooks.context(request)
  for (let step = 1; step <= 3; step++) hooks["execute.after"](result(step))
  await hooks.context({ ...request, model: { providerID: "github-copilot" } })
  assert.equal(actions.length, 2)
  await cleanup()
})

test("warns after a repeat, giving the model a chance to change strategy", async () => {
  const hooks = {}
  const hook = async (name, callback) => {
    hooks[name] = callback
    return { dispose: async () => {} }
  }
  await plugin.setup({ options: {}, session: { hook }, tool: { hook } })
  const request = () => ({ sessionID: "ses_a", model: { providerID: "shimmers" }, system: [] })
  await hooks.context(request())
  hooks["execute.after"](result(1))
  hooks["execute.after"](result(2))
  const warned = request()
  await hooks.context(warned)
  assert.match(warned.system[0].text, /materially different approach/)
  const next = request()
  await hooks.context(next)
  assert.equal(next.system.length, 0, "warning is transient, not duplicated on retries")
})
