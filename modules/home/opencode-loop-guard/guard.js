import { createHash } from "node:crypto"

function canonical(value) {
  return JSON.stringify(value, (_, item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) return item
    return Object.fromEntries(Object.keys(item).sort().map((key) => [key, item[key]]))
  })
}

// Retain only hashes, counts and tool names, never arguments or tool output.
export class LoopGuard {
  constructor({ threshold = 3, capacity = 1000 } = {}) {
    this.threshold = threshold
    this.capacity = capacity
    this.sessions = new Map()
  }

  reset(sessionID) {
    this.sessions.delete(sessionID)
  }

  begin(sessionID) {
    const state = this.sessions.get(sessionID) ?? { count: 0 }
    // Keep the most recently active sessions; bound memory even without idle events.
    this.sessions.delete(sessionID)
    this.sessions.set(sessionID, state)
    if (this.sessions.size > this.capacity) this.reset(this.sessions.keys().next().value)
    return state.paused ? state.tool : undefined
  }

  observe(event) {
    const state = this.sessions.get(event.sessionID)
    if (!state || state.paused) return
    if (event.status !== "completed") {
      state.count = 0
      state.hash = undefined
      return
    }
    if (event.result.content === undefined && event.result.output === undefined) return
    let hash
    try {
      hash = createHash("sha256").update(canonical({
        tool: event.tool,
        input: event.input,
        content: event.result.content,
        output: event.result.output,
      })).digest("hex")
    } catch {
      // Non-JSON plugin results must not break a user's run or count as a loop.
      state.count = 0
      state.hash = undefined
      return
    }
    if (hash === state.hash) {
      // Repeated callbacks or parallel/nested calls in ONE model step are not a
      // repeated agent loop. Count at most once per assistant message.
      if (state.messageID === event.messageID) return
      state.count += 1
    } else {
      state.count = 1
    }
    state.hash = hash
    state.messageID = event.messageID
    state.tool = event.tool
    state.paused = state.count >= this.threshold
    return state.paused ? state.tool : undefined
  }
}
