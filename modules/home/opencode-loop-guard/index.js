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
      // Put a visible explanation on the third saved tool result. The synthetic
      // notice below remains pending until the user explicitly resumes the run.
      const content = event.result.content ?? JSON.stringify(event.result.output, null, 2)
      const notice = "Tool loop guard: three identical tool calls returned the same "
        + "result. The run will pause before another model request. Send a new "
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
      if (!tool) return
      const text = `Tool loop guard paused this run: ${tool} returned the same result `
        + `for identical arguments in three consecutive tool steps. No further model `
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
