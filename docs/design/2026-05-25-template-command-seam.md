# Deepening Plan — the Command trigger/template seam

Date: 2026-05-25
Status: ready to implement (design settled, no code written yet)
Source: `/improve-codebase-architecture` review — candidate #1 ("name the
Command seam the four template commands already imply")

## Why

Four launcher command types each carry a **byte-identical** copy of the
trigger-stripping logic, and two of them additionally carry an identical
placeholder-substitution engine. They are **shallow**: their interface is
nearly as complex as their implementation, and the shared behaviour has no
single home.

Verified duplication:

- `argument(from:)` — identical in all four:
  - `Sources/KWWKLauncherCore/LauncherPromptCommand.swift:49`
  - `Sources/KWWKLauncherCore/LauncherSnippet.swift:50`
  - `Sources/KWWKLauncherCore/LauncherQuicklink.swift:37`
  - `Sources/KWWKLauncherCore/LauncherWorkflow.swift:195`
- The 14-placeholder substitution body — identical except the template field
  name (`promptTemplate` vs `textTemplate`):
  - `LauncherPromptCommand.renderedPrompt` (`:77`)
  - `LauncherSnippet.renderedText` (`:78`)

`LauncherQuicklink.renderedURLString` (`:65`) is a *different* algorithm (a
subset of placeholders, percent-encoded) and shares only the trigger logic.
`LauncherWorkflow` has no single template — it is a sequence of
`LauncherWorkflowStep` — and likewise shares only the trigger logic.

**Deletion test:** delete the four copies into one shared default and nothing a
caller sees changes; the complexity concentrates in one place instead of four.
The duplication is not earning its keep.

## Design — two nested seams

```
TriggeredCommand   { title, keywords }  → argument(from:)     ← Prompt · Snippet · Quicklink · Workflow   (kills 4 copies)
  └ TemplateCommand { + template }       → render(query,ctx)   ← Prompt · Snippet                          (kills 2 copies)
```

Both seams have ≥2 adapters, so both are real (not hypothetical). The interface
shrinks to **two properties** that hand back the entire trigger algorithm, and a
**one-property** refinement that hands back the placeholder engine — high
leverage, and the behaviour now lives in one place (locality).

- `Quicklink` and `Workflow` join **only** the outer `TriggeredCommand` seam.
- `Prompt` and `Snippet` join both.

Domain language: this introduces **Trigger** and **Argument** as concepts —
both now defined in `CONTEXT.md` (added during the design session).

## Interface — new file `Sources/KWWKLauncherCore/TriggeredCommand.swift`

```swift
import Foundation

/// A command whose search query carries a Trigger (its title or a keyword)
/// that is stripped to yield the Argument — the user's real input.
public protocol TriggeredCommand: Sendable {
    var title: String { get }
    var keywords: [String] { get }
}

public extension TriggeredCommand {
    func argument(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let triggers = ([title] + keywords)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for trigger in triggers {
            if trimmed.caseInsensitiveCompare(trigger) == .orderedSame {
                return ""
            }

            guard trimmed.count > trigger.count else { continue }
            let triggerEnd = trimmed.index(trimmed.startIndex, offsetBy: trigger.count)
            guard trimmed[..<triggerEnd].caseInsensitiveCompare(trigger) == .orderedSame,
                  trimmed[triggerEnd].isWhitespace
            else {
                continue
            }

            return String(trimmed[triggerEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }
}

/// A `TriggeredCommand` rendered from a single template field by substituting
/// launcher context placeholders.
public protocol TemplateCommand: TriggeredCommand {
    var template: String { get }
}

public extension TemplateCommand {
    func render(
        query: String,
        clipboard: String = "",
        context: LauncherContextSnapshot = LauncherContextSnapshot()
    ) -> String {
        let argument = argument(from: query)
        return template
            .replacingOccurrences(of: "{query}", with: argument)
            .replacingOccurrences(of: "{Query}", with: argument)
            .replacingOccurrences(of: "{argument}", with: argument)
            .replacingOccurrences(of: "{Argument}", with: argument)
            .replacingOccurrences(of: "{clipboard}", with: clipboard)
            .replacingOccurrences(of: "{Clipboard}", with: clipboard)
            .replacingOccurrences(of: "{workspace}", with: context.workingDirectory ?? "")
            .replacingOccurrences(of: "{Workspace}", with: context.workingDirectory ?? "")
            .replacingOccurrences(of: "{cwd}", with: context.workingDirectory ?? "")
            .replacingOccurrences(of: "{Cwd}", with: context.workingDirectory ?? "")
            .replacingOccurrences(of: "{finderSelection}", with: context.finderSelectionPaths.joined(separator: "\n"))
            .replacingOccurrences(of: "{FinderSelection}", with: context.finderSelectionPaths.joined(separator: "\n"))
            .replacingOccurrences(of: "{frontmostApp}", with: context.frontmostApplicationName ?? "")
            .replacingOccurrences(of: "{FrontmostApp}", with: context.frontmostApplicationName ?? "")
    }
}
```

> `Sendable` on the protocols is free (all conformers are already `Sendable`
> value types) and keeps existentials usable from the `@MainActor` view model
> under Swift 6 strict concurrency.

## File-by-file changes

### `LauncherPromptCommand.swift`
- Add `extension LauncherPromptCommand: TemplateCommand { public var template: String { promptTemplate } }`.
- **Delete** the stored `argument(from:)` (`:49`–`:75`).
- Replace the body of `renderedPrompt(query:clipboard:context:)` with a forwarder:
  `render(query: query, clipboard: clipboard, context: context)`. Keep the
  public name so callers and `previewText` are untouched.
- Leave stored `promptTemplate` and all `CodingKeys` as-is (on-disk shape unchanged).

### `LauncherSnippet.swift`
- Add `extension LauncherSnippet: TemplateCommand { public var template: String { textTemplate } }`.
- **Delete** the stored `argument(from:)` (`:50`–`:76`).
- Replace `renderedText(query:clipboard:context:)` body with a forwarder to `render(...)`.
- Leave `textTemplate` and `CodingKeys` as-is.

### `LauncherQuicklink.swift`
- Add `extension LauncherQuicklink: TriggeredCommand {}` (empty — `title`/`keywords` already stored).
- **Delete** the stored `argument(from:)` (`:37`–`:63`).
- `renderedURLString`, `url`, `previewText`, `usesArgument`, `percentEncode` unchanged
  (they call `argument(from:)`, now inherited from the protocol extension).

### `LauncherWorkflow.swift`
- Add `extension LauncherWorkflow: TriggeredCommand {}`.
- **Delete** the stored `argument(from:)` (`:195`…).
- Everything else (step model, `cliCommand`, `terminalCommand`) unchanged.

**Net:** ~130 lines of duplication removed; ~50 lines of protocol added.

## Execution loop — the interface is the test surface

Run `swift test --filter KWWKLauncherCoreTests` at each step.

1. **Characterise (green on today's code).** Add `TriggeredCommandTests` and
   `TemplateCommandTests` against the *current* concrete types so the seam's
   behaviour is pinned before any refactor.
2. **Deepen (same tests stay green).** Add `TriggeredCommand.swift`; conform the
   four types; delete the six duplicated bodies; add the `template` bridges and
   the two render forwarders. Suite must stay green — behaviour is identical.
3. **Prune (green, behaviour still covered).** Collapse the four per-type
   `argument(from:)` test cases and the Prompt/Snippet placeholder-substitution
   assertions into the two seam test files. Delete the superseded shallow-module
   tests.

Finish with a full `swift build && swift test`.

### Tests to add
- `Tests/KWWKLauncherCoreTests/TriggeredCommandTests.swift` — tiny fake conformer;
  cover: empty query, exact-trigger match → `""`, trigger + whitespace → remainder,
  longest-trigger-first, keyword triggers, case-insensitivity, no-trigger passthrough.
- `Tests/KWWKLauncherCoreTests/TemplateCommandTests.swift` — fake conformer; assert
  all 14 placeholder substitutions and that `{query}`/`{argument}` receive the stripped argument.

### Tests to keep (type-specific, not covered by the seam)
- Quicklink percent-encoding and `usesArgument` (`LauncherQuicklinkTests`).
- Workflow step decoding and rendering (`LauncherWorkflowTests`).
- `previewText`, Codable/legacy-key decoding, and `*Index` tests for every type.

## Behaviour-preservation guarantees
- On-disk JSON unchanged: `template` is a computed bridge; no `CodingKeys` touched.
- Public method names kept (`renderedPrompt` / `renderedText` / `renderedURLString`).
- `argument(from:)` semantics identical (verbatim move into the extension).

## Out of scope (do not touch in this change)
- Quicklink's URL render algorithm and Workflow's multi-step rendering.
- `LauncherActionCatalog` and the launcher view model.
- The other eight candidates from the architecture review.

Surgical-changes rule: every edit in this change traces to this candidate. No
drive-by refactors of adjacent code.
