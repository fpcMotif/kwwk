# Native SwiftUI Pattern For KWWKLauncher

KWWKLauncher uses a native macOS command-surface pattern: a resident SwiftUI app
with a sidebar/detail split, command search, a compact action panel, settings,
and a menu-bar extra.

## Pattern

Use this structure for launcher UI work:

- `WindowGroup` owns the primary resident palette window.
- `NavigationSplitView` owns command results in the leading column and command
  preview/output in the detail column.
- `List(...).listStyle(.sidebar)` owns grouped command rows.
- `TextField` owns primary search input; scope buttons make the active filter
  explicit.
- `ContentUnavailableView` handles empty command, action, and preview states.
- `Settings` owns durable user preferences.
- `MenuBarExtra` owns quick resident access to show launcher, settings,
  favorites, recents, terminal contexts, and quit.
- AppKit interop is reserved for window behavior, global hotkey, accessibility
  window targeting, and terminal/application handoff.

## Command Surface Rules

- Keep command rows light: one symbol, one title, one short subtitle, and one
  optional favorite marker.
- Put dense context, rendered prompts, streamed output, and secondary actions in
  the detail pane.
- Keep search as the primary visible control.
- Use scopes to narrow result families instead of adding separate navigation
  screens.
- Keep action titles short and imperative.
- Expose keyboard and menu paths for important commands.
- Add stable accessibility identifiers to search, scope, list, action, and
  result controls when editing a surface that needs e2e coverage.

## Agent Harness Rules

- Render context before asking the agent. A prompt command, quicklink, snippet,
  preset, or workflow should show what it will actually send or run.
- Preserve terminal parity. If the GUI can run it, the action catalog should
  usually be able to copy a replay command or deep link.
- Keep user data local by default. Clipboard tracking stays opt-in, and captured
  terminal or file context remains bounded.
- Prefer opening an interactive draft when the user needs review/edit control;
  prefer headless runs when the command is deliberate and repeatable.
- Treat history as material for future commands: answers can become snippets,
  prompts can become prompt commands, and terminal captures can become
  workflows.

## Apple Guidance Applied

- Apple's SwiftUI docs position SwiftUI as the declarative app structure for
  views, scenes, controls, focus, accessibility, and framework integration:
  https://developer.apple.com/documentation/swiftui
- `NavigationSplitView` is the native SwiftUI structure for sidebar/detail
  column navigation:
  https://developer.apple.com/documentation/swiftui/navigationsplitview
- Apple's sidebar guidance favors native sidebars for peer areas, familiar
  symbols, succinct labels, and adaptive hiding/revealing behavior:
  https://developer.apple.com/design/human-interface-guidelines/sidebars
- Apple's search guidance says important search should be easy to find, use one
  clear location, and clearly display the current scope:
  https://developer.apple.com/design/human-interface-guidelines/searching
- `MenuBarExtra` is appropriate for commonly used functionality even when the
  app is not active:
  https://developer.apple.com/documentation/swiftui/menubarextra

## Anti-patterns

- A giant custom card list for command rows.
- A GUI-only action that cannot be inspected or replayed when a bridge is
  practical.
- Long prompt text in the menu-bar extra.
- Template metadata shown as if it were rendered context.
- Clipboard history enabled by default.
- Blank states that look like a broken or frozen window.
