# Architecture — One Runtime, Three Surfaces

How the system delivers the wedge today, where the seams and risks are, and the one
structural proposal the refocus implies. Grounded in the actual module layout
([Package.swift](../../../Package.swift), `Sources/`).

---

## 1. Layered view

```
        ┌─────────────────────────────────────────────────────────┐
Surfaces│  KWWKLauncher (SwiftUI)   kwwk CLI/TUI        Your app    │
        │  macOS palette + menubar  interactive + -p    (SDK embed) │
        └───────┬───────────────────────┬───────────────────┬──────┘
                │ shells out to          │ in-process        │ links
                │ `kwwk -p` / scripts    │                   │
        ┌───────▼────────────────────────▼───────────────────▼──────┐
 Wrapper│  KWWKLauncherCore            KWWKCli                       │
        │  catalog · filter · invoke   TUI · headless · slash cmds   │
        └───────────────────────────────┬───────────────────────────┘
                                         │
        ┌────────────────────────────────▼──────────────────────────┐
Runtime │  KWWKAgent  — turn/tool loop, built-in tools, hooks,       │
        │               background tasks, steering                  │
        │  KWWKAI     — providers, OAuth, streaming, model catalog   │
        └────────────────────────────────────────────────────────────┘
```

- **Runtime core:** [`KWWKAI`](../../../Sources/KWWKAI) (providers, OAuth, SSE streaming,
  model catalog) + [`KWWKAgent`](../../../Sources/KWWKAgent) (the agent loop in
  `AgentLoop.swift`, built-in tools, `beforeToolCall`/`afterToolCall` hooks,
  `BackgroundTaskManager`, `agent.steer`).
- **CLI wrapper:** [`KWWKCli`](../../../Sources/KWWKCli) renders the TUI and the headless
  `-p` path ([`Headless.swift`](../../../Sources/KWWKCli/Headless.swift)).
- **Launcher:** [`KWWKLauncher`](../../../Sources/KWWKLauncher) (SwiftUI views/stores) over
  [`KWWKLauncherCore`](../../../Sources/KWWKLauncherCore) (the command catalog, filtering,
  and CLI invocation).

---

## 2. The unification seam — process boundary

The GUI does **not** link the agent in-process. It **shells out to `kwwk -p`** via
[`KWWKCLIInvocation.swift`](../../../Sources/KWWKLauncherCore/KWWKCLIInvocation.swift),
using the CLI helper bundled at `Contents/MacOS/kwwk` (overridable with `KWWK_CLI_PATH`).

**This is the most important architectural fact in the PRD**, with two faces:

- ✅ **Strength:** it makes "one runtime" *literally true* — the GUI runs the same binary,
  same auth store (`~/.kwwk/oauth.json`), same model/thinking/context flags, same shared
  JSON stores under `~/.kwwk/launcher/`. There is no second agent implementation to drift.
- ⚠️ **Constraint:** it is a *process* boundary, not an in-proc API. Streaming is line/stdout-
  based; richer interaction (e.g. **B1 live steering** in [brainstorm.md](./brainstorm.md))
  needs a control channel the current shell-out seam doesn't provide. Decide deliberately
  whether B1/B2 keep the process model (IPC/socket) or introduce in-proc embedding for the
  GUI.

---

## 3. The bridging mechanism (the wedge, in code)

Bidirectional GUI↔CLI bridging is carried by three Core types:

| Concern | Module |
|---|---|
| Deep-link encode/decode (`kwwk://launcher?…`) | [`LauncherDeepLink.swift`](../../../Sources/KWWKLauncherCore/LauncherDeepLink.swift) |
| Replayable command / `--inspect-command` export | [`LauncherCommandExport.swift`](../../../Sources/KWWKLauncherCore/LauncherCommandExport.swift) |
| Per-result actions (copy command, open in terminal, save-as-*) | [`LauncherActionItem.swift`](../../../Sources/KWWKLauncherCore/LauncherActionItem.swift) |

Shared persistent state lives in `~/.kwwk/launcher/*.json` (history, prompts, snippets,
quicklinks, aliases, workflows, profiles, clipboard) so every surface reads/writes the
same artifacts.

---

## 4. The sprawl, structurally

The refocus's maintainability concern is visible in the file sizes:

- [`LauncherActionItem.swift`](../../../Sources/KWWKLauncherCore/LauncherActionItem.swift) ≈ **69 KB** — the largest file in the project.
- [`LauncherWorkflow.swift`](../../../Sources/KWWKLauncherCore/LauncherWorkflow.swift) ≈ 25 KB, [`LauncherScriptCommand.swift`](../../../Sources/KWWKLauncherCore/LauncherScriptCommand.swift) ≈ 21 KB, [`LauncherCommand.swift`](../../../Sources/KWWKLauncherCore/LauncherCommand.swift) ≈ 20 KB.

Root cause: **N artifact types × M operations.** Prompt, snippet, quicklink, alias,
script, workflow, CLI-context, AI-history, and clipboard each carry their own
list/show/render/save-as-prompt/save-as-snippet/save-as-workflow/launcher-command surface
— in the GUI action panel *and* as `kwwk <type> …` subcommands. The action-item file
absorbs the combinatorial explosion.

---

## 5. Structural proposal — a unified `SavedArtifact` model

> **Proposal, not current state** — pending the open question in the PRD about migration cost.

Collapse the repeated per-type surface behind one protocol:

```
protocol SavedArtifact {
    var id: String { get }
    var category: ArtifactCategory { get }   // prompt | snippet | quicklink | workflow | …
    func render(_ ctx: LauncherContext) -> RenderedArtifact
    func bridge() -> LauncherCommandBridge   // replay command + deep link, one impl
    func promote(to: ArtifactCategory) -> SavedArtifact?  // the save-as-* matrix, once
}
```

Payoffs: one bridge/export path (not re-implemented per type), one `kwwk artifact …` CLI
surface instead of nine near-duplicates, and `LauncherActionItem` shrinks to dispatch.
Also lets **aliases** (a SPRAWL "consolidate" call in the PRD) fold in as a thin
`SavedArtifact` rather than a parallel concept.

This is the single highest-leverage refactor for serving the HERO tier without the parity
surface dragging maintenance down.

---

## 6. Cross-platform note

The CLI/runtime is cross-platform (recent commits added Linux support + CI). The
**launcher is macOS-only by design** (SwiftUI, Accessibility, menu-bar, `kwwk://` scheme)
— consistent with the ICP and the non-goals. Keep `KWWKLauncher*` cleanly separable so the
runtime never takes a macOS-only dependency.
