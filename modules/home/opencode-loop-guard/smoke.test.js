// Offline integration test against the installed OpenCode V2 executable. All
// inference is a local HTTP stand-in; no real providers or GPU credentials load.
import assert from "node:assert/strict"
import test from "node:test"
import { spawn } from "node:child_process"
import { once } from "node:events"
import { createServer } from "node:http"
import { mkdtemp, mkdir, writeFile, symlink, rm } from "node:fs/promises"
import { join, resolve } from "node:path"
import { fileURLToPath } from "node:url"
import { setTimeout as delay } from "node:timers/promises"

test("real OpenCode pauses after three unchanged results and resumes only on a new prompt", { timeout: 60000 }, async () => {
  const root = await mkdtemp(join(process.env.TMPDIR ?? "/tmp/opencode", "loop-guard-smoke-"))
  const modelCalls = []
  const mock = createServer(async (request, response) => {
    if (request.url !== "/v1/chat/completions") {
      response.writeHead(404).end()
      return
    }
    const chunks = []
    for await (const chunk of request) chunks.push(chunk)
    const body = JSON.parse(Buffer.concat(chunks).toString())
    modelCalls.push(body)
    const name = body.tools.find((tool) => tool.function.name === "loop_probe")?.function.name
    if (!name) {
      response.writeHead(400).end(JSON.stringify({ error: { message: "fixture tool missing" } }))
      return
    }
    response.writeHead(200, { "content-type": "text/event-stream" })
    const call = { index: 0, id: `call_${modelCalls.length}`, type: "function", function: { name, arguments: '{"value":"unchanged"}' } }
    response.end([
      { id: "test", object: "chat.completion.chunk", choices: [{ index: 0, delta: { role: "assistant", tool_calls: [call] }, finish_reason: null }] },
      { id: "test", object: "chat.completion.chunk", choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } },
    ].map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("") + "data: [DONE]\n\n")
  })
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
  await mkdir(join(configHome, "opencode", "plugins"))
  const guardPath = join(configHome, "opencode", "plugins", "shimmers-loop-guard")
  await symlink(resolve(fileURLToPath(new URL(".", import.meta.url))), guardPath)
  await mkdir(fixture)
  await writeFile(join(fixture, "index.js"), `export default {
    id: "loop-guard.test-fixture",
    async setup(ctx) {
      await ctx.session.hook("title", (event) => { event.result = "Loop guard test" })
      await ctx.tool.transform((editor) => editor.add({
        name: "loop_probe", description: "Offline loop test",
        input: { type: "object", properties: { value: { type: "string" } }, required: ["value"] },
        options: { codemode: false },
        execute: async () => ({ content: "identical result", metadata: { timestamp: Date.now() } }),
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
    const response = await fetch(url + path, body === undefined ? { headers } : {
      method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify(body),
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
  } finally {
    child.kill("SIGTERM")
    await once(child, "exit")
    await new Promise((done) => mock.close(done))
    await rm(root, { recursive: true, force: true })
  }
})
