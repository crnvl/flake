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

test("changing arguments, output or tool breaks a streak", () => {
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
    guard.observe(result(4))
    assert.equal(guard.begin("ses_a"), undefined)
  }
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
  const request = { sessionID: "ses_a", model: { providerID: "shimmers" } }
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
