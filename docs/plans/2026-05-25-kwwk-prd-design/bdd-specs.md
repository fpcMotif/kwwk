# BDD Specifications — Hero Wedge Flows

These scenarios give the PRD's hero core *testable* acceptance criteria. They cover the
**wedge** (one runtime, bidirectional bridging) — not the parity surface, which has its
own existing tests under [`Tests/KWWKLauncherCoreTests`](../../../Tests/KWWKLauncherCoreTests).

Scenarios tagged `@shipped` describe behavior the README already documents; `@proposed`
describe Next bets from [brainstorm.md](./brainstorm.md) and are specs to *build toward*.

---

## Feature: GUI → CLI bridging

```gherkin
@shipped
Scenario: Copy a palette result as a replayable CLI command
  Given the launcher shows a result with command id "open-cli"
  When I open the action panel and choose "Copy Launcher Command"
  Then the clipboard contains a command of the form
    "kwwk launcher --command open-cli --run"
  And running that command in a terminal reproduces the GUI action

@shipped
Scenario: Export a result as a native deep link
  Given a selected result with an associated query
  When I choose "Copy Launcher URL"
  Then the clipboard contains a "kwwk://launcher?..." URL
  And opening that URL re-invokes the same command in the resident app

@shipped
Scenario: Inspect a command for external tooling
  When I run "kwwk launcher --inspect-command open-cli --json"
  Then stdout is valid JSON containing the preview text, primary action,
    replayable launcher command, native launcher URL, and featured actions
```

## Feature: CLI → GUI context

```gherkin
@shipped
Scenario: Pipe terminal output into bounded agent context
  Given a failing test run
  When I run "swift test 2>&1 | kwwk launcher --ask-stdin --stdin-name test-output 'explain'"
  Then the captured output is saved under "~/.kwwk/launcher/context/"
  And it becomes a searchable "cli-context:" command under the CLI scope
  And "latest-cli-context" resolves to this newest capture without a generated id

@shipped
Scenario: Seed context without opening the launcher
  When I run "git diff | kwwk launcher --capture-stdin --stdin-name diff --json"
  Then stdout JSON includes the saved context id, file path, and a replayable
    "kwwk launcher --command cli-context:... --run" bridge
  And the launcher is not brought to the foreground
```

## Feature: One runtime — settings parity across surfaces

```gherkin
@shipped
Scenario Outline: Model, thinking, and 1M-context settings apply identically
  Given the launcher default model is "<model>" with thinking "<thinking>"
  When I run an AI prompt from the palette
  And I run the same prompt via "kwwk -p" with the matching profile
  Then both invocations use "<model>", thinking "<thinking>", and the same
    1M-context setting, because both route through the shared "kwwk -p" path

  Examples:
    | model        | thinking |
    | gpt-5.4      | high     |
    | claude-...   | medium   |

@shipped
Scenario: A saved AI profile is honored by both surfaces
  Given a profile "codex-deep" in "~/.kwwk/launcher/profiles.json"
  When the launcher applies "Use Codex Deep" via the @models scope
  And a script runs "kwwk --profile codex-deep -p 'review this'"
  Then both apply the same model, thinking level, and 1M-context flag
```

## Feature: Desktop context as agent input

```gherkin
@shipped
Scenario: Ask about the active checkout
  Given the launcher was opened from a CLI deep link carrying a working directory
  When I run "Ask About Workspace"
  Then the prompt includes bounded workspace context
  And the run executes through the bundled "kwwk -p" helper in that checkout

@shipped
Scenario: Bounded file context is size-limited
  Given a Finder selection containing one small UTF-8 file and one large binary
  When I run "Ask About Finder Selection"
  Then the small file contributes a bounded content excerpt
  And the large/binary file is represented by an omission note, not pasted inline
```

## Feature: Workflows run from either surface

```gherkin
@shipped
Scenario: The same workflow runs from GUI and terminal
  Given a workflow "review-and-test" in "~/.kwwk/launcher/workflows.json"
  When I run it from the palette via @workflows
  And separately run "kwwk workflow review-and-test 'staged changes'"
  Then both execute the same ordered steps with the same model/thinking/context
  And a prompt step's stdout is available to the next shell step via {previousOutput}
```

---

## Proposed (specs to build toward — see brainstorm.md)

```gherkin
@proposed @B1
Scenario: Steer a running agent from the palette
  Given an agent run started from the launcher is still in flight
  When I type a follow-up request into the palette and submit it
  Then the message is injected at the next turn boundary via agent.steer(...)
  And the current turn is not aborted

@proposed @B2
Scenario: Continue a palette session in the terminal with full transcript
  Given an AI exchange exists in launcher history
  When I choose "Open Draft in CLI"
  Then the interactive CLI opens preloaded with the full conversation transcript
    (not only the last prompt)
  And continuing in the terminal appends to the same session
```

---

## Coverage notes

- **Happy paths** covered for all five shipped hero flows.
- **Edge cases** covered: large/binary file omission, `latest-*` id resolution,
  no-foreground capture.
- **Gaps to add during implementation:** auth-expiry mid-run; provider/model unavailable
  at run time; deep link pointing at a stale/removed command id; concurrent runs sharing
  one history file.
