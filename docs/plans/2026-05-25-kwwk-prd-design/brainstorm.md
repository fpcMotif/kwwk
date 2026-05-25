# Brainstorm — Amplifying the Wedge

"Explore furthermore." These are **new bets beyond current scope**, every one chosen to
deepen *one runtime, every surface* — not to add another parity feature. Tiered by how
far out they are. Each names the wedge it serves.

> Filter for this list: **does it make the unification more valuable, or is it just
> another launcher feature?** If the latter, it belongs in PARITY, not here.

---

## Next (highest leverage, builds on what exists)

### B1. Palette as live agent-steering surface ⭐
The SDK already exposes `agent.steer(...)` (inject a message at the next turn boundary
without aborting). Today the launcher fires `kwwk -p` and watches output. **Bet:** while
a run is in flight, the palette shows live status and lets you type a follow-up that is
*steered into the running agent*. This fuses the GUI directly into the agent loop — no
competitor's launcher touches a running agent's control plane.
*Serves: one runtime (GUI becomes a control surface, not just a trigger).*

### B2. Full-transcript handoff (not just the prompt) ⭐
"Open Draft in CLI" carries the prompt. **Bet:** carry the entire *conversation state* so
you continue the same session in the terminal — palette-started exploration becomes a
deep terminal session seamlessly, and vice-versa.
*Serves: cross-surface continuity — the literal definition of the wedge.*

### B3. Context router — one hotkey, best context
A single command that assembles the *most relevant* context automatically (workspace +
Finder selection + frontmost app + clipboard + last terminal capture), ranks it, and asks
the agent. "Ask about everything I'm looking at" without choosing a scope.
*Serves: desktop-context-as-input, made zero-friction.*

### B4. Background agent jobs surfaced in the menu bar
`BackgroundTaskManager` + `BgNotificationSummary` already exist in the agent. **Bet:**
kick off a long agent job from the palette, get a menu-bar/notification summary when it
finishes, review in CLI. "Fire from GUI, notified async, inspect in terminal."
*Serves: one runtime across async time, not just one invocation.*

---

## Later (bigger, ecosystem-shaped)

### B5. MCP support
Let the agent consume MCP servers, and surface MCP tools as palette commands. This is the
clearest "agent harness like Claude Code" expansion and a large ecosystem play — KWWK
becomes the macOS *host* for the MCP ecosystem, on your own subscription.
*Serves: the harness story; extends "every surface" to "every tool."*

### B6. User-facing safety hooks
The SDK has `beforeToolCall` / `afterToolCall` / `userPromptSubmit` hooks. **Bet:** expose
a user policy file editable from Settings — "never run `rm -rf`", "redact secrets",
"require confirmation for writes outside the repo." A governance angle terminal-agent
users actively want.
*Serves: trust — a precondition for letting the agent act across surfaces.*

### B7. Shareable workflow/recipe bundles
Export a workflow + its prompts/snippets as one file or a `kwwk://install?…` link.
Agent-native quicklinks: parameterized agent *tasks*, not just URLs, shareable with a
teammate or your future self.
*Serves: scriptability/composability; seeds a community library.*

### B8. Auto-promote a successful run into a workflow
`history --save-workflow` exists but only saves the prompt. **Bet:** detect a multi-step
ad-hoc agent session that worked and offer to parameterize it into a reusable workflow.
*Serves: the automation flywheel — every good run becomes a reusable command.*

---

## Moonshots (validate desirability before any build)

### B9. Vision/screenshot context
Capture the frontmost window and attach it as image context to the prompt. "Why is this
UI broken?" pointed at what's on screen.
*Serves: desktop-context-as-input, beyond text.*

### B10. Local model support (Ollama / MLX)
A fully-local provider for privacy-maximalist devs. Fits the BYO/private ethos and
sidesteps the OAuth/ToS risk entirely for that segment.
*Serves: the BYO/freedom angle; a hedge against the ToS risk in the PRD.*

### B11. Voice into the palette
Dictate a request to the agent from the hotkey. Lowest-friction possible entry.
*Serves: launcher-as-hero, taken to its limit.*

---

## Explicitly parked (tempting, but off-mission)

- More calculator/conversion/window-management depth → **PARITY/SPRAWL**, not here.
- A plugin store competing with Raycast's → out-resourced; lean on the SDK + MCP instead.
- Mobile app → contradicts the macOS-power-dev ICP.

---

## Prioritization signal

If forced to pick **two** to start: **B1 (live steering)** and **B2 (transcript
handoff)** — both turn the *current* process-boundary unification into something
qualitatively new, require no new providers or external dependencies, and are the hardest
for any competitor to follow. B5 (MCP) is the biggest *strategic* bet but is a larger lift
and partly bounded by the upstream ecosystem.
