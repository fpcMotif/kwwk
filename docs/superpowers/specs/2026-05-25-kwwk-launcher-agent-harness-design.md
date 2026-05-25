# KWWKLauncher Agent Harness PRD

Date: 2026-05-25
Status: active implementation spec
Issue: https://github.com/EYHN/kwwk/issues/19

## Summary

KWWKLauncher should be a native macOS agent harness with Raycast-style command
discovery. The product is not just a command palette that happens to call AI; it
is a fast control surface for turning local context, terminal output, workspace
files, command history, and reusable workflows into agent work that can move
between GUI, terminal, and automation.

The Raycast-style palette remains the interaction pattern: one primary search
field, scoped command results, previews, primary actions, and secondary actions.
The agent-harness value is the durable system underneath: commands carry real
rendered context, actions export replayable CLI and deep-link bridges, and
history can become prompt commands, snippets, or workflows.

## Product Goal

Make KWWKLauncher feel like the native desktop companion for kwwk's terminal
agent: quick enough for launcher muscle memory, rich enough for coding-agent
handoff, and truthful enough that every GUI operation can be inspected or
replayed from the terminal.

## Users

- A developer already using `kwwk` in a terminal who wants native macOS access
  to the same agent runtime.
- A keyboard-first macOS user who expects Raycast-like discovery, fast search,
  command actions, and menu-bar access.
- A power user who wants to convert useful one-off prompts, terminal captures,
  workspace files, scripts, and snippets into repeatable agent workflows.

## Problem

Terminal-first agents are powerful but create friction when the user wants to
act on desktop context, selected files, clipboard text, or recent output. A
basic launcher can open commands quickly, but it usually loses the agent
context, replayability, and inspectability that make coding-agent work safe.

KWWKLauncher solves this by making the launcher command surface the native
front door to the same agent harness instead of a separate app with separate
state.

## Non-goals

- Do not create a second agent runtime in the launcher.
- Do not make the GUI claim work is "live" unless it can stream or inspect the
  real command result.
- Do not hide terminal replay commands behind opaque UI-only state.
- Do not replace the terminal TUI. The launcher should hand work to it when an
  editable coding session is better than a headless run.

## Design Principles

1. Native first: use SwiftUI scenes, split views, lists, settings, menu-bar
   extras, commands, focus, and accessibility hooks before custom chrome.
2. Search is the front door: the command surface must keep a single, visible
   search entry point with scopes for narrowing results.
3. Context must be rendered: prompt commands, snippets, quicklinks, presets,
   history, and workspace files should show the actual rendered prompt, URL, or
   bounded context, not only template metadata.
4. Every GUI action should have a bridge: where practical, actions should expose
   a replayable `kwwk launcher ...` command and native `kwwk://launcher` deep
   link.
5. Agent work remains inspectable: results, errors, prompts, and terminal
   context should be copyable, savable, rerunnable, and openable as terminal
   drafts.
6. Privacy is explicit: clipboard history is opt-in, captured context is local,
   and workspace/file prompts are bounded.

## UX Model

### Launcher Command Surface

The main window is a compact native palette with:

- Search field for commands, prompts, paths, shell commands, calculations,
  conversions, URLs, and natural-language agent prompts.
- Scope strip for All, AI, CLI, Apps, Scripts, Workspace, Workflows, Quicklinks,
  Snippets, and Models.
- Sidebar-style command list grouped by command family.
- Preview/detail pane that shows the selected command's rendered context,
  streamed output, or saved result.
- Featured action strip for the most useful command-specific actions.
- Full action panel for searchable secondary operations.

### Agent Harness Behavior

The launcher should let people:

- Ask KWWK about clipboard, workspace, Finder selection, terminal captures, or
  arbitrary natural-language prompts.
- Open the same prompt as an editable terminal draft.
- Apply AI profiles and runtime settings without leaving the command surface.
- Save useful outputs as snippets, prompts, aliases, scripts, or workflows.
- Replay GUI choices through shell commands or native deep links.

### Resident Behavior

The app stays resident, exposes a menu-bar extra, supports a global hotkey, and
keeps the palette hide/show cycle fast. The menu-bar extra mirrors favorites,
recents, and terminal contexts rather than becoming a separate product surface.

## Current Implementation Alignment

The current codebase already provides most of the harness foundation:

- `KWWKLauncher` SwiftUI app target and `KWWKLauncherCore` model layer.
- Raycast-style commands and actions through `LauncherCommand` and
  `LauncherActionItem`.
- Deep-link handoff through `LauncherDeepLinkRequest`.
- CLI invocation/replay through `KWWKCLIInvocation`.
- Runtime profiles, thinking, model override, and long-context preferences.
- Prompt commands, quicklinks, snippets, aliases, scripts, workflows, AI
  history, clipboard history, terminal context, workspace files, workspace
  tasks, calculator, web, system, and window commands.
- A packaged app script at `script/build_and_run.sh` that stages a real
  `dist/KWWKLauncher.app` with bundled `kwwk`.

## Design Decisions

### Primary Product Posture

Choose "agent harness with Raycast-style command discovery" over "command
palette with AI features."

Rationale: the stronger product promise is repeatable coding-agent work with
real local context. Raycast-style UI gives speed and familiarity, but the
business logic should optimize for agent context, replay, and terminal handoff.

### Native Layout

Use a SwiftUI `NavigationSplitView` for the command list and detail pane. Keep
the command list sidebar-like and visually light, and put dense context and
actions in the detail pane. This follows Apple's guidance that sidebars expose
peer areas and that split views are the native pattern for sidebar/detail
navigation.

### Search and Scopes

Keep search visible and primary. Use scope buttons and `@scope` text prefixes
to make filters explicit. This follows Apple's search guidance: one clear
search location, clear current scope, and filtering when people need to narrow
results.

### Menu-Bar Extra

Use a SwiftUI `MenuBarExtra` for access to common functionality when the app is
not active. It should stay compact and mirror the resident launcher rather than
host long prompts or dense output.

### Empty States and Accessibility

The command list, action panel, and response pane need explicit empty states so
bad queries and missing config do not look like a broken window. Core controls
need accessibility labels and stable identifiers for assistive use and future
UI automation.

## E2E Test Strategy

Credential-free e2e coverage should focus on deterministic flows that use
public interfaces:

- Palette query -> filtered command -> preview/detail export -> featured
  actions -> replayable launcher command.
- Workspace file query -> bounded file context -> preview -> file actions.
- Prompt command -> rendered prompt -> open-terminal and open-draft actions.
- CLI bridge command export -> JSON and text parity.
- Build/run script -> staged app bundle -> process verification.

Live model calls stay outside default tests. Real credentials are not required
to prove the command surface, context rendering, bridge export, or native app
packaging path.

## Acceptance Criteria

1. The launcher app builds as a native SwiftUI macOS executable.
2. The main surface uses native split-view/list/detail structure, explicit
   empty states, and stable accessibility identifiers.
3. Prompt, workspace, and command-detail e2e tests pass without network
   credentials.
4. The focused launcher-core suite passes.
5. `swift build --product KWWKLauncher` passes.
6. `./script/build_and_run.sh --verify` stages and launches the app bundle.
7. PRD, glossary, design pattern, and a GitHub issue exist for future work.

## Open Follow-up Ideas

- Add a dedicated UI automation target when the package grows beyond core
  behavior tests.
- Add screenshots or generated preview fixtures for the command surface after
  the window layout stabilizes.
- Add telemetry for command run, cancellation, deep-link handling, and action
  export failures.
- Revisit Liquid Glass-specific refinements when the deployment target can move
  beyond macOS 14.

## Apple References

- SwiftUI: https://developer.apple.com/documentation/swiftui
- NavigationSplitView: https://developer.apple.com/documentation/swiftui/navigationsplitview
- MenuBarExtra: https://developer.apple.com/documentation/swiftui/menubarextra
- Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars
- Searching: https://developer.apple.com/design/human-interface-guidelines/searching
- Search fields: https://developer.apple.com/design/human-interface-guidelines/search-fields

## Self-review

- No placeholder sections remain.
- The product posture is explicit: agent harness first, Raycast discovery
  second.
- The architecture matches the current code boundaries.
- The test strategy avoids real credentials and verifies public behavior.
- The scope is one coherent implementation stream, with larger UI automation
  and Liquid Glass refinements listed as follow-up.
