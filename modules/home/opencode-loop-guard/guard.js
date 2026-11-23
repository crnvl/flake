import { createHash } from "node:crypto"

function canonical(value) {
  return JSON.stringify(value, (_, item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return item
    return Object.fromEntries(Object.keys(item).sort().map((key) => [key, item[key]]))
  })
}

const shellTools = new Set(["shell", "bash", "functions_shell"])

function without(value, keys) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return value
  return Object.fromEntries(Object.entries(value).filter(([key]) => !keys.includes(key)))
}

function inputFor(event) {
  if (!shellTools.has(event.tool)) return event.input
  // These change the presentation/wait policy, not the command's meaning.
  // Keep the command verbatim: normalizing shell whitespace can alter quotes.
  return without(event.input, ["description", "timeout"])
}

function outcomeFor(event) {
  if (event.status === "error") return { error: event.error.message }
  if (shellTools.has(event.tool) && typeof event.result.output?.output === "string") {
    // V2 shell returns timing and per-execution IDs INSIDE structured output.
    // Prefer this to presentation content, which can contain truncation paths.
    return without(event.result.output, ["wallTimeSeconds", "outputPath", "shellID", "pid"])
  }
  return { content: event.result.content, output: event.result.output }
}

function hash(value) {
  return createHash("sha256").update(canonical(value)).digest("hex")
}

// Retain only hashes, counts and tool names, never arguments or tool output.
export class LoopGuard {
  constructor({ threshold = 3, inputThreshold = 5, window = 12, capacity = 1000 } = {}) {
    this.threshold = threshold
    this.inputThreshold = inputThreshold
    this.window = window
    this.capacity = capacity
    this.sessions = new Map()
  }

  reset(sessionID) {
    this.sessions.delete(sessionID)
  }

  begin(sessionID) {
    const state = this.sessions.get(sessionID) ?? { steps: [] }
    // Keep the most recently active sessions; bound memory even without idle events.
    this.sessions.delete(sessionID)
    this.sessions.set(sessionID, state)
    if (this.sessions.size > this.capacity) this.reset(this.sessions.keys().next().value)
    return state.paused ? state.tool : undefined
  }

  observe(event) {
    const state = this.sessions.get(event.sessionID)
    if (!state || state.paused) return
    if (event.status === "completed") {
      // Background job IDs aren't completed output; don't mistake launches for
      // results or interfere with the job's completion notification.
      if (event.result.metadata?.status === "running") return
      if (event.result.content === undefined && event.result.output === undefined) return
    }
    let input, outcome
    try {
      input = hash({ tool: event.tool, input: inputFor(event) })
      outcome = hash({ input, status: event.status, outcome: outcomeFor(event) })
    } catch {
      // Non-JSON plugin results must not break a user's run or count as a loop.
      return
    }

    let step = state.steps.find((step) => step.id === event.messageID)
    if (!step) {
      step = { id: event.messageID, inputs: new Set(), outcomes: new Set() }
      state.steps.push(step)
      if (state.steps.length > this.window) state.steps.shift()
    }
    // Duplicate callbacks and parallel/nested calls in ONE model step count
    // once. Bound each step too (a Code Mode loop may make many nested calls).
    if (step.outcomes.has(outcome) || step.outcomes.size >= 128) return
    step.inputs.add(input)
    step.outcomes.add(outcome)

    const repeats = state.steps.filter((step) => step.outcomes.has(outcome)).length
    const attempts = state.steps.filter((step) => step.inputs.has(input)).length
    state.warning ||= repeats >= 2 || attempts >= 3
    if (repeats >= this.threshold) {
      state.reason = `${event.tool} returned the same ${event.status === "error" ? "error" : "result"} `
        + `${repeats} times for the same action within the last ${this.window} tool steps.`
    } else if (attempts >= this.inputThreshold) {
      state.reason = `${event.tool} repeated the same action ${attempts} times within the last `
        + `${this.window} tool steps, even though its output changed.`
    }
    state.paused = Boolean(state.reason)
    if (!state.paused) return
    state.tool = event.tool
    return state.tool
  }

  reason(sessionID) {
    return this.sessions.get(sessionID)?.reason
  }

  warn(sessionID) {
    const state = this.sessions.get(sessionID)
    const warning = state?.warning
    if (state) state.warning = false
    return Boolean(warning)
  }
}
