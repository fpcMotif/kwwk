# kwwk

A Swift-native coding agent with two faces:

- **`kwwk`** — an interactive coding CLI (TUI) that drives your existing
  Anthropic, ChatGPT (Codex), Gemini, or GitHub Copilot subscription.
- **`KWWKAgent` / `KWWKAI`** — the agent runtime underneath, exposed as
  SwiftPM libraries so you can embed it in your own app, build custom
  tools, or swap the LLM provider.

## Requirements

- macOS 14+
- Swift 6.1 toolchain (Xcode 16.3+ or the matching `swift` toolchain)

---

## 1. The coding CLI

### Install

From Homebrew (recommended):

```sh
brew install EYHN/tap/kwwk
```

Or build from source:

```sh
swift build -c release
cp .build/release/kwwk /usr/local/bin/
```

### Run

```
kwwk              launch the interactive coding TUI
kwwk --draft "fix the failing tests"
                  launch the TUI with a prefilled prompt
kwwk login        log in to an OAuth provider
kwwk workflow --list
                  list saved launcher workflows
kwwk workflow --list --json
                  list saved workflows for scripts and pickers
kwwk workflow review-and-test "staged changes"
                  run a saved launcher workflow in the terminal
kwwk history --json
                  list shared launcher / CLI AI history
kwwk context --json
                  list saved terminal contexts
kwwk profile --json
                  list shared launcher AI runtime profiles
kwwk launcher --ask-stdin "review this"
                  pipe terminal output into resident launcher AI context
kwwk --profile codex-deep -p "review this"
                  run the CLI with a saved launcher AI profile
kwwk --help       show this message
```

Credentials come from the OAuth store at `~/.kwwk/oauth.json` — run
`kwwk login` once to register a provider (OAuth subscription like
ChatGPT Codex, Gemini, Copilot, or Claude Code; or an API key for
Anthropic, OpenAI, Google, or any OpenAI-compatible endpoint).

Inside the TUI, `/help` lists slash commands (`/model`, `/thinking`,
`/clear`, …). The agent ships with Bash, Read, Write, Edit, Grep, Find,
LS, tmux, and background-task tools out of the box.

---

## 2. The macOS launcher app

`KWWKLauncher` is a SwiftUI command launcher for the same agent runtime and
CLI. It opens as a compact Raycast-style palette, filters built-in commands and
installed macOS apps, discovers executable script commands from
`~/.kwwk/launcher/commands`, loads quicklinks, snippets, AI prompt commands, and
clipboard and AI history from `~/.kwwk/launcher/*.json`, shows favorites and
recent commands first, groups visible results by source category, streams
`kwwk -p` or script output into the app, and can open the interactive CLI or
login flow in a terminal. AI prompt results are kept
as searchable history items that can be previewed, rerun, copied, or saved back
into `~/.kwwk/launcher/prompts.json` as reusable prompt commands through the
action panel. Clipboard history items can also be promoted into durable
snippets without opening the JSON file by hand.
The search field includes a compact scope strip for All, AI, CLI, Apps,
Scripts, Workspace, Workflows, Quicklinks, Snippets, and Models; selecting a
scope preserves the current search text and swaps only the leading `@scope`
prefix.
Natural-language queries surface a dynamic `Ask KWWK` result, while explicit
preset triggers like `shell command ...` keep their specialized action. Press
`cmd` + `K` inside the launcher to open a searchable action panel for the
selected result. The preview pane also surfaces the selected result's most
useful secondary actions inline, while the full action panel can copy a reusable
`kwwk launcher ...` command or native `kwwk://launcher?...` deep link for a
selected result, or open the selected result's context as an editable
interactive CLI draft, so GUI workflows can become shell automation, Shortcuts
handoff, or terminal-agent work without guessing command IDs. When a GUI action
saves a prompt command, snippet, quicklink, alias, script, or workflow, the
response pane prints the saved path, command ID, native launcher URL, and
replayable launcher command so the saved artifact can immediately move back into
a terminal script, Shortcuts handoff, or the resident app. That AI context uses
the rendered prompt, snippet text, quicklink URL, or preset input for
template-backed results, not only the saved template metadata.
Prefix a query with `$` or `!` to create a direct shell command result, for
example `$ git status --short`. It opens in Terminal from the active launcher
workspace and can be copied from the action panel.
Type a math expression like `=2 + 3 * 4` or `sqrt(144)` to create a calculator
result. The primary action copies the answer, while the action panel can copy
the expression or a reusable launcher bridge command.
Type unit conversions like `10 km to mi`, `32 f to c`, `1 MiB to KB`, or
`5 lb to kg` to get a copyable conversion result in the same palette.
Type `web swift package manager`, `search web macOS automation`, or a URL such
as `https://example.com` to create browser commands without configuring a
quicklink first.
Built-in macOS system commands can lock the screen, sleep the display, start the
screen saver, open System Settings, or ask running apps to quit from the same
searchable command flow. Window commands can move the previously active app's
window to the left half, right half, centered layout, or visible-screen maximum;
macOS may require Accessibility permission before those commands can resize
another app.
Prefix a query with a category scope to narrow the palette without reaching for
the mouse: `@ai summarize this module`, `@cli $ git status --short`, `@apps
xcode`, `@scripts deploy`, `@quicklinks gh swift`, `@snippets thanks`,
`@clipboard release notes`, `@calculator 2 + 2`, `@calculator 10 km to mi`,
`@quicklinks web swift`, `@aliases term`, `@models gpt`, `@system lock`,
`@window left`, `@workflows release`, or `@workspace Package.swift`.
You can also type `search apps`, `scope workspace`, or `@scopes apps` to reveal
scope switcher commands that prefill those prefixes for you.
The app menu also exposes native shortcuts for running the selected command,
moving the selection with `ctrl` + `N` / `ctrl` + `P`, opening actions,
toggling favorites, capturing or clearing clipboard history, stopping a run,
refreshing context, and reloading script commands, terminal contexts, workflows,
quicklinks, snippets, or AI prompt commands. Current streamed results can be copied
directly from the response pane or with `cmd` + `shift` + `C`;
`cmd` + `shift` + `S` saves the visible result as a reusable snippet; type a
follow-up request and press `cmd` + `shift` + `return` to ask KWWK against the
current result; use `cmd` + `shift` + `O` to open the current result as an
editable interactive CLI draft.
The menu-bar extra mirrors the resident workflow with Favorites, Recent, and
Terminal Contexts submenus, so captured terminal output and frequently used
commands can run without typing the search again.

```sh
./script/build_and_run.sh
./script/build_and_run.sh --install  # copy to ~/Applications/KWWKLauncher.app
```

`--install` also registers the `kwwk://launcher` URL scheme for the installed
bundle. Set `KWWK_LAUNCHER_INSTALL_DIR` when you want a different destination.

Built-in AI presets turn common launcher tasks into one-keystroke commands:
summarize or explain clipboard text, debug a pasted failure, draft a conventional
commit message from a copied diff, or generate a safe zsh command from the query
text. These presets use the same streamed `kwwk -p` execution path as free-form
prompts, so they share model, thinking, and context settings. Long-running AI
and script commands can be stopped from the launcher with the Stop button or
`cmd` + `.`.
AI commands also expose `Open in Terminal` from the action panel, which replays
the rendered prompt through `kwwk -p -` with the current model, thinking level,
1M-context setting, and active workspace. Use `Open Draft in CLI` when you want
the same prompt prefilled in the interactive terminal agent instead of running
it headlessly.

Model commands are searchable under `@models` and set the launcher's default
`--model` override without opening Settings. Use entries such as `Use GPT-5.4`,
`Use Claude Sonnet 4.5`, or `Use Gemini 2.5 Pro` to pin a provider-specific
model for future `kwwk -p` runs from the launcher; `Use Provider Default Model`
clears that override. The action panel can copy the raw model ID, a reusable
`--model ...` flag, or a complete headless command.
The same `@models` surface includes AI profiles, which apply model, thinking,
and 1M-context settings together. Built-in profiles cover fast provider-default
runs, Codex deep runs, and Claude long-context runs. `Save Current AI Profile`
writes the current launcher model, thinking level, and 1M-context setting into
`~/.kwwk/launcher/profiles.json`, where custom profiles can be renamed or
refined. The terminal can inspect and reuse the same profiles:

```sh
kwwk profile                         # table of default and custom profiles
kwwk profile --json                  # automation-friendly profile metadata
kwwk profile --show codex-deep       # inspect one profile
kwwk profile --flags codex-deep      # print --thinking/--model/context flags
kwwk --profile codex-deep -p "review this change"
kwwk --profile review workflow ship "staged diff"
```

Explicit `--thinking`, `--model`, and `--context-1m` flags can still be supplied
with `--profile`; they override or extend the profile for that run.

```json
[
  {
    "id": "review",
    "title": "Use Review Profile",
    "subtitle": "GPT-5.4 with high thinking",
    "keywords": ["review", "code"],
    "model": "gpt-5.4",
    "thinking": "high",
    "context1m": false
  }
]
```
AI runtime settings are commandable too: `@models thinking high` changes the
default reasoning effort, while `@models 1m context` can enable or disable the
Anthropic 1M-context flag. These commands update the same defaults used by
streamed launcher AI runs, and their action panels copy matching CLI flags or
replayable `kwwk launcher --command ... --run` bridges.

The launcher also creates AI commands from desktop context. When opened from the
CLI it exposes the active checkout as `Ask About Workspace`; when Finder has
selected files it exposes `Ask About Finder Selection`; and `Ask About Current
Context` combines available workspace, Finder, and frontmost-app context into a
single prompt. These context prompts still run through the bundled `kwwk -p`
path, so the GUI and CLI stay one runtime.

When a CLI deep link includes a working directory, the launcher indexes regular
workspace files as command results too. Typing `Package.swift` can open that
file, reveal it in Finder, copy its path, or send its path and relative location
to KWWK through the action panel. For small UTF-8 files, the ask action includes
a bounded content excerpt; for folders it includes a shallow listing; and large
or binary files are represented by an omission note instead of being pasted into
the prompt. File actions also include a relative-path copy for shell commands
and issue comments.
Explicit paths also become openable commands without waiting for indexing: type
`./README.md`, `../notes`, `~/Downloads/file.txt`, or `/tmp/log.txt` to open the
matching file or folder, reveal it in Finder, copy its absolute path, or export a
reusable `kwwk launcher --command ... --run -- <path>` bridge.
The active checkout also contributes project task commands. If the launcher is
opened from a directory with `package.json`, it exposes scripts as `bun run`,
`pnpm run`, or `yarn run` commands without ever falling back to `npm`; SwiftPM
projects expose `swift build` and `swift test`; and Cargo projects expose
`cargo build`, `cargo test`, and `cargo run`. These tasks run in the same active
workspace as the CLI bridge and can be copied from the action panel.

The local app bundle includes the `kwwk` CLI helper under
`Contents/MacOS/kwwk`, so GUI launches do not depend on the shell PATH.
Set `KWWK_CLI_PATH` to override that helper during development. The Settings
window can also pin a CLI path, default model, thinking level, 1M context mode,
AI history limit, launch-at-login behavior, and the resident global hotkey.

Default launcher hotkey: `ctrl` + `option` + `shift` + `space`; pressing it
again hides the resident palette. Settings can change it or disable the global
hotkey when it conflicts with another launcher.
The app also installs a small menu-bar extra for showing the launcher, opening
settings, and quitting while it stays resident.

The CLI can also open the launcher through the app's `kwwk://launcher` deep
link:

```sh
kwwk launcher "Open KWWK CLI"             # open with a search query
kwwk launcher --toggle                    # show or hide the resident palette
kwwk launcher --hide                      # hide without quitting
kwwk launcher --ask "summarize this repo" # open and run an AI prompt
git diff | kwwk launcher --ask-stdin "review this change"
                                          # save stdin as bounded AI context
swift test 2>&1 | kwwk launcher --ask-stdin --stdin-name test-output "explain"
                                          # label the captured context file
swift test 2>&1 | kwwk launcher --capture-stdin --stdin-name test-output --json
                                          # save terminal context for later
kwwk context                             # list saved terminal contexts
kwwk context --show latest-cli-context   # print the newest captured context
kwwk context --ask-command latest-cli-context
                                          # print a launcher command to ask about it
kwwk context --save-prompt latest-cli-context
                                          # save newest capture as a prompt command
kwwk context --save-snippet latest-cli-context
                                          # save newest capture as a reusable snippet
kwwk prompt                              # list saved launcher prompt commands
kwwk prompt --render review-code "staged diff"
                                          # render a prompt command in the terminal
kwwk prompt --launcher-command review-code
                                          # print a replayable launcher bridge
kwwk quicklink --render github-search "swift package manager"
                                          # render a saved quicklink URL locally
kwwk quicklink --launcher-command github-search
                                          # print a quicklink launcher bridge
kwwk alias --launcher-command term       # print an alias launcher bridge
kwwk alias --target term                 # print an alias target command id
kwwk script --launcher-command summarize-repo "staged diff"
                                          # print a script launcher bridge
kwwk script --path summarize-repo        # print a script executable path
kwwk snippet --render thanks "Alice"
                                          # render a saved snippet locally
kwwk snippet --launcher-command thanks
                                          # print a snippet launcher bridge
kwwk context --save-workflow latest-cli-context
                                          # save newest capture as a workflow
kwwk history --save-workflow latest-ai-history
                                          # save newest AI run as a workflow
kwwk history --save-snippet latest-ai-history
                                          # save newest AI answer/error as a snippet
kwwk clipboard --show latest-clipboard    # print the newest saved clipboard item
kwwk clipboard --save-snippet latest-clipboard
                                          # save newest clipboard item as a snippet
kwwk launcher --ask-path ./README.md "summarize this file"
                                          # ask with bounded file/folder context
kwwk launcher --ask-path ./README.md --ask-path ./Package.swift "compare"
                                          # ask with multiple local contexts
kwwk launcher --command open-cli --run    # run a specific palette command
kwwk launcher --list-commands             # list command IDs for automation
kwwk launcher --list-commands ai --json   # filter and emit JSON
kwwk launcher --list-commands --include-workspace-files Package.swift
                                          # include indexed files from cwd
kwwk launcher --list-actions open-cli     # list secondary actions for a match
kwwk launcher --featured-actions open-cli # list preview-pane actions only
kwwk launcher --inspect-command open-cli --json
                                          # selected-command preview + actions
kwwk launcher --command open-cli --list-actions --json
                                          # JSON action payloads for scripts
kwwk launcher --command open-cli --action copy-launcher-command --run
                                          # run a specific secondary action
kwwk launcher --print-url --ask "..."     # inspect the generated deep link
```

Launcher deep links include the terminal working directory, so `--ask` runs from
the same checkout when the GUI starts the bundled `kwwk -p` helper, `Open KWWK
CLI` opens the interactive terminal agent in that checkout, and workspace
commands appear for revealing the active checkout or copying its path.
`--ask-stdin` captures piped terminal output into
`~/.kwwk/launcher/context/*.txt` and attaches that file as bounded AI context;
use `--stdin-name` when the saved context should have a readable filename.
Captured terminal contexts also become searchable `cli-context:` palette
commands under the CLI category, where the primary action asks KWWK about the
captured output and secondary actions can copy the raw captured output, copy the
AI ask prompt, save the capture as a reusable prompt command, snippet, or
workflow, reveal it, copy its path, or move the saved file to Trash. Scripts can
use the stable `latest-cli-context` command ID to ask about the newest captured
terminal output without parsing the generated file-specific command ID.
Use `--capture-stdin` when a terminal job should seed that context library
without opening the launcher immediately; the command prints the saved context
ID, path, and a replayable `kwwk launcher --command cli-context:... --run`
bridge, with `--json` for scripts.
The same captured-output library is inspectable from the terminal with
`kwwk context`, `kwwk context --show <id>`, and
`kwwk context --ask-command <id>`. Passing `latest-cli-context` targets the
newest capture without parsing a generated filename. Use
`kwwk context --save-prompt <id>`, `kwwk context --save-snippet <id>`, or
`kwwk context --save-workflow <id>` to promote a capture into
`~/.kwwk/launcher/prompts.json`, `~/.kwwk/launcher/snippets.json`, or
`~/.kwwk/launcher/workflows.json` from a script; add `--json` to get the saved
artifact ID, file path, command ID, and replayable launcher command.
Use `Reveal Terminal Contexts Folder`, `Reload Terminal Contexts`, or
`Clear Terminal Contexts` to inspect, refresh, or trash the captured-output
library from the palette.
Repeat `--ask-path` to attach multiple bounded file/folder contexts to one AI prompt.
The `--command` bridge addresses palette commands by ID, which avoids fuzzy
matching when a shell script or automation wants to run a specific launcher
command with query text as input. `--list-commands` prints tab-separated `id`,
`category`, `title`, and `subtitle` columns; add `--json` to include each
record's `launcherCommand` replay string and native `launcherURL` deep link for
scripts, Shortcuts, or app handoff, or `--include-apps` when you also want
installed macOS application commands. Add
`--include-workspace-files` when terminal automation should enumerate the same
bounded workspace-file results the app can show for the active checkout.
`--list-actions` resolves the top matching command, or an explicit
`--command <id>`, then prints its Raycast-style secondary actions; with `--json`
it includes action kind and payload fields for automation, including a
replayable `launcherCommand` for each action. The GUI action panel can also copy
the matching `--inspect-command --json` shell bridge for the selected result, so
external tools can fetch the same preview and compact action payload later.
Action JSON is rendered with the
terminal working directory as launcher context, so `{workspace}` and `{cwd}`
placeholders match the checkout that invoked the bridge. Every command also
exposes a `Copy Launcher URL` action for native `kwwk://launcher?...` app
handoff. Add `--action <id> --run` to target a specific secondary action through
the same deep-link bridge the app uses internally. Use `--featured-actions` when
an external script, picker, or status UI should show the same compact action set
as the launcher's preview pane instead of the full action panel. Use
`--inspect-command` for a selected result's preview text, primary action,
replayable launcher command, native launcher URL, and featured actions in one
JSON or text payload.

One-shot terminal AI runs with `kwwk -p` append their prompt, streamed output,
exit code, replay command, and working directory to the same
`~/.kwwk/launcher/ai-history.json` file used by the launcher. That makes CLI
answers searchable from `@ai`, visible in menu-bar recents, and available to
`kwwk launcher --list-commands ai --json` without giving up pipe-clean stdout.
The same store is inspectable without opening the GUI:

```sh
kwwk history                         # table of saved AI runs
kwwk history --json                  # automation-friendly history records
kwwk history --show <id>             # print saved output or error text
kwwk history --show <id> --json      # print one saved run as JSON
kwwk history --replay-command <id>   # print the shell command to rerun it
kwwk history --save-prompt <id>      # save the original prompt as a command
kwwk history --save-workflow <id>    # save the original prompt as a workflow
kwwk history --save-snippet <id>     # save answer/error output as a snippet
```

Scripts can pass `latest-ai-history` wherever this section accepts a history
ID. That targets the newest saved AI run, so external launchers and terminal
helpers can inspect or replay the last answer without parsing generated
`ai-history:<id>` command IDs. Use `--save-prompt` or `--save-workflow` to
promote the original prompt into `~/.kwwk/launcher/prompts.json` or
`~/.kwwk/launcher/workflows.json`; use `--save-snippet` to promote saved answer
or error output into `~/.kwwk/launcher/snippets.json`. Add `--json` to get the
saved artifact ID, file path, command ID, and replayable launcher command.

Script commands are plain executables. Metadata is optional, but lets the
launcher display and rank them cleanly:

```sh
#!/usr/bin/env bash
# @kwwk.title Summarize Repo
# @kwwk.subtitle Run a local automation from the launcher
# @kwwk.keywords git,summary,agent
# @kwwk.icon sparkles
# @kwwk.argument-mode stdin

kwwk -p -
```

`@kwwk.argument-mode` can be `none`, `argument`, or `stdin`. The launcher also
sets `KWWK_LAUNCHER_QUERY` and `KWWK_LAUNCHER_CWD` for every script run. Scripts
inherit the active launcher workspace by default, while `@kwwk.cwd` pins a
script-specific working directory. When a workspace is available, the launcher
also exports it as `KWWK_LAUNCHER_WORKSPACE`. It recognizes basic Raycast script
metadata such as `@raycast.title` and `@raycast.argument1`. Use the built-in
`Reveal Script Commands Folder` and `Reload Script Commands` commands from the
launcher while developing scripts. One-off shell rows created with `$ ...` also
include `Save as Script Command`, which writes an executable `.zsh` script with
KWWK metadata into `~/.kwwk/launcher/commands` and reloads the script catalog.
The same script catalog is inspectable from the terminal:

```sh
kwwk script                              # table of discovered script commands
kwwk script --json                       # automation-friendly records
kwwk script --show summarize-repo        # print one script preview
kwwk script --path summarize-repo        # print one executable path
kwwk script --launcher-command summarize-repo "staged diff"
                                         # print a replayable launcher command
kwwk script --dir ./commands --json      # scan another script directory
```

Replay commands include a `<query>` placeholder for scripts that declare
`@kwwk.argument-mode argument` or `stdin`; scripts with `none` mode export a
plain `kwwk launcher --command script:<id> --run` bridge unless explicit input
is supplied to `--launcher-command`.

Workflows live in `~/.kwwk/launcher/workflows.json` and become searchable
multi-step commands under `@workflows`. They can also run directly from the
terminal with `kwwk workflow <id> [input]`, and `kwwk workflow --list --json`
exports stable workflow metadata plus replayable `cliCommand` strings, so a GUI
workflow can become a scriptable CLI routine without opening the launcher. From
the action panel, `Open Workflow in Terminal` starts the same workflow with the
active workspace and configured CLI helper. One-off AI prompts and `$` shell
commands also expose `Save as Workflow`, which writes a one-step seed into
`workflows.json` that can be extended into a larger automation. Each step can
run a headless KWWK prompt or a shell command. Workflows can pin `model`,
`thinking`, and `context1m`; when a field is omitted, the launcher or CLI uses
the active default.
Templates support `{query}`, `{argument}`, `{clipboard}`, `{workspace}`, `{cwd}`,
`{finderSelection}`, `{frontmostApp}`, and `{previousOutput}`; the
previous-output placeholder carries the prior step's stdout or stderr into the
next step. Add `:q`, as in `{previousOutput:q}` or `{workspace:q}`, when a
placeholder should be shell-quoted for a command argument. Shell steps run from
the active launcher workspace and receive `KWWK_LAUNCHER_QUERY`,
`KWWK_LAUNCHER_CWD`, `KWWK_LAUNCHER_WORKSPACE`, and
`KWWK_LAUNCHER_PREVIOUS_OUTPUT`.

```json
[
  {
    "id": "review-and-test",
    "title": "Review And Test",
    "subtitle": "Review a change, then run the focused test",
    "keywords": ["ship"],
    "model": "gpt-5.4",
    "thinking": "high",
    "context1m": false,
    "steps": [
      {
        "title": "Review",
        "kind": "prompt",
        "template": "Review this change and name the focused Swift test to run.\n\n{query}\n\nWorkspace: {workspace}"
      },
      {
        "title": "Run Focused Test",
        "kind": "shell",
        "template": "swift test --filter {previousOutput:q}"
      }
    ]
  }
]
```

Quicklinks live in `~/.kwwk/launcher/quicklinks.json` and become searchable
launcher commands. URL templates can include `{query}` or `{argument}`; when a
query starts with the quicklink title or keyword, that trigger is stripped before
the value is percent-encoded into the URL. The action panel can copy the
rendered URL or a reusable `kwwk launcher --command ... --run -- <query>` bridge
for terminal automation. URL and web-search rows typed directly into the
launcher, such as `https://example.com/docs` or `web swift package manager`,
also include `Save as Quicklink`, which upserts a durable quicklink into the
same JSON file.
The same quicklink library is scriptable from the terminal:

```sh
kwwk quicklink                              # table of saved quicklinks
kwwk quicklink --json                       # automation-friendly records
kwwk quicklink --show github-search         # print one URL template
kwwk quicklink --render github-search "swift package manager"
                                            # render a percent-encoded URL
kwwk quicklink --launcher-command github-search
                                            # print a replayable launcher command
```

`kwwk quicklink --render` strips a leading title or keyword from the input before
percent-encoding, matching the launcher palette. Use `--file <path>` when tests
or scripts should read a separate quicklinks JSON file.

```json
[
  {
    "id": "github-search",
    "title": "GitHub Search",
    "subtitle": "Search GitHub code",
    "keywords": ["gh"],
    "urlTemplate": "https://github.com/search?q={query}&type=code"
  }
]
```

Command aliases live in `~/.kwwk/launcher/aliases.json` and give stable shortcut
names to existing command IDs. Aliases are searchable under `@aliases`, can be
favorited like any other command, and replay through the same
`kwwk launcher --command alias:<id> --run` bridge. Stable palette commands also
include `Save as Alias` in the action panel, which upserts a generated alias
record for the selected command so shortcuts can start in the GUI and be refined
later in JSON.
The same alias library is scriptable from the terminal:

```sh
kwwk alias                         # table of saved aliases
kwwk alias --json                  # automation-friendly records
kwwk alias --show term             # print one target command id
kwwk alias --target term           # print one target command id
kwwk alias --launcher-command term # print a replayable launcher command
```

Use `--file <path>` when tests or scripts should read a separate aliases JSON
file instead of the default launcher alias store.

```json
[
  {
    "id": "term",
    "title": "Terminal Here",
    "subtitle": "Open the interactive CLI",
    "targetCommandId": "open-cli",
    "keywords": ["terminal", "agent"]
  }
]
```

AI prompt commands live in `~/.kwwk/launcher/prompts.json` and run through the
same streamed `kwwk -p` path as built-in presets. Templates can use `{query}`,
`{argument}`, `{clipboard}`, `{workspace}`, `{cwd}`, `{finderSelection}`, and
`{frontmostApp}`. Like Quicklinks, typing the prompt title or keyword first
strips that trigger from the rendered `{query}`, and the action panel can copy
the rendered prompt, open it as an interactive CLI draft, or copy a reusable
`kwwk launcher --command ... --run -- <query>` bridge. One-off natural-language
AI rows and recent AI history items also include `Save as Prompt Command`, which
upserts the original prompt into this file so a useful prompt can become a
durable launcher command.
The same prompt command library is scriptable from the terminal:

```sh
kwwk prompt                              # table of saved prompt commands
kwwk prompt --json                       # automation-friendly records
kwwk prompt --show review-code           # print one raw prompt template
kwwk prompt --render review-code "diff"  # render with terminal context
kwwk prompt --launcher-command review-code
                                         # print a replayable launcher command
```

`kwwk prompt --render` uses the current working directory for `{workspace}` and
`{cwd}` by default. Pass `--clipboard`, `--workspace`, `--finder-selection`, or
`--frontmost-app` when a script needs deterministic placeholder values, and
`--file <path>` when tests should read a separate prompt JSON file.
The AI history store lives in `~/.kwwk/launcher/ai-history.json`, so GUI runs,
menu-bar recents, and `kwwk launcher --list-commands ai --json` all share the
same saved runs. Use `Reveal AI History File` or `Reload AI History` when you
want to inspect or refresh that file-backed history from the launcher. AI answer
and error output can also be saved as reusable snippets in
`~/.kwwk/launcher/snippets.json`. The history action panel carries the previous
answer or error text into `Ask KWWK About This` and `Open Context Draft in CLI`,
so old runs can become concrete follow-up context without copying text by hand.

```json
[
  {
    "id": "review-code",
    "title": "Review Code",
    "subtitle": "Review a diff, file, or selected Finder item",
    "keywords": ["review"],
    "promptTemplate": "Review this code carefully. Focus on bugs, regressions, and missing tests.\n\nQuery:\n{query}\n\nClipboard:\n{clipboard}\n\nWorkspace:\n{workspace}\n\nFinder selection:\n{finderSelection}"
  }
]
```

Snippets live in `~/.kwwk/launcher/snippets.json` and become searchable commands
whose primary action copies rendered text to the pasteboard. Templates support
the same placeholders as AI prompt commands: `{query}`, `{argument}`,
`{clipboard}`, `{workspace}`, `{cwd}`, `{finderSelection}`, and
`{frontmostApp}`. Fixed snippets stay fixed; add `{query}` or `{argument}` when
typed launcher text should be inserted. Like Quicklinks, typing the snippet
title or keyword first strips that trigger from the rendered query, and the
action panel can copy either the rendered snippet, the raw template, or a
reusable `kwwk launcher --command ... --run -- <query>` bridge. Calculator and
unit conversion rows also include `Save Result as Snippet`, so useful one-off
results can be promoted into the same snippet library. The response pane's
`Save Snippet` action captures the currently visible AI, script, workflow, or
command output directly into this same library.

```json
[
  {
    "id": "thanks",
    "title": "Thanks",
    "subtitle": "Short acknowledgement",
    "keywords": ["ty"],
    "textTemplate": "Thanks, {query}. I will take a look."
  }
]
```

Clipboard history is stored in `~/.kwwk/launcher/clipboard-history.json`.
Settings includes an opt-in `Track clipboard history` toggle for watching text
pasteboard changes while the resident app runs; `Capture Current Clipboard`
still forces a manual capture, `@clipboard` filters saved entries, and `Clear
Clipboard History` or `Reveal Clipboard History File` manages the store. Use a
clipboard item's `Save as Snippet` action to upsert that text into
`~/.kwwk/launcher/snippets.json` as a reusable snippet command.

The same clipboard store is scriptable from the terminal:

```sh
kwwk clipboard                         # table of saved clipboard entries
kwwk clipboard --json                  # automation-friendly records
kwwk clipboard --show latest-clipboard # print the newest saved clipboard text
kwwk clipboard --save-snippet latest-clipboard --json
                                       # save newest clipboard text as snippet
```

Pass `latest-clipboard` wherever this section accepts a clipboard item ID to
target the newest saved text without parsing generated `clipboard:<id>` command
IDs. Use `--snippet-file <path>` when tests or scripts should write snippets to
a separate JSON file instead of the default launcher snippet store.

The snippet library is scriptable too:

```sh
kwwk snippet                           # table of saved snippets
kwwk snippet --json                    # automation-friendly records
kwwk snippet --show thanks             # print one raw snippet template
kwwk snippet --render thanks "Alice"   # render with terminal context
kwwk snippet --launcher-command thanks # print a replayable launcher command
```

`kwwk snippet --render` uses the current working directory for `{workspace}` and
`{cwd}` by default. Pass `--clipboard`, `--workspace`, `--finder-selection`, or
`--frontmost-app` when a script needs deterministic placeholder values, and
`--file <path>` when tests should read a separate snippet JSON file.

---

## 3. The agent SDK

Add `kwwk` as a SwiftPM dependency:

```swift
.package(url: "https://github.com/EYHN/kwwk", branch: "main"),
```

Then depend on the libraries you need:

```swift
.product(name: "KWWKAgent", package: "kwwk"),
.product(name: "KWWKAI",    package: "kwwk"),
```

- **`KWWKAI`** — model clients, provider registry, streaming, OAuth,
  message / tool types.
- **`KWWKAgent`** — the turn/tool loop, built-in coding tools, hooks.

### Quick start — one-shot run

`Agent.runOnce` mirrors `query()` in the Python Agent SDK: a fresh agent
runs a single prompt and yields every event as an async stream.

```swift
import KWWKAI
import KWWKAgent

// 1. Register a provider using an API key.
await registerBuiltins(anthropic: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"])

// 2. Build a coding agent scoped to a working directory.
let agent = await makeCodingAgent(CodingAgentConfig(
    model: Models.claudeSonnet45,
    cwd: FileManager.default.currentDirectoryPath,
    tools: .all
))

// 3. Drive it.
try await agent.prompt("Summarize the Swift files under Sources/KWWKAgent.")

// 4. Read the transcript.
for message in agent.state.messages {
    print(message)
}
```

### Subagents

`CodingAgentConfig.subagents` defaults to an empty array. When it is
empty, `makeCodingAgent` does not register the `agent` tool. Add
subagent definitions explicitly when you want model-driven delegation:

```swift
let reviewer = SubagentDefinition(
    name: "reviewer",
    description: "Use for code quality, security, maintainability, and test coverage review.",
    prompt: """
    You are a senior code reviewer. Review code carefully, do not edit files,
    and report findings with file paths, severity, and concrete evidence.
    """,
    tools: .readOnly,
    model: .inherit
)

let bg = BackgroundTaskManager()
let agent = await makeCodingAgent(CodingAgentConfig(
    model: Models.claudeSonnet45,
    cwd: FileManager.default.currentDirectoryPath,
    tools: .all,
    backgroundManager: bg,
    subagents: [reviewer]
))

try await agent.prompt("Use the reviewer subagent to review Sources/KWWKAgent.")
```

For the same built-ins that the CLI uses, SDK users can opt in without
copying prompts:

```swift
let agent = await makeCodingAgent(CodingAgentConfig(
    model: Models.claudeSonnet45,
    cwd: FileManager.default.currentDirectoryPath,
    tools: .all,
    backgroundManager: BackgroundTaskManager()
).withBuiltinSubagents([.general, .explore, .plan]))
```

SDK users can also run a subagent directly:

```swift
let runner = SubagentRunner(
    cwd: FileManager.default.currentDirectoryPath,
    subagents: [.plan()],
    parentModel: Models.claudeSonnet45
)
let result = try await runner.run(
    type: "Plan",
    prompt: "Plan how to simplify Sources/KWWKAgent/SubagentTool.swift."
)
```

Subagents are fresh-context agents: they do not inherit the parent
transcript. The parent model must put the relevant files, errors, goals,
and constraints into the `agent` tool's `prompt`. Subagents inherit the
parent model, thinking level, retry delay, and API key resolver, but they
do not inherit parent hooks such as `betweenTurns`, `transformContext`,
`convertToLlm`, `userPromptSubmit`, or tool-call hooks.

Each subagent run gets its own child session id. Tools inside that
subagent, including background-capable tools such as Bash, are scoped to
the child session. While the child agent is running, background task
notifications are attached to that child session. When the subagent
finishes or is cancelled, the generic background-task session is closed:
still-running tasks in that child session are killed and queued
notifications for that child session are discarded. If the parent starts
the subagent itself with `run_in_background`, that top-level subagent job
remains parent-visible so `wait_task` and completion notifications still
work.

In the interactive TUI, foreground subagent tool calls update their
in-flight display with the child agent's token usage as it runs. When a
provider does not stream exact usage until the end of the turn, the live
counter falls back to an approximate output-token estimate and is
replaced by provider-reported usage once available.

Subagent tools also emit structured runtime events through
`AgentEvent.runtimeEvent(.subagent(...))`: started, tool update,
background started, completed, and failed. The terminal
`AgentRunSummary.subagents` array records each foreground child run's
usage, cost, turns, duration, status, model, and child session id.
Background subagents are recorded when the parent-visible background task
is started; their completion is delivered through the existing
background-task notification flow.

The interactive `kwwk` CLI enables a small built-in set by default:
`general`, `Explore`, and `Plan`. `general` has wildcard tools by
default and is used when the model omits `subagent_type`. `Explore` and
`Plan` are read-only specialists. Use `--no-subagents` to disable them
or `--subagents general,Explore` to enable only a subset. The SDK does
not enable those automatically.

When an SDK application is done with an agent session, call
`await agent.closeSession()` to release provider-owned resources keyed by
that session id. For OpenAI Responses WebSocket transport, this closes the
stored WebSocket connection for the session.

### Streaming events

Subscribe before prompting to observe tokens, tool calls, and the final
summary as they happen:

```swift
let unsubscribe = agent.subscribe { event, _ in
    switch event {
    case .messageUpdate(let assistant, _):
        // Live-render streaming assistant tokens.
        print(assistant.textPreview, terminator: "")
    case .toolExecutionStart(_, let name, let args):
        print("→ \(name) \(args)")
    case .agentEnd(_, let summary):
        print("\n[\(summary.turns) turns · $\(summary.cost.total)]")
    default: break
    }
}
defer { unsubscribe() }

try await agent.prompt("Find all TODOs in this repo.")
```

Or consume `runOnce` as an `AsyncThrowingStream`:

```swift
for try await event in Agent.runOnce(
    prompt: "what's in README.md?",
    options: AgentOptions(initialState: AgentInitialState(
        model: Models.claudeHaiku45,
        tools: [createReadTool(cwd: ".")]
    ))
) {
    if case .messageEnd(let message) = event { print(message) }
}
```

### Custom tools

A tool is a name, a JSON-Schema parameter spec, and an async `execute`
closure. The agent handles validation, cancellation, and wiring the
result back into the transcript.

```swift
import KWWKAI
import KWWKAgent

let weather = AgentTool(
    name: "get_weather",
    label: "weather",
    description: "Look up the current temperature for a city.",
    parameters: [
        "type": "object",
        "properties": [
            "city": ["type": "string", "description": "City name"]
        ],
        "required": ["city"]
    ],
    execute: { _, args, _, _ in
        guard case .object(let obj) = args,
              case .string(let city) = obj["city"] ?? .null else {
            throw CodingToolError.invalidArgument("city required")
        }
        let temp = try await fetchTemp(city)
        return AgentToolResult(content: [.text(.init(text: "\(temp)°C in \(city)"))])
    }
)

let agent = Agent(initialState: AgentInitialState(
    model: Models.claudeSonnet45,
    tools: [weather]
))
try await agent.prompt("Is it warmer in Tokyo or Oslo right now?")
```

### Hooks — audit, redact, short-circuit

Every `AgentOptions` accepts hooks that fire at well-defined points. Use
them to enforce policy without forking the loop:

```swift
let options = AgentOptions(
    initialState: AgentInitialState(model: Models.claudeSonnet45, tools: [...]),
    // Block or rewrite a tool call before it runs.
    beforeToolCall: { ctx, _ in
        if ctx.toolCall.name == "bash",
           case .object(let o) = ctx.args,
           case .string(let cmd) = o["command"] ?? .null,
           cmd.contains("rm -rf") {
            return BeforeToolCallResult(block: true, reason: "destructive command blocked")
        }
        return nil
    },
    // Intercept a user prompt before it enters the transcript.
    userPromptSubmit: { ctx, _ in
        // e.g. redact secrets, inject policy preamble.
        return nil
    }
)
let agent = Agent(options: options)
```

Other hook points: `afterToolCall`, `convertToLlm`, `transformContext`
(for context pruning / summarization).

### Steering a running agent

Queue a message that will be injected at the next turn boundary —
without aborting the current turn:

```swift
Task {
    try await agent.prompt("refactor this module end-to-end")
}

// later, from any thread:
agent.steer(UserMessage(text: "also add tests as you go"))
```

### Providers

`registerBuiltins` covers Anthropic, OpenAI (Completions + Responses),
and Google Gemini. `Models` exposes a small curated catalog
(`claudeSonnet45`, `gpt5`, `gemini25Pro`, …) or you can construct
`Model` values by hand. For OpenAI-compatible endpoints (xAI, Groq,
OpenRouter) there are `Models.xaiGrok(id:)`, `Models.groq(id:)`,
`Models.openRouter(id:)` helpers.

To use a subscription (OAuth) token instead of a raw API key, drive the
flow via `KWWKAI.OAuth` / `OAuthLogin` — the same code path the CLI's
`kwwk login` command uses.

### Updating the model catalog

`/model` reads the bundled catalog at
`Sources/KWWKAI/Resources/models.json`, generated from pi-mono's
`packages/ai/src/models.generated.ts`.

```sh
swift run kwwk-generate-models /path/to/pi-mono/packages/ai/src/models.generated.ts
swift test
```

The generator writes `Sources/KWWKAI/Resources/models.json` by default.
The catalog tests assert unsupported Google Gemini CLI and Google
Antigravity provider groups stay absent.

---

## Layout

- `Sources/KWWKAI` — model clients, OAuth, provider adapters
- `Sources/KWWKAgent` — tool-using agent loop and built-in tools
- `Sources/KWWKCli` — interactive TUI, slash commands, rendering
- `Sources/kwwk` — the executable entry point
- `Sources/KWWKLauncher` — macOS SwiftUI launcher app
- `Sources/KWWKLauncherCore` — launcher command catalog, filtering, CLI invocation
- `Tests/` — XCTest suites for each module

```sh
swift test
```

## A note on OAuth client IDs

`Sources/KWWKAI/OAuthProviders.swift` reuses the OAuth client IDs (and,
where applicable, public app metadata) shipped by the upstream
first-party CLIs — Anthropic's Claude Code, OpenAI's Codex CLI, and
GitHub Copilot's VS Code extension. Those credentials are not secrets in
any meaningful sense — they are embedded in those open-source CLIs and
are required for the "log in with your existing subscription" flow to
work. They remain the property of their respective vendors, who may
rotate or revoke them at any time. `kwwk` is not affiliated with or
endorsed by any of these vendors.

## License

MIT — see [LICENSE](LICENSE).
