// Offline integration test against the installed OpenCode V2 executable. All
// inference is a local HTTP stand-in; no real providers or GPU credentials load.
import assert from "node:assert/strict"
import test from "node:test"
import { spawn } from "node:child_process"
import { once } from "node:events"
import { createServer } from "node:http"
import { mkdtemp, mkdir, writeFile, readFile, copyFile, chmod, rm } from "node:fs/promises"
import { join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { setTimeout as delay } from "node:timers/promises"

test("real OpenCode pauses after three unchanged results and resumes only on a new prompt", { timeout: 60000 }, async (t) => {
  const root = await mkdtemp(join(process.env.TMPDIR ?? "/tmp/opencode", "loop-guard-smoke-"))
  const modelCalls = []
  let scenario = "identical"
  let offset = 0
  const mock = createServer(async (request, response) => {
    if (request.url !== "/v1/chat/completions") {
      response.writeHead(404).end()
      return
    }
    const chunks = []
    for await (const chunk of request) chunks.push(chunk)
    const body = JSON.parse(Buffer.concat(chunks).toString())
    modelCalls.push(body)
    if (modelCalls.length - offset > 20) {
      response.writeHead(200, { "content-type": "text/event-stream" })
      response.end(`data: ${JSON.stringify({ id: "limit", object: "chat.completion.chunk", choices: [{ index: 0, delta: { content: "Fixture safety stop" }, finish_reason: "stop" }] })}\n\ndata: [DONE]\n\n`)
      return
    }
    const shellScenario = scenario === "shell"
    const name = body.tools.find((tool) => tool.function.name === (shellScenario ? "shell" : "loop_probe"))?.function.name
    if (!name) {
      response.writeHead(400).end(JSON.stringify({ error: { message: "fixture tool missing" } }))
      return
    }
    response.writeHead(200, { "content-type": "text/event-stream" })
    const step = modelCalls.length - offset
    const args = shellScenario
      ? { command: "grep example bundle", description: `attempt ${step}`, timeout: step * 1000 }
      : { value: scenario === "alternating" ? (step % 2 ? "A" : "B") : scenario }
    const call = { index: 0, id: `call_${modelCalls.length}`, type: "function", function: { name, arguments: JSON.stringify(args) } }
    response.end([
      { id: "test", object: "chat.completion.chunk", choices: [{ index: 0, delta: { role: "assistant", tool_calls: [call] }, finish_reason: null }] },
      { id: "test", object: "chat.completion.chunk", choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } },
    ].map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("") + "data: [DONE]\n\n")
  })
  // Setup can fail before the child/finally block below (e.g. a read-only Nix
  // source). Never leave a listening fixture server hanging the test process.
  t.after(() => { mock.closeAllConnections(); mock.close() })
  mock.listen(0, "127.0.0.1")
  await once(mock, "listening")
  const mockPort = mock.address().port
  const portReservation = createServer()
  portReservation.listen(0, "127.0.0.1")
  await once(portReservation, "listening")
  const port = portReservation.address().port
  await new Promise((done) => portReservation.close(done))

  const configHome = join(root, "config")
  const fixture = join(root, "fixture")
  await mkdir(join(configHome, "opencode"), { recursive: true })
  // Match Nix deployment: each revision has a unique immutable directory and
  // config points directly at it, never through a retargeted package symlink.
  const guardPath = join(root, "guard-v1")
  const guardUpgrade = join(root, "guard-v2")
  for (const target of [guardPath, guardUpgrade]) {
    await mkdir(target)
    for (const file of ["index.js", "guard.js", "package.json"]) {
      await copyFile(resolve(fileURLToPath(new URL(file, import.meta.url))), join(target, file))
    }
  }
  const upgraded = (await readFile(join(guardUpgrade, "index.js"), "utf8"))
    .replace("Tool loop guard paused this run:", "Tool loop guard revision 2 paused this run:")
  // copyFile preserves the Nix store's read-only mode.
  await chmod(join(guardUpgrade, "index.js"), 0o600)
  await writeFile(join(guardUpgrade, "index.js"), upgraded)
  await mkdir(fixture)
  await writeFile(join(fixture, "index.js"), `export default {
    id: "loop-guard.test-fixture",
    async setup(ctx) {
      await ctx.session.hook("title", (event) => { event.result = "Loop guard test" })
      await ctx.tool.transform((editor) => editor.add({
        name: "loop_probe", description: "Offline loop test",
        input: { type: "object", properties: { value: { type: "string" } }, required: ["value"] },
        options: { codemode: false },
        execute: async (input) => {
          if (input.value === "errors") throw new Error("fixture failed with the same error")
          return { content: "identical result", metadata: { timestamp: Date.now() } }
        },
      }))
      await ctx.tool.transform((editor) => editor.add({
        name: "shell", description: "Mock of the V2 shell; executes no commands",
        input: { type: "object", properties: { command: { type: "string" }, description: { type: "string" }, timeout: { type: "number" } }, required: ["command"] },
        output: { type: "object", additionalProperties: true },
        options: { codemode: false },
        execute: async () => ({
          content: [{ type: "text", text: "identical stdout" }],
          output: { output: "identical stdout", exitCode: 0, wallTimeSeconds: Math.random(), shellID: String(Math.random()), outputPath: String(Math.random()) },
          metadata: { status: "completed" },
        }),
      }))
    },
  }`)
  await writeFile(join(configHome, "opencode", "opencode.json"), JSON.stringify({
    model: "shimmers/loop-test",
    plugins: [{ package: guardPath, options: { providerID: "shimmers" } }, fixture],
    warming: false,
    compaction: { auto: false },
    policies: [
      { action: "provider.use", resource: "*", effect: "deny" },
      { action: "provider.use", resource: "shimmers", effect: "allow" },
    ],
    providers: { shimmers: {
      package: "@opencode/ai/providers/openai-compatible",
      settings: { baseURL: `http://127.0.0.1:${mockPort}/v1` },
      models: { "loop-test": { capabilities: { tools: true, input: ["text"], output: ["text"] }, limit: { context: 65536, output: 4096 } } },
    } },
  }))
  const env = {
    ...process.env,
    HOME: root,
    XDG_CONFIG_HOME: configHome,
    XDG_DATA_HOME: join(root, "data"),
    XDG_CACHE_HOME: join(root, "cache"),
    XDG_STATE_HOME: join(root, "state"),
    OPENCODE_DISABLE_MODELS_FETCH: "true",
    OPENCODE_DISABLE_AUTOUPDATE: "true",
    OPENCODE_PASSWORD: "offline-loop-guard-test",
  }
  delete env.OPENCODE_CONFIG
  delete env.OPENCODE_CONFIG_CONTENT
  delete env.OPENCODE_DB
  const child = spawn(process.env.OPENCODE_BIN ?? "opencode", ["serve", "--hostname", "127.0.0.1", "--port", String(port)], { cwd: root, env })
  let logs = ""
  child.stdout.on("data", (chunk) => { logs += chunk })
  child.stderr.on("data", (chunk) => { logs += chunk })
  const url = `http://127.0.0.1:${port}`
  const headers = { authorization: `Basic ${Buffer.from("opencode:offline-loop-guard-test").toString("base64")}` }
  async function api(path, body) {
    const response = await fetch(url + path, body === undefined ? { headers, signal: AbortSignal.timeout(15000) } : {
      method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    })
    assert.ok(response.ok, `${path}: ${response.status} ${await response.clone().text()}\n${logs}`)
    if (response.status === 204) return
    const output = await response.json()
    return output && "data" in output ? output.data : output
  }
  try {
    let ready = false
    for (let attempt = 0; attempt < 100; attempt++) {
      ready = await fetch(url + "/api/info", { headers }).then((r) => r.ok).catch(() => false)
      if (ready) break
      await delay(100)
    }
    assert.ok(ready, logs)
    const session = await api("/api/session", { title: "Loop guard smoke" })
    await api(`/api/session/${session.id}/prompt`, { text: "Repeat loop_probe with value unchanged." })
    await api(`/api/experimental/session/${session.id}/wait`, {})
    const plugins = await api("/api/plugin")
    assert.equal(plugins.filter((plugin) => plugin.id === "shimmers.loop-guard").length, 1, JSON.stringify(plugins) + logs)
    assert.equal(modelCalls.length, 3, logs)
    const history = await api(`/api/session/${session.id}/context`)
    const serialized = JSON.stringify(history)
    assert.ok(serialized.includes("Tool loop guard:"), serialized + logs)
    const tools = history.filter((message) => message.type === "assistant").flatMap((message) => message.content.filter((part) => part.type === "tool"))
    assert.equal(tools.length, 3)
    assert.ok(tools.every((tool) => tool.state.status === "completed" && JSON.stringify(tool.state.content).includes("identical result")))
    assert.ok(history.some((message) => message.type === "idle" && message.outcome === "interrupted"))
    // Interruption must not consume its own synthetic notice and resume the loop.
    await delay(300)
    assert.equal(modelCalls.length, 3, logs)
    await api(`/api/session/${session.id}/prompt`, { text: "Try again; I am explicitly resuming the test." })
    await api(`/api/experimental/session/${session.id}/wait`, {})
    assert.equal(modelCalls.length, 6, logs)
    const configPath = join(configHome, "opencode", "opencode.json")
    const config = JSON.parse(await readFile(configPath, "utf8"))
    config.plugins[0].package = guardUpgrade
    await writeFile(configPath, JSON.stringify(config))
    await api("/api/location/reload", {})
    // The original guard missed all of these even though it passed the simple
    // fixture above: real V2 shell timing fields, A/B cycles and tool failures.
    for (const [mode, expectedCalls] of [["shell", 3], ["alternating", 5], ["errors", 3]]) {
      scenario = mode
      offset = modelCalls.length
      const session = await api("/api/session", { title: `Loop guard ${mode}` })
      await api(`/api/session/${session.id}/prompt`, { text: `Test ${mode} loop.` })
      await api(`/api/experimental/session/${session.id}/wait`, {})
      assert.equal(modelCalls.length - offset, expectedCalls, `${mode}\n${logs}`)
      const history = await api(`/api/session/${session.id}/context`)
      assert.ok(JSON.stringify(history).includes("Tool loop guard:"), `${mode}: ${JSON.stringify(history)}\n${logs}`)
      assert.ok(history.some((message) => message.type === "idle" && message.outcome === "interrupted"), `${mode}: ${JSON.stringify(history)}`)
      const inbox = await api(`/api/session/${session.id}/inbox`)
      assert.ok(JSON.stringify(inbox).includes("Tool loop guard revision 2 paused this run:"), "upgrade must activate the new entrypoint, not cached revision 1")
      const warning = modelCalls.slice(offset).some((body) => JSON.stringify(body.messages).includes("Loop guard warning:"))
      assert.ok(warning, `${mode}: should warn before pausing`)
      await delay(200)
      assert.equal(modelCalls.length - offset, expectedCalls, "must not resume itself")
    }
  } finally {
    child.kill("SIGTERM")
    await once(child, "exit")
    await new Promise((done) => mock.close(done))
    await rm(root, { recursive: true, force: true })
  }
})
