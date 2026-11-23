import { LoopGuard } from "./guard.js"

// OpenCode V2's Plugin.define is an identity function. Export the equivalent
// { id, setup } shape directly: no npm dependencies or startup installs needed.
export default {
  id: "shimmers.loop-guard",
  async setup(ctx) {
    const guard = new LoopGuard()
    const providerID = ctx.options.providerID ?? "shimmers"
    const registrations = []

    registrations.push(await ctx.session.hook("prompt", ({ sessionID }) => {
      guard.reset(sessionID)
    }))
    registrations.push(await ctx.tool.hook("execute.after", (event) => {
      if (!guard.observe(event)) return
      // Put a visible explanation on the saved tool result. The synthetic
      // notice below remains pending until the user explicitly resumes the run.
      if (event.status === "error") {
        // Keep the host's Tool.Error type but use a curated message: the host
        // otherwise displays the nested cause instead and hides this notice.
        event.error = new event.error.constructor({
          message: `${event.error.message}\n\nTool loop guard: ${guard.reason(event.sessionID)} `
            + "The run will pause. Send a new instruction to continue or switch models.",
          metadata: event.error.metadata,
        })
        return
      }
      const content = event.result.content ?? JSON.stringify(event.result.output, null, 2)
      const notice = `Tool loop guard: ${guard.reason(event.sessionID)} `
        + "The run will pause before another model request. Send a new "
        + "instruction to continue or switch models."
      event.result = {
        ...event.result,
        content: typeof content === "string"
          ? `${content}\n\n[${notice}]`
          : [...content, { type: "text", text: notice }],
      }
    }))
    registrations.push(await ctx.session.hook("context", async (event) => {
      if (event.model.providerID !== providerID) {
        guard.reset(event.sessionID)
        return
      }
      const tool = guard.begin(event.sessionID)
      if (!tool) {
        if (guard.warn(event.sessionID)) {
          event.system.push({
            type: "text",
            text: "Loop guard warning: you have repeated an action. Inspect its existing result. "
              + "Do not repeat it unless there is new evidence or the user explicitly requests it. "
              + "Choose a materially different approach, explain what blocks progress, or ask the user.",
          })
        }
        return
      }
      const text = `Tool loop guard paused this run: ${guard.reason(event.sessionID)} No further model `
        + `request was sent. Send a new instruction to continue, choose a different `
        + `approach, or switch models. Do not repeat the same unchanged tool call.`

      // This boundary runs after tool results are persisted. The notice does not
      // wake the session, and interruption must not automatically resume it.
      await ctx.session.synthetic({
        sessionID: event.sessionID,
        description: "Tool loop detected — run paused",
        text,
        resume: false,
      })
      await ctx.session.interrupt({ sessionID: event.sessionID, resume: false })
      // A final dispatch veto if interruption has not yet unwound this callback.
      throw new Error(text)
    }))

    return async () => {
      guard.sessions.clear()
      await Promise.all(registrations.map((registration) => registration.dispose()))
    }
  },
}
