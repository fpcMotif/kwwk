# KWWK PRD — One Coding Agent, Every Surface

**Status:** Draft for review · **Date:** 2026-05-25 · **Owner:** @fpcmotif
**Supersedes:** the de-facto "spec" currently living in [README.md](../../../README.md) (a 40 KB feature catalog with no problem statement, ICP, metrics, non-goals, or prioritization).

> This PRD **refocuses** an already-large product. It does not propose building from
> scratch — most of the "Now" tier already ships. The work here is naming the **hero
> core**, tiering the long tail honestly, and drawing the lines we will *not* cross.

---

## 1. TL;DR

KWWK is **one Swift-native coding-agent runtime exposed on three surfaces** — a
Raycast-style macOS palette (`KWWKLauncher`), a terminal TUI (`kwwk`), and an
embeddable SDK (`KWWKAgent`/`KWWKAI`) — driven by **the AI subscription you already
pay for** (Claude, Codex, Gemini, Copilot, or any API key).

For the target user, the one-liner is: **Spotlight for your coding agent.** Hit a
hotkey and the same agent that runs in your terminal is one keystroke from your
clipboard, your Finder selection, and your current repo — and anything you do in the
GUI copies back out as a replayable shell command.

---

## 2. Problem

macOS power-devs run three disconnected tools:

1. A **launcher** (Raycast / Alfred / Spotlight) for OS-level actions. Its AI is
   shallow — it can summarize clipboard text, not *do* multi-step work in your repo.
2. A **terminal coding agent** (Claude Code / Codex / etc.) that is powerful but
   invisible from the GUI. Asking it about your Finder selection or current clipboard
   means copy-paste gymnastics.
3. A pile of **one-off scripts** that can't replay what you just did by hand in the GUI,
   and GUI actions that can't be scripted.

None of these share a runtime, auth, model settings, or state. You re-authenticate, re-
configure, and re-paste context across all three.

---

## 3. Target user (ICP)

**Primary:** the individual macOS developer who *already* pairs a launcher
(Raycast/Alfred) with a terminal coding agent, pays for ≥1 AI subscription, lives in the
shell, and automates their own workflow.

| Surface | Role for this user |
|---|---|
| **Launcher** | **HERO** — always a hotkey away, lowest-friction entry point. |
| **CLI/TUI** | **Power tool** — deep agent work, piping, scripting, CI. |
| **SDK** | **Extension** — the subset who embed or build custom tools. |

Explicitly *not* the primary audience (for now): enterprise/teams, non-developers,
Windows/Linux GUI users, people who want a hosted/managed agent.

---

## 4. The wedge — why KWWK wins

**One runtime, every surface, with bidirectional GUI↔CLI bridging.** Concretely:

1. **Same agent, auth, and model settings everywhere.** `kwwk -p` is the single
   execution path; the launcher streams it, the SDK wraps it.
2. **GUI → CLI:** every palette result can be copied as a replayable
   `kwwk launcher --command … --run` command or a native `kwwk://launcher?…` deep link.
3. **CLI → GUI:** terminal output pipes into bounded agent context
   (`… | kwwk launcher --ask-stdin`), becoming a searchable `cli-context:` command.

This mechanic is **structurally hard for incumbents to copy**:

| Competitor | Why they can't close the wedge |
|---|---|
| **Raycast AI** | No real terminal agent; closed, commercial; no SDK; locked to its own AI. |
| **Claude Code** | No GUI/palette; single-vendor; not embeddable. |
| **Warp** | Terminal-only; no palette, no SDK, no GUI bridging. |
| **Cursor** | An editor, not a launcher or a scriptable runtime. |

*(Competitive claims are as of the author's knowledge; verify current feature sets
before publishing externally.)*

---

## 5. Strategy: the refocus principle

Every existing feature gets one of three roles. **This is the core output of the
refocus** — it tells us where to invest and what to stop polishing.

- **HERO** — serves the wedge (the unification). *Invest aggressively.*
- **PARITY** — table-stakes that make the launcher *credible* vs Raycast, but are not
  why anyone switches. *Keep working, bound the investment, never enter a feature arms
  race here.*
- **SPRAWL** — off-mission for a coding agent; high maintenance, low strategic value.
  *Candidate to cut, defer, or de-emphasize.*

---

## 6. Scope — tiered feature inventory

Tier = maturity (**Now** ships today · **Next** = next bet · **Later** = deferred).
Role = the refocus classification above.

### HERO (the product's reason to exist)

| Feature | Tier | Notes |
|---|---|---|
| Unified `kwwk -p` runtime shared by CLI + launcher + SDK | Now | The seam is process-level (GUI shells to the binary) — see [architecture](./architecture.md). |
| BYO-subscription multi-provider OAuth (Claude/Codex/Gemini/Copilot) + API keys | Now | Cross-cutting enabler. **ToS-fragile — see risks.** |
| GUI→CLI bridges: `--command --run`, `kwwk://` deep links, `--inspect-command --json` | Now | The signature mechanic. Make it discoverable, not buried in an action panel. |
| CLI→GUI context: `--ask-stdin` / `--capture-stdin`, `cli-context:` commands | Now | Terminal output → agent context. |
| Desktop context as input: Ask About Workspace / Finder Selection / Current Context | Now | "Ask about everything I'm looking at." |
| Workflows (multi-step prompt+shell, run from GUI **or** `kwwk workflow`) | Now | Composable automation; serves the wedge. |
| Cross-surface handoff: "Open Draft in CLI" / "Open in Terminal" | Now | Today carries the *prompt*; carrying the full *transcript* is a Next bet. |

### PARITY (necessary table-stakes — bound the investment)

| Feature | Tier | Role note |
|---|---|---|
| App launching, file/folder open, fuzzy search, favorites/recents | Now | Expected of any launcher. |
| Quicklinks, snippets, clipboard history | Now | Commodity; keep simple. |
| Web search / URL commands, scope strip (`@ai`/`@cli`/…) | Now | Fine as-is. |
| AI presets (summarize/explain/commit-msg/shell-gen) | Now | Cheap wins on top of `kwwk -p`. |

### SPRAWL (off-mission — candidates to cut/defer/de-emphasize)

| Feature | Verdict | Rationale |
|---|---|---|
| Calculator + unit conversion | **De-emphasize / cut** | Pure Raycast parity; zero strategic value for a *coding* agent. |
| Window management | **Cut or spin out** | High maintenance (Accessibility perms), off-mission. |
| `aliases` as a distinct concept | **Consolidate** | Overlaps quicklinks/prompts/scripts. |
| Per-type CRUD surface (`--save-prompt`/`--save-snippet`/`--save-workflow`/… × prompt/snippet/quicklink/alias/script/context/history/clipboard) | **Unify** | This combinatorial surface is what bloats [LauncherActionItem.swift](../../../Sources/KWWKLauncherCore/LauncherActionItem.swift) to ~69 KB. Propose a single "saved artifact" abstraction — see [architecture](./architecture.md). |

> **The headline refocus finding:** the agent-unification *is* the product; the
> Raycast-parity layer is being **over-built**; and calculator/window/conversion are
> off-mission. The product is strong **because** of HERO, not because it has the most
> palette features.

---

## 7. Success metrics (hypotheses — instrument before trusting)

The README defines none. These are **leading indicators**, stated as hypotheses; exact
targets require opt-in telemetry we don't have yet (see open questions).

- **Unification proof:** % of W1 users who invoke the agent from **both** launcher and
  CLI. *(If low, the wedge isn't landing.)*
- **Wedge usage:** # of GUI→CLI bridges (`--command`/deep links) copied per active user.
- **Activation:** median time-to-first-agent-run from a fresh install.
- **Stickiness:** saved artifacts (prompts/workflows/snippets) created per active user.
- **Engagement:** weekly hotkey invocations; W1/W4 retention.

---

## 8. Non-goals

- ❌ Out-featuring Raycast on general productivity (calculators, window mgmt as headline).
- ❌ A hosted/cloud service or model hosting — local, BYO-subscription only.
- ❌ A Windows/Linux **GUI** (the CLI is cross-platform; the launcher is macOS-only by design).
- ❌ An IDE/editor — not competing with Cursor on in-editor editing.
- ❌ Team/multiplayer collaboration — at least for the current ICP.

---

## 9. Go / No-go verdict

**GO — conditionally.** The concept is genuinely differentiated and the hard part is
already built. It holds **if and only if** three conditions are met:

1. **Scope discipline holds.** Invest in HERO, freeze PARITY, prune SPRAWL. Without
   this, the product drowns in its own surface area (the central risk).
2. **The OAuth/ToS risk is contained.** Reusing vendors' first-party OAuth client IDs is
   fragile and could break or invite legal pressure overnight. The API-key path must be
   first-class; subscription-OAuth is best-effort. **Do not build monetization on it.**
3. **The wedge is made obvious.** GUI↔CLI bridging is currently buried in action panels
   and dense docs. If users never discover it, KWWK is just another launcher.

**No-go signals to watch:** bridging usage stays near zero; Raycast ships a real
terminal agent + bridge; maintenance of the parity/sprawl layer outpaces HERO work.

Full risk register in [best-practices](./best-practices.md).

---

## 10. Open questions

1. **Sustainability/monetization** — OSS-only? Paid Pro launcher? Donations?
2. **Telemetry** — opt-in analytics to validate §7, or stay blind?
3. **Blessed provider** — which provider is the default given ToS risk?
4. **macOS-only forever?** — or a Linux GUI once the core stabilizes?
5. **Artifact unification** — is collapsing prompt/snippet/quicklink/alias/workflow into
   one model worth the migration cost? (See architecture.)

---

## Design Documents

- [BDD Specifications](./bdd-specs.md) — behavior scenarios for the hero wedge flows.
- [Architecture](./architecture.md) — the one-runtime / three-surface system, grounded in the actual code, and the sprawl-containment proposal.
- [Best Practices](./best-practices.md) — PRD quality bar, scope-discipline guardrails, full risk register, and the ToS/legal note.
- [Brainstorm](./brainstorm.md) — "explore furthermore": new bets that amplify the wedge, tiered Now-adjacent → Moonshot.
