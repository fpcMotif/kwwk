import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import KWWKAgent
import KWWKCli
import KWWKLauncherCore

private struct RuntimeOptions {
    var thinkingLevel: ThinkingLevel
    var modelOverride: String?
    var context1m: Bool
}

/// `kwwk` — coding-agent CLI. Dispatches on argv:
///
///   kwwk                    → interactive coding TUI (uses creds from `kwwk login`)
///   kwwk --draft <prompt>   → interactive TUI with the prompt prefilled
///   kwwk login              → TUI-driven OAuth / API-key login
///   kwwk -p <prompt>        → one-shot, non-interactive run (stdout = reply)
///   kwwk launcher [query]   → open the macOS launcher with an optional query
///   kwwk launcher --ask-stdin
///                            → send stdin as AI context to the launcher
///   kwwk workflow <id>      → run a saved launcher workflow in the terminal
///   kwwk history            → list shared launcher / CLI AI history
///   kwwk prompt             → list saved launcher AI prompt commands
///   kwwk quicklink          → list saved launcher quicklinks
///   kwwk alias              → list saved launcher command aliases
///   kwwk script             → list launcher script commands
///   kwwk snippet            → list saved launcher snippets
///   kwwk context            → list saved terminal contexts
///   kwwk profile            → list shared launcher AI runtime profiles
///   kwwk --help             → usage
///
/// Global flags (apply to both TUI and headless `-p`):
///   `--thinking <off|minimal|low|medium|high|xhigh>` — reasoning effort, default `medium`.
///   `--model <id>`     — override the resolved provider's default model id
///                        (e.g. `--model claude-opus-4-5`). Catalog metadata
///                        is looked up by id; unknown ids fall back to sane
///                        defaults for `contextWindow` / `maxTokens`.
///   `--context-1m`     — opt into Anthropic's 1M-context beta. Adds
///                        `context-1m-2025-08-07` to the `anthropic-beta`
///                        header and bumps `contextWindow` to 1_000_000.
///                        Requires the account to have long-context billing
///                        enabled. Ignored for non-Anthropic providers.
///   `--profile <id>`   — start from a saved launcher AI profile, then let
///                        explicit --thinking, --model, and --context-1m flags
///                        override it.
@main
struct KwwkCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        let thinkingLevel: ThinkingLevel
        let thinkingSpecified: Bool
        let parsedThinking = extractThinking(args)
        args = parsedThinking.0
        thinkingLevel = parsedThinking.1
        thinkingSpecified = parsedThinking.2
        let modelOverride: String?
        (args, modelOverride) = extractStringFlag(args, "--model")
        let profileId: String?
        (args, profileId) = extractStringFlag(args, "--profile")
        let context1m: Bool
        (args, context1m) = extractBoolFlag(args, "--context-1m")
        let draftPrompt: String?
        (args, draftPrompt) = extractStringFlag(args, "--draft")

        let subcommand = args.first

        switch subcommand {
        case nil:
            let runtime = resolvedRuntimeOptions(
                profileId: profileId,
                thinkingLevel: thinkingLevel,
                thinkingSpecified: thinkingSpecified,
                modelOverride: modelOverride,
                context1m: context1m
            )
            await runOrExit { try await KWWK.runCodingTUI(
                thinkingLevel: runtime.thinkingLevel,
                modelOverride: runtime.modelOverride,
                context1m: runtime.context1m,
                initialPrompt: readDraftPrompt(draftPrompt)
            ) }
        case "login":
            await runOrExit { try await KWWK.runLogin() }
        case "launcher":
            runLauncher(rest: Array(args.dropFirst()))
        case "workflow":
            let runtime = resolvedRuntimeOptions(
                profileId: profileId,
                thinkingLevel: thinkingLevel,
                thinkingSpecified: thinkingSpecified,
                modelOverride: modelOverride,
                context1m: context1m
            )
            await runWorkflow(
                rest: Array(args.dropFirst()),
                thinkingLevel: runtime.thinkingLevel,
                modelOverride: runtime.modelOverride,
                context1m: runtime.context1m
            )
        case "history":
            runHistory(rest: Array(args.dropFirst()))
        case "prompt", "prompts":
            runPrompt(rest: Array(args.dropFirst()))
        case "quicklink", "quicklinks":
            runQuicklink(rest: Array(args.dropFirst()))
        case "alias", "aliases":
            runAlias(rest: Array(args.dropFirst()))
        case "script", "scripts":
            runScriptCommand(rest: Array(args.dropFirst()))
        case "snippet", "snippets":
            runSnippet(rest: Array(args.dropFirst()))
        case "clipboard", "clipboards", "clips":
            runClipboard(rest: Array(args.dropFirst()))
        case "context", "contexts":
            runContext(rest: Array(args.dropFirst()))
        case "profile", "profiles":
            runProfile(rest: Array(args.dropFirst()))
        case "-p", "--print":
            let runtime = resolvedRuntimeOptions(
                profileId: profileId,
                thinkingLevel: thinkingLevel,
                thinkingSpecified: thinkingSpecified,
                modelOverride: modelOverride,
                context1m: context1m
            )
            await runPrint(
                rest: Array(args.dropFirst()),
                thinkingLevel: runtime.thinkingLevel,
                modelOverride: runtime.modelOverride,
                context1m: runtime.context1m
            )
        case "-h", "--help":
            printUsage()
        default:
            FileHandle.standardError.write(Data("kwwk: unknown subcommand '\(subcommand!)'\n\n".utf8))
            printUsage()
            Foundation.exit(2)
        }
    }

    static func printUsage() {
        print("""
        kwwk — coding-agent CLI

        usage:
          kwwk                        launch the interactive coding TUI
          kwwk --draft <prompt>       launch the TUI with a prefilled prompt
          kwwk --draft -              read a draft prompt from stdin
          kwwk login                  log in to an OAuth provider
          kwwk -p <prompt>            run a one-shot prompt and print the reply
          kwwk -p                     read the prompt from stdin
          kwwk launcher [query]       open the macOS launcher with a query
          kwwk workflow <id> [input]  run a saved launcher workflow locally
          kwwk workflow --list        list saved launcher workflows
          kwwk history                list shared launcher / CLI AI history
          kwwk history --show <id>    print one history record's output
          kwwk history --save-workflow <id>
                                      save one history prompt as a workflow
          kwwk history --save-snippet <id>
                                      save one history answer/error as a snippet
          kwwk prompt                 list shared launcher prompt commands
          kwwk prompt --render <id> [input]
                                      render one prompt command locally
          kwwk quicklink              list shared launcher quicklinks
          kwwk quicklink --render <id> [input]
                                      render one quicklink URL locally
          kwwk alias                  list shared launcher command aliases
          kwwk alias --launcher-command <id>
                                      print one alias launcher bridge
          kwwk script                 list launcher script commands
          kwwk script --launcher-command <id> [input]
                                      print one script launcher bridge
          kwwk snippet                list shared launcher snippets
          kwwk snippet --render <id> [input]
                                      render one snippet locally
          kwwk clipboard              list shared launcher clipboard history
          kwwk clipboard --show <id>  print one clipboard history item
          kwwk clipboard --save-snippet <id>
                                      save one clipboard item as a snippet
          kwwk context                list saved terminal contexts
          kwwk context --show <id>    print one captured context
          kwwk context --save-prompt <id>
                                  save a captured context as a prompt command
          kwwk context --save-snippet <id>
                                  save a captured context as a snippet
          kwwk context --save-workflow <id>
                                  save a captured context as a workflow
          kwwk profile --list         list shared launcher AI profiles
          kwwk launcher --ask <prompt>
                                      open the launcher and run an AI prompt
          kwwk launcher --ask-stdin <prompt>
                                      attach stdin as launcher AI context
          kwwk launcher --toggle      show or hide the resident launcher
          kwwk launcher --hide        hide the resident launcher
          kwwk launcher --command <id>
                                      open a specific launcher command
          kwwk launcher --command <id> --action <id> --run
                                      run a secondary launcher action
          kwwk launcher --list-commands
                                      list launcher command IDs for automation
          kwwk launcher --list-actions [query]
                                      list action IDs for the top launcher match
          kwwk launcher --print-url   print the launcher deep link
          kwwk --help                 show this message

        global options:
          --thinking <level>          reasoning effort: off, minimal, low,
                                      medium (default), high, xhigh
          --model <id>                override the provider's default model id
                                      (e.g. --model claude-opus-4-5)
          --context-1m                opt into Anthropic 1M-context beta
                                      (long-context billing must be on)
          --profile <id>              use a saved launcher AI profile
          --draft <prompt>            prefill the interactive TUI prompt

        Credentials are read from the OAuth store at ~/.kwwk/oauth.json.
        Run `kwwk login` once to register a provider (OAuth subscription
        or API key).
        """)
    }

    private static func resolvedRuntimeOptions(
        profileId: String?,
        thinkingLevel: ThinkingLevel,
        thinkingSpecified: Bool,
        modelOverride: String?,
        context1m: Bool
    ) -> RuntimeOptions {
        guard let profileId else {
            return RuntimeOptions(
                thinkingLevel: thinkingLevel,
                modelOverride: modelOverride,
                context1m: context1m
            )
        }

        let customProfiles = LauncherAIProfileIndex.load()
        guard let profile = LauncherAIProfileCatalog.profile(
            matching: profileId,
            customProfiles: customProfiles
        ) else {
            writeStderr("kwwk: no AI profile matched '\(profileId)' in \(LauncherAIProfileIndex.defaultURL().path)\n")
            Foundation.exit(2)
        }

        let resolvedThinking = thinkingSpecified
            ? thinkingLevel
            : ThinkingLevel(rawValue: profile.thinking.rawValue) ?? thinkingLevel
        let profileModel = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = modelOverride ?? (profileModel.isEmpty ? nil : profileModel)

        return RuntimeOptions(
            thinkingLevel: resolvedThinking,
            modelOverride: resolvedModel,
            context1m: context1m || profile.context1m
        )
    }

    static func runHistory(rest: [String]) {
        var historyFile: URL?
        var listJSON = false
        var showId: String?
        var replayId: String?
        var savePromptId: String?
        var saveWorkflowId: String?
        var saveSnippetId: String?
        var promptFile: URL?
        var workflowFile: URL?
        var snippetFile: URL?
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-runs":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history --file needs a path\n")
                    Foundation.exit(2)
                }
                historyFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--show", "--output":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history \(rest[i]) needs a record id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--replay-command", "--replay":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history \(rest[i]) needs a record id\n")
                    Foundation.exit(2)
                }
                replayId = rest[i + 1]
                i += 2
            case "--save-prompt", "--save-prompt-command":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history \(rest[i]) needs a record id\n")
                    Foundation.exit(2)
                }
                savePromptId = rest[i + 1]
                i += 2
            case "--save-workflow":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history \(rest[i]) needs a record id\n")
                    Foundation.exit(2)
                }
                saveWorkflowId = rest[i + 1]
                i += 2
            case "--save-snippet", "--save-output-snippet", "--save-answer-snippet", "--save-error-snippet":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history \(rest[i]) needs a record id\n")
                    Foundation.exit(2)
                }
                saveSnippetId = rest[i + 1]
                i += 2
            case "--prompt-file", "--prompts-file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                promptFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--workflow-file", "--workflows-file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                workflowFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--snippet-file", "--snippets-file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: history \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                snippetFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "-h", "--help":
                printHistoryUsage()
                Foundation.exit(0)
            default:
                guard showId == nil else {
                    writeStderr("kwwk: unexpected history argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                showId = rest[i]
                i += 1
            }
        }

        let requestedActionCount = [showId, replayId, savePromptId, saveWorkflowId, saveSnippetId]
            .compactMap { $0 }
            .count
        if requestedActionCount > 1 {
            writeStderr("kwwk: history actions cannot be combined\n")
            Foundation.exit(2)
        }

        let url = historyFile ?? AIRunHistoryStore.defaultURL()
        let history = AIRunHistoryStore.load(from: url)

        if let replayId {
            let record = requireHistoryRecord(replayId, in: history, source: url)
            print(record.terminalReplayCommand)
            return
        }

        if let savePromptId {
            let record = requireHistoryRecord(savePromptId, in: history, source: url)
            saveHistoryPromptCommand(record, to: promptFile ?? LauncherPromptCommandIndex.defaultURL(), asJSON: listJSON)
            return
        }

        if let saveWorkflowId {
            let record = requireHistoryRecord(saveWorkflowId, in: history, source: url)
            saveHistoryWorkflow(record, to: workflowFile ?? LauncherWorkflowIndex.defaultURL(), asJSON: listJSON)
            return
        }

        if let saveSnippetId {
            let record = requireHistoryRecord(saveSnippetId, in: history, source: url)
            saveHistorySnippet(record, to: snippetFile ?? LauncherSnippetIndex.defaultURL(), asJSON: listJSON)
            return
        }

        if let showId {
            let record = requireHistoryRecord(showId, in: history, source: url)
            if listJSON {
                do {
                    print(try AIRunHistoryExport.json(for: AIRunHistory(records: [record])))
                } catch {
                    writeStderr("kwwk: failed to encode AI history: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                writeStdout(record.previewText)
                if !record.previewText.hasSuffix("\n") {
                    writeStdout("\n")
                }
            }
            return
        }

        printHistoryList(history, asJSON: listJSON)
    }

    static func printHistoryUsage() {
        print("""
        kwwk history — inspect shared launcher / CLI AI history

        usage:
          kwwk history                         list ~/.kwwk/launcher/ai-history.json
          kwwk history --json                  list history as automation JSON
          kwwk history --show <id>             print a record's output or error
          kwwk history --show <id> --json      print one record as JSON
          kwwk history --replay-command <id>   print a shell replay command
          kwwk history --save-prompt <id>      save a history prompt command
          kwwk history --save-workflow <id>    save a one-step history workflow
          kwwk history --save-snippet <id>     save answer/error as snippet
          kwwk history --file <path> --json    read another history file
          kwwk history --prompt-file <path>    write prompts to another JSON file
          kwwk history --workflow-file <path>  write workflows to another JSON file
          kwwk history --snippet-file <path>   write snippets to another JSON file

        `kwwk -p` and launcher AI runs write to the same history store, so
        terminal runs can be searched in the launcher and inspected here.
        Use `latest-ai-history` as the id for the newest saved run.
        """)
    }

    static func printHistoryList(_ history: AIRunHistory, asJSON: Bool = false) {
        if asJSON {
            do {
                print(try AIRunHistoryExport.json(for: history))
            } catch {
                writeStderr("kwwk: failed to encode AI history: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\tcreatedAt\texit\ttitle\tpreview")
            let table = AIRunHistoryExport.table(for: history)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func saveHistoryPromptCommand(_ record: AIRunHistoryRecord, to url: URL, asJSON: Bool) {
        let promptCommand = LauncherPromptCommandIndex.promptCommand(from: record)
        do {
            try LauncherPromptCommandIndex.upsert(promptCommand, to: url)
            printSavedArtifact(
                LauncherSavedArtifactExportRecord(promptCommand: promptCommand, path: url),
                asJSON: asJSON
            )
        } catch {
            writeStderr("kwwk: failed to save prompt command for AI history '\(record.id)': \(error)\n")
            Foundation.exit(1)
        }
    }

    static func saveHistoryWorkflow(_ record: AIRunHistoryRecord, to url: URL, asJSON: Bool) {
        let workflow = LauncherWorkflowIndex.workflow(from: record)
        do {
            try LauncherWorkflowIndex.upsert(workflow, to: url)
            printSavedArtifact(
                LauncherSavedArtifactExportRecord(workflow: workflow, path: url),
                asJSON: asJSON
            )
        } catch {
            writeStderr("kwwk: failed to save workflow for AI history '\(record.id)': \(error)\n")
            Foundation.exit(1)
        }
    }

    static func saveHistorySnippet(_ record: AIRunHistoryRecord, to url: URL, asJSON: Bool) {
        guard let snippet = LauncherSnippetIndex.snippet(fromAIHistoryOutput: record) else {
            writeStderr("kwwk: AI history '\(record.id)' has no answer or error output to save as a snippet\n")
            Foundation.exit(2)
        }

        do {
            try LauncherSnippetIndex.upsert(snippet, to: url)
            printSavedArtifact(
                LauncherSavedArtifactExportRecord(snippet: snippet, path: url),
                asJSON: asJSON
            )
        } catch {
            writeStderr("kwwk: failed to save snippet for AI history '\(record.id)': \(error)\n")
            Foundation.exit(1)
        }
    }

    static func requireHistoryRecord(
        _ id: String,
        in history: AIRunHistory,
        source: URL
    ) -> AIRunHistoryRecord {
        if let record = historyRecord(matching: id, in: history) {
            return record
        }
        writeStderr("kwwk: no AI history record matched '\(id)' in \(source.path)\n")
        Foundation.exit(2)
    }

    static func historyRecord(matching id: String, in history: AIRunHistory) -> AIRunHistoryRecord? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == AIRunHistoryCommandFactory.latestCommandId {
            return history.records.first
        }

        let normalized = trimmed.hasPrefix(AIRunHistoryCommandFactory.commandPrefix)
            ? String(trimmed.dropFirst(AIRunHistoryCommandFactory.commandPrefix.count))
            : trimmed
        return history.record(id: normalized)
    }

    static func runPrompt(rest: [String]) {
        var promptFile: URL?
        var listJSON = false
        var showId: String?
        var renderId: String?
        var launcherCommandId: String?
        var launcherURLId: String?
        var clipboard = ""
        var workingDirectory: String? = FileManager.default.currentDirectoryPath
        var finderSelectionPaths: [String] = []
        var frontmostApplicationName: String?
        var queryTokens: [String] = []
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-prompts":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt --file needs a path\n")
                    Foundation.exit(2)
                }
                promptFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--show", "--template":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt \(rest[i]) needs a prompt command id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--render":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt --render needs a prompt command id\n")
                    Foundation.exit(2)
                }
                renderId = rest[i + 1]
                i += 2
            case "--launcher-command", "--command", "--replay-command":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt \(rest[i]) needs a prompt command id\n")
                    Foundation.exit(2)
                }
                launcherCommandId = rest[i + 1]
                i += 2
            case "--launcher-url":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt --launcher-url needs a prompt command id\n")
                    Foundation.exit(2)
                }
                launcherURLId = rest[i + 1]
                i += 2
            case "--clipboard":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt --clipboard needs text\n")
                    Foundation.exit(2)
                }
                clipboard = rest[i + 1]
                i += 2
            case "--workspace", "--cwd":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                workingDirectory = rest[i + 1]
                i += 2
            case "--finder-selection":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt --finder-selection needs a path\n")
                    Foundation.exit(2)
                }
                finderSelectionPaths.append(rest[i + 1])
                i += 2
            case "--frontmost-app":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: prompt --frontmost-app needs an app name\n")
                    Foundation.exit(2)
                }
                frontmostApplicationName = rest[i + 1]
                i += 2
            case "-h", "--help":
                printPromptUsage()
                Foundation.exit(0)
            case "--":
                queryTokens += rest.dropFirst(i + 1)
                i = rest.count
            default:
                if renderId != nil || launcherCommandId != nil || launcherURLId != nil {
                    queryTokens.append(rest[i])
                } else if showId == nil && launcherCommandId == nil && launcherURLId == nil {
                    showId = rest[i]
                } else {
                    writeStderr("kwwk: unexpected prompt argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                i += 1
            }
        }

        let requestedActionCount = [showId, renderId, launcherCommandId, launcherURLId]
            .compactMap { $0 }
            .count
        if requestedActionCount > 1 {
            writeStderr("kwwk: prompt actions cannot be combined\n")
            Foundation.exit(2)
        }
        if !queryTokens.isEmpty && renderId == nil && launcherCommandId == nil && launcherURLId == nil {
            writeStderr("kwwk: prompt input requires --render, --launcher-command, or --launcher-url\n")
            Foundation.exit(2)
        }

        let url = promptFile ?? LauncherPromptCommandIndex.defaultURL()
        let promptCommands = LauncherPromptCommandIndex.load(from: url)

        if let launcherCommandId {
            let promptCommand = requirePromptCommand(launcherCommandId, in: promptCommands, source: url)
            print(promptLauncherCommand(for: promptCommand, query: readPromptQuery(tokens: queryTokens)))
            return
        }

        if let launcherURLId {
            let promptCommand = requirePromptCommand(launcherURLId, in: promptCommands, source: url)
            print(promptLauncherURL(for: promptCommand, query: readPromptQuery(tokens: queryTokens)))
            return
        }

        if let renderId {
            let promptCommand = requirePromptCommand(renderId, in: promptCommands, source: url)
            let context = LauncherContextSnapshot(
                workingDirectory: workingDirectory,
                finderSelectionPaths: finderSelectionPaths,
                frontmostApplicationName: frontmostApplicationName
            )
            let rendered = promptCommand.renderedPrompt(
                query: readPromptQuery(tokens: queryTokens),
                clipboard: clipboard,
                context: context
            )
            writeStdout(rendered)
            if !rendered.hasSuffix("\n") {
                writeStdout("\n")
            }
            return
        }

        if let showId {
            let promptCommand = requirePromptCommand(showId, in: promptCommands, source: url)
            if listJSON {
                do {
                    print(try LauncherPromptCommandExport.json(for: promptCommand))
                } catch {
                    writeStderr("kwwk: failed to encode prompt command: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                writeStdout(promptCommand.promptTemplate)
                if !promptCommand.promptTemplate.hasSuffix("\n") {
                    writeStdout("\n")
                }
            }
            return
        }

        printPromptList(promptCommands, asJSON: listJSON)
    }

    static func printPromptUsage() {
        print("""
        kwwk prompt — inspect shared launcher AI prompt commands

        usage:
          kwwk prompt                         list ~/.kwwk/launcher/prompts.json
          kwwk prompt --json                  list prompt commands as automation JSON
          kwwk prompt --show <id>             print one prompt template
          kwwk prompt --show <id> --json      print one prompt command as JSON
          kwwk prompt --render <id> [input]   render one prompt with input
          kwwk prompt --render <id> -         read render input from stdin
          kwwk prompt --launcher-command <id> print a launcher replay command
          kwwk prompt --launcher-url <id>     print a native launcher URL
          kwwk prompt --file <path> --json    read another prompts file

        Rendered prompts support {query}, {clipboard}, {workspace}, {cwd},
        {finderSelection}, and {frontmostApp}. Use --clipboard, --workspace,
        --finder-selection, and --frontmost-app to provide deterministic
        terminal context for scripts.
        """)
    }

    static func printPromptList(_ promptCommands: [LauncherPromptCommand], asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherPromptCommandExport.json(for: promptCommands))
            } catch {
                writeStderr("kwwk: failed to encode prompt commands: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\ttitle\tsubtitle\tpromptTemplate\tlauncherCommand")
            let table = LauncherPromptCommandExport.table(for: promptCommands)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func requirePromptCommand(
        _ id: String,
        in promptCommands: [LauncherPromptCommand],
        source: URL
    ) -> LauncherPromptCommand {
        if let promptCommand = promptCommand(matching: id, in: promptCommands) {
            return promptCommand
        }
        writeStderr("kwwk: no prompt command matched '\(id)' in \(source.path)\n")
        Foundation.exit(2)
    }

    static func promptCommand(
        matching id: String,
        in promptCommands: [LauncherPromptCommand]
    ) -> LauncherPromptCommand? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("prompt:")
            ? String(trimmed.dropFirst("prompt:".count))
            : trimmed

        return promptCommands.first { promptCommand in
            promptCommand.id == normalized
                || promptCommand.id.hasPrefix(normalized)
                || promptCommand.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    static func promptLauncherCommand(for promptCommand: LauncherPromptCommand, query: String) -> String {
        let argument = promptCommand.argument(from: query)
        let queryArgument = argument.isEmpty ? "<query>" : argument
        return [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote("prompt:\(promptCommand.id)"),
            "--run",
            "--",
            KWWKShellCommand.quote(queryArgument),
        ].joined(separator: " ")
    }

    static func promptLauncherURL(for promptCommand: LauncherPromptCommand, query: String) -> String {
        LauncherPromptCommandExport.launcherURL(
            for: promptCommand,
            query: query,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
    }

    static func readPromptQuery(tokens: [String]) -> String {
        if tokens == ["-"] {
            if isatty(0) != 0 {
                writeStderr("kwwk: prompt - requires stdin\n")
                Foundation.exit(2)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        return tokens.joined(separator: " ")
    }

    static func runQuicklink(rest: [String]) {
        var quicklinkFile: URL?
        var listJSON = false
        var showId: String?
        var renderId: String?
        var launcherCommandId: String?
        var launcherURLId: String?
        var queryTokens: [String] = []
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-quicklinks":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: quicklink --file needs a path\n")
                    Foundation.exit(2)
                }
                quicklinkFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--show", "--template":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: quicklink \(rest[i]) needs a quicklink id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--render", "--url":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: quicklink \(rest[i]) needs a quicklink id\n")
                    Foundation.exit(2)
                }
                renderId = rest[i + 1]
                i += 2
            case "--launcher-command", "--command", "--replay-command":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: quicklink \(rest[i]) needs a quicklink id\n")
                    Foundation.exit(2)
                }
                launcherCommandId = rest[i + 1]
                i += 2
            case "--launcher-url":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: quicklink --launcher-url needs a quicklink id\n")
                    Foundation.exit(2)
                }
                launcherURLId = rest[i + 1]
                i += 2
            case "-h", "--help":
                printQuicklinkUsage()
                Foundation.exit(0)
            case "--":
                queryTokens += rest.dropFirst(i + 1)
                i = rest.count
            default:
                if renderId != nil || launcherCommandId != nil || launcherURLId != nil {
                    queryTokens.append(rest[i])
                } else if showId == nil && launcherCommandId == nil && launcherURLId == nil {
                    showId = rest[i]
                } else {
                    writeStderr("kwwk: unexpected quicklink argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                i += 1
            }
        }

        let requestedActionCount = [showId, renderId, launcherCommandId, launcherURLId]
            .compactMap { $0 }
            .count
        if requestedActionCount > 1 {
            writeStderr("kwwk: quicklink actions cannot be combined\n")
            Foundation.exit(2)
        }
        if !queryTokens.isEmpty && renderId == nil && launcherCommandId == nil && launcherURLId == nil {
            writeStderr("kwwk: quicklink input requires --render, --launcher-command, or --launcher-url\n")
            Foundation.exit(2)
        }

        let url = quicklinkFile ?? LauncherQuicklinkIndex.defaultURL()
        let quicklinks = LauncherQuicklinkIndex.load(from: url)

        if let launcherCommandId {
            let quicklink = requireQuicklink(launcherCommandId, in: quicklinks, source: url)
            print(quicklinkLauncherCommand(for: quicklink, query: readQuicklinkQuery(tokens: queryTokens)))
            return
        }

        if let launcherURLId {
            let quicklink = requireQuicklink(launcherURLId, in: quicklinks, source: url)
            print(quicklinkLauncherURL(for: quicklink, query: readQuicklinkQuery(tokens: queryTokens)))
            return
        }

        if let renderId {
            let quicklink = requireQuicklink(renderId, in: quicklinks, source: url)
            print(quicklink.renderedURLString(query: readQuicklinkQuery(tokens: queryTokens)))
            return
        }

        if let showId {
            let quicklink = requireQuicklink(showId, in: quicklinks, source: url)
            if listJSON {
                do {
                    print(try LauncherQuicklinkExport.json(for: quicklink))
                } catch {
                    writeStderr("kwwk: failed to encode quicklink: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                print(quicklink.urlTemplate)
            }
            return
        }

        printQuicklinkList(quicklinks, asJSON: listJSON)
    }

    static func printQuicklinkUsage() {
        print("""
        kwwk quicklink — inspect shared launcher quicklinks

        usage:
          kwwk quicklink                         list ~/.kwwk/launcher/quicklinks.json
          kwwk quicklink --json                  list quicklinks as automation JSON
          kwwk quicklink --show <id>             print one URL template
          kwwk quicklink --show <id> --json      print one quicklink as JSON
          kwwk quicklink --render <id> [input]   render one quicklink URL
          kwwk quicklink --render <id> -         read render input from stdin
          kwwk quicklink --launcher-command <id> print a launcher replay command
          kwwk quicklink --launcher-url <id>     print a native launcher URL
          kwwk quicklink --file <path> --json    read another quicklinks file

        Rendered quicklinks percent-encode input for {query} and {argument}.
        Typing the quicklink title or keyword first strips that trigger from the
        rendered input, matching the launcher palette.
        """)
    }

    static func printQuicklinkList(_ quicklinks: [LauncherQuicklink], asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherQuicklinkExport.json(for: quicklinks))
            } catch {
                writeStderr("kwwk: failed to encode quicklinks: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\ttitle\tsubtitle\turlTemplate\tlauncherCommand")
            let table = LauncherQuicklinkExport.table(for: quicklinks)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func requireQuicklink(
        _ id: String,
        in quicklinks: [LauncherQuicklink],
        source: URL
    ) -> LauncherQuicklink {
        if let quicklink = quicklink(matching: id, in: quicklinks) {
            return quicklink
        }
        writeStderr("kwwk: no quicklink matched '\(id)' in \(source.path)\n")
        Foundation.exit(2)
    }

    static func quicklink(
        matching id: String,
        in quicklinks: [LauncherQuicklink]
    ) -> LauncherQuicklink? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("quicklink:")
            ? String(trimmed.dropFirst("quicklink:".count))
            : trimmed

        return quicklinks.first { quicklink in
            quicklink.id == normalized
                || quicklink.id.hasPrefix(normalized)
                || quicklink.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    static func quicklinkLauncherCommand(for quicklink: LauncherQuicklink, query: String) -> String {
        let argument = quicklink.argument(from: query)
        let queryArgument = argument.isEmpty ? "<query>" : argument
        return [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote("quicklink:\(quicklink.id)"),
            "--run",
            "--",
            KWWKShellCommand.quote(queryArgument),
        ].joined(separator: " ")
    }

    static func quicklinkLauncherURL(for quicklink: LauncherQuicklink, query: String) -> String {
        LauncherQuicklinkExport.launcherURL(
            for: quicklink,
            query: query,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
    }

    static func readQuicklinkQuery(tokens: [String]) -> String {
        if tokens == ["-"] {
            if isatty(0) != 0 {
                writeStderr("kwwk: quicklink - requires stdin\n")
                Foundation.exit(2)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        return tokens.joined(separator: " ")
    }

    static func runAlias(rest: [String]) {
        var aliasFile: URL?
        var listJSON = false
        var showId: String?
        var targetId: String?
        var launcherCommandId: String?
        var launcherURLId: String?
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-aliases":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: alias --file needs a path\n")
                    Foundation.exit(2)
                }
                aliasFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--show":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: alias --show needs an alias id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--target", "--target-command", "--target-command-id":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: alias \(rest[i]) needs an alias id\n")
                    Foundation.exit(2)
                }
                targetId = rest[i + 1]
                i += 2
            case "--launcher-command", "--command", "--replay-command":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: alias \(rest[i]) needs an alias id\n")
                    Foundation.exit(2)
                }
                launcherCommandId = rest[i + 1]
                i += 2
            case "--launcher-url":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: alias --launcher-url needs an alias id\n")
                    Foundation.exit(2)
                }
                launcherURLId = rest[i + 1]
                i += 2
            case "-h", "--help":
                printAliasUsage()
                Foundation.exit(0)
            default:
                guard showId == nil else {
                    writeStderr("kwwk: unexpected alias argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                showId = rest[i]
                i += 1
            }
        }

        let requestedActionCount = [showId, targetId, launcherCommandId, launcherURLId]
            .compactMap { $0 }
            .count
        if requestedActionCount > 1 {
            writeStderr("kwwk: alias actions cannot be combined\n")
            Foundation.exit(2)
        }

        let url = aliasFile ?? LauncherCommandAliasIndex.defaultURL()
        let aliases = LauncherCommandAliasIndex.load(from: url)

        if let launcherCommandId {
            let alias = requireAlias(launcherCommandId, in: aliases, source: url)
            print(aliasLauncherCommand(for: alias))
            return
        }

        if let launcherURLId {
            let alias = requireAlias(launcherURLId, in: aliases, source: url)
            print(aliasLauncherURL(for: alias))
            return
        }

        if let targetId {
            let alias = requireAlias(targetId, in: aliases, source: url)
            print(alias.targetCommandId)
            return
        }

        if let showId {
            let alias = requireAlias(showId, in: aliases, source: url)
            if listJSON {
                do {
                    print(try LauncherCommandAliasExport.json(for: alias))
                } catch {
                    writeStderr("kwwk: failed to encode alias: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                print(alias.targetCommandId)
            }
            return
        }

        printAliasList(aliases, asJSON: listJSON)
    }

    static func printAliasUsage() {
        print("""
        kwwk alias — inspect shared launcher command aliases

        usage:
          kwwk alias                         list ~/.kwwk/launcher/aliases.json
          kwwk alias --json                  list aliases as automation JSON
          kwwk alias --show <id>             print one alias target command id
          kwwk alias --show <id> --json      print one alias as JSON
          kwwk alias --target <id>           print one alias target command id
          kwwk alias --launcher-command <id> print a launcher replay command
          kwwk alias --launcher-url <id>     print a native launcher URL
          kwwk alias --file <path> --json    read another aliases file

        Aliases point stable shortcut names at existing launcher command IDs.
        Run the printed launcher command to execute the alias through the same
        deep-link bridge as the macOS palette.
        """)
    }

    static func printAliasList(_ aliases: [LauncherCommandAlias], asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherCommandAliasExport.json(for: aliases))
            } catch {
                writeStderr("kwwk: failed to encode aliases: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\ttitle\tsubtitle\ttargetCommandId\tlauncherCommand")
            let table = LauncherCommandAliasExport.table(for: aliases)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func requireAlias(
        _ id: String,
        in aliases: [LauncherCommandAlias],
        source: URL
    ) -> LauncherCommandAlias {
        if let alias = commandAlias(matching: id, in: aliases) {
            return alias
        }
        writeStderr("kwwk: no alias matched '\(id)' in \(source.path)\n")
        Foundation.exit(2)
    }

    static func commandAlias(
        matching id: String,
        in aliases: [LauncherCommandAlias]
    ) -> LauncherCommandAlias? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix(LauncherCommandAliasIndex.commandPrefix)
            ? String(trimmed.dropFirst(LauncherCommandAliasIndex.commandPrefix.count))
            : trimmed

        return aliases.first { alias in
            alias.id == normalized
                || alias.id.hasPrefix(normalized)
                || alias.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    static func aliasLauncherCommand(for alias: LauncherCommandAlias) -> String {
        LauncherCommandAliasExportRecord(alias: alias).launcherCommand
    }

    static func aliasLauncherURL(for alias: LauncherCommandAlias) -> String {
        LauncherCommandAliasExport.launcherURL(
            for: alias,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
    }

    static func runScriptCommand(rest: [String]) {
        var roots: [URL] = []
        var listJSON = false
        var showId: String?
        var pathId: String?
        var launcherCommandId: String?
        var launcherURLId: String?
        var queryTokens: [String] = []
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-scripts":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--dir", "--directory", "--root":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: script \(rest[i]) needs a directory path\n")
                    Foundation.exit(2)
                }
                roots.append(URL(fileURLWithPath: rest[i + 1]).standardizedFileURL)
                i += 2
            case "--show", "--preview":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: script \(rest[i]) needs a script id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--path", "--script-path":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: script \(rest[i]) needs a script id\n")
                    Foundation.exit(2)
                }
                pathId = rest[i + 1]
                i += 2
            case "--launcher-command", "--command", "--replay-command":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: script \(rest[i]) needs a script id\n")
                    Foundation.exit(2)
                }
                launcherCommandId = rest[i + 1]
                i += 2
            case "--launcher-url":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: script --launcher-url needs a script id\n")
                    Foundation.exit(2)
                }
                launcherURLId = rest[i + 1]
                i += 2
            case "-h", "--help":
                printScriptUsage()
                Foundation.exit(0)
            case "--":
                queryTokens += rest.dropFirst(i + 1)
                i = rest.count
            default:
                if launcherCommandId != nil || launcherURLId != nil {
                    queryTokens.append(rest[i])
                } else if showId == nil && pathId == nil {
                    showId = rest[i]
                } else {
                    writeStderr("kwwk: unexpected script argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                i += 1
            }
        }

        let requestedActionCount = [showId, pathId, launcherCommandId, launcherURLId]
            .compactMap { $0 }
            .count
        if requestedActionCount > 1 {
            writeStderr("kwwk: script actions cannot be combined\n")
            Foundation.exit(2)
        }
        if !queryTokens.isEmpty && launcherCommandId == nil && launcherURLId == nil {
            writeStderr("kwwk: script input requires --launcher-command or --launcher-url\n")
            Foundation.exit(2)
        }

        let sourceRoots = roots.isEmpty ? LauncherScriptCommandIndex.defaultRoots() : roots
        let scripts = LauncherScriptCommandIndex.scan(roots: sourceRoots)
        let sourceDescription = sourceRoots.map(\.path).joined(separator: ", ")

        if let launcherCommandId {
            let script = requireScript(launcherCommandId, in: scripts, source: sourceDescription)
            print(LauncherScriptCommandExport.launcherCommand(for: script, query: readScriptQuery(tokens: queryTokens)))
            return
        }

        if let launcherURLId {
            let script = requireScript(launcherURLId, in: scripts, source: sourceDescription)
            print(scriptLauncherURL(for: script, query: readScriptQuery(tokens: queryTokens)))
            return
        }

        if let pathId {
            let script = requireScript(pathId, in: scripts, source: sourceDescription)
            print(script.scriptPath)
            return
        }

        if let showId {
            let script = requireScript(showId, in: scripts, source: sourceDescription)
            if listJSON {
                do {
                    print(try LauncherScriptCommandExport.json(for: script))
                } catch {
                    writeStderr("kwwk: failed to encode script command: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                print(script.previewText)
            }
            return
        }

        printScriptList(scripts, asJSON: listJSON)
    }

    static func printScriptUsage() {
        print("""
        kwwk script — inspect launcher script commands

        usage:
          kwwk script                         list ~/.kwwk/launcher/commands
          kwwk script --json                  list scripts as automation JSON
          kwwk script --show <id>             print one script preview
          kwwk script --show <id> --json      print one script as JSON
          kwwk script --path <id>             print one script executable path
          kwwk script --launcher-command <id> print a launcher replay command
          kwwk script --launcher-command <id> [input]
                                             print a replay command with input
          kwwk script --launcher-url <id>     print a native launcher URL
          kwwk script --launcher-url <id> [input]
                                             print a native URL with input
          kwwk script --dir <path> --json     scan another script directory

        Script commands are executable files with optional @kwwk or Raycast
        metadata. Input is only included in launcher replay commands for scripts
        with argument or stdin mode, unless explicit input is supplied here.
        """)
    }

    static func printScriptList(_ scripts: [LauncherScriptCommand], asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherScriptCommandExport.json(for: scripts))
            } catch {
                writeStderr("kwwk: failed to encode script commands: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\ttitle\tsubtitle\targumentMode\tscriptPath\tlauncherCommand")
            let table = LauncherScriptCommandExport.table(for: scripts)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func requireScript(
        _ id: String,
        in scripts: [LauncherScriptCommand],
        source: String
    ) -> LauncherScriptCommand {
        if let script = script(matching: id, in: scripts) {
            return script
        }
        writeStderr("kwwk: no script command matched '\(id)' in \(source)\n")
        Foundation.exit(2)
    }

    static func script(
        matching id: String,
        in scripts: [LauncherScriptCommand]
    ) -> LauncherScriptCommand? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("script:")
            ? String(trimmed.dropFirst("script:".count))
            : trimmed

        return scripts.first { script in
            script.id == normalized
                || script.id.hasPrefix(normalized)
                || script.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                || script.scriptPath == trimmed
        }
    }

    static func readScriptQuery(tokens: [String]) -> String {
        if tokens == ["-"] {
            if isatty(0) != 0 {
                writeStderr("kwwk: script - requires stdin\n")
                Foundation.exit(2)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        return tokens.joined(separator: " ")
    }

    static func scriptLauncherURL(for script: LauncherScriptCommand, query: String) -> String {
        LauncherScriptCommandExport.launcherURL(
            for: script,
            query: query,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
    }

    static func runSnippet(rest: [String]) {
        var snippetFile: URL?
        var listJSON = false
        var showId: String?
        var renderId: String?
        var launcherCommandId: String?
        var launcherURLId: String?
        var clipboard = ""
        var workingDirectory: String? = FileManager.default.currentDirectoryPath
        var finderSelectionPaths: [String] = []
        var frontmostApplicationName: String?
        var queryTokens: [String] = []
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-snippets":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet --file needs a path\n")
                    Foundation.exit(2)
                }
                snippetFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--show", "--template":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet \(rest[i]) needs a snippet id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--render":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet --render needs a snippet id\n")
                    Foundation.exit(2)
                }
                renderId = rest[i + 1]
                i += 2
            case "--launcher-command", "--command", "--replay-command":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet \(rest[i]) needs a snippet id\n")
                    Foundation.exit(2)
                }
                launcherCommandId = rest[i + 1]
                i += 2
            case "--launcher-url":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet --launcher-url needs a snippet id\n")
                    Foundation.exit(2)
                }
                launcherURLId = rest[i + 1]
                i += 2
            case "--clipboard":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet --clipboard needs text\n")
                    Foundation.exit(2)
                }
                clipboard = rest[i + 1]
                i += 2
            case "--workspace", "--cwd":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                workingDirectory = rest[i + 1]
                i += 2
            case "--finder-selection":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet --finder-selection needs a path\n")
                    Foundation.exit(2)
                }
                finderSelectionPaths.append(rest[i + 1])
                i += 2
            case "--frontmost-app":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: snippet --frontmost-app needs an app name\n")
                    Foundation.exit(2)
                }
                frontmostApplicationName = rest[i + 1]
                i += 2
            case "-h", "--help":
                printSnippetUsage()
                Foundation.exit(0)
            case "--":
                queryTokens += rest.dropFirst(i + 1)
                i = rest.count
            default:
                if renderId != nil || launcherCommandId != nil || launcherURLId != nil {
                    queryTokens.append(rest[i])
                } else if showId == nil && launcherCommandId == nil && launcherURLId == nil {
                    showId = rest[i]
                } else {
                    writeStderr("kwwk: unexpected snippet argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                i += 1
            }
        }

        let requestedActionCount = [showId, renderId, launcherCommandId, launcherURLId]
            .compactMap { $0 }
            .count
        if requestedActionCount > 1 {
            writeStderr("kwwk: snippet actions cannot be combined\n")
            Foundation.exit(2)
        }
        if !queryTokens.isEmpty && renderId == nil && launcherCommandId == nil && launcherURLId == nil {
            writeStderr("kwwk: snippet input requires --render, --launcher-command, or --launcher-url\n")
            Foundation.exit(2)
        }

        let url = snippetFile ?? LauncherSnippetIndex.defaultURL()
        let snippets = LauncherSnippetIndex.load(from: url)

        if let launcherCommandId {
            let snippet = requireSnippet(launcherCommandId, in: snippets, source: url)
            print(snippetLauncherCommand(for: snippet, query: readSnippetQuery(tokens: queryTokens)))
            return
        }

        if let launcherURLId {
            let snippet = requireSnippet(launcherURLId, in: snippets, source: url)
            print(snippetLauncherURL(for: snippet, query: readSnippetQuery(tokens: queryTokens)))
            return
        }

        if let renderId {
            let snippet = requireSnippet(renderId, in: snippets, source: url)
            let context = LauncherContextSnapshot(
                workingDirectory: workingDirectory,
                finderSelectionPaths: finderSelectionPaths,
                frontmostApplicationName: frontmostApplicationName
            )
            let rendered = snippet.renderedText(
                query: readSnippetQuery(tokens: queryTokens),
                clipboard: clipboard,
                context: context
            )
            writeStdout(rendered)
            if !rendered.hasSuffix("\n") {
                writeStdout("\n")
            }
            return
        }

        if let showId {
            let snippet = requireSnippet(showId, in: snippets, source: url)
            if listJSON {
                do {
                    print(try LauncherSnippetExport.json(for: snippet))
                } catch {
                    writeStderr("kwwk: failed to encode snippet: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                writeStdout(snippet.textTemplate)
                if !snippet.textTemplate.hasSuffix("\n") {
                    writeStdout("\n")
                }
            }
            return
        }

        printSnippetList(snippets, asJSON: listJSON)
    }

    static func printSnippetUsage() {
        print("""
        kwwk snippet — inspect shared launcher snippets

        usage:
          kwwk snippet                         list ~/.kwwk/launcher/snippets.json
          kwwk snippet --json                  list snippets as automation JSON
          kwwk snippet --show <id>             print one snippet template
          kwwk snippet --show <id> --json      print one snippet as JSON
          kwwk snippet --render <id> [input]   render one snippet with input
          kwwk snippet --render <id> -         read render input from stdin
          kwwk snippet --launcher-command <id> print a launcher replay command
          kwwk snippet --launcher-url <id>     print a native launcher URL
          kwwk snippet --file <path> --json    read another snippets file

        Rendered snippets support {query}, {clipboard}, {workspace}, {cwd},
        {finderSelection}, and {frontmostApp}. Use --clipboard, --workspace,
        --finder-selection, and --frontmost-app to provide deterministic
        terminal context for scripts.
        """)
    }

    static func printSnippetList(_ snippets: [LauncherSnippet], asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherSnippetExport.json(for: snippets))
            } catch {
                writeStderr("kwwk: failed to encode snippets: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\ttitle\tsubtitle\ttextTemplate\tlauncherCommand")
            let table = LauncherSnippetExport.table(for: snippets)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func requireSnippet(
        _ id: String,
        in snippets: [LauncherSnippet],
        source: URL
    ) -> LauncherSnippet {
        if let snippet = snippet(matching: id, in: snippets) {
            return snippet
        }
        writeStderr("kwwk: no snippet matched '\(id)' in \(source.path)\n")
        Foundation.exit(2)
    }

    static func snippet(
        matching id: String,
        in snippets: [LauncherSnippet]
    ) -> LauncherSnippet? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasPrefix("snippet:")
            ? String(trimmed.dropFirst("snippet:".count))
            : trimmed

        return snippets.first { snippet in
            snippet.id == normalized
                || snippet.id.hasPrefix(normalized)
                || snippet.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    static func snippetLauncherCommand(for snippet: LauncherSnippet, query: String) -> String {
        let argument = snippet.argument(from: query)
        let queryArgument = argument.isEmpty ? "<query>" : argument
        return [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote("snippet:\(snippet.id)"),
            "--run",
            "--",
            KWWKShellCommand.quote(queryArgument),
        ].joined(separator: " ")
    }

    static func snippetLauncherURL(for snippet: LauncherSnippet, query: String) -> String {
        LauncherSnippetExport.launcherURL(
            for: snippet,
            query: query,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
    }

    static func readSnippetQuery(tokens: [String]) -> String {
        if tokens == ["-"] {
            if isatty(0) != 0 {
                writeStderr("kwwk: snippet - requires stdin\n")
                Foundation.exit(2)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        return tokens.joined(separator: " ")
    }

    static func runClipboard(rest: [String]) {
        var clipboardFile: URL?
        var listJSON = false
        var showId: String?
        var saveSnippetId: String?
        var snippetFile: URL?
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-items":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: clipboard --file needs a path\n")
                    Foundation.exit(2)
                }
                clipboardFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--show", "--output":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: clipboard \(rest[i]) needs an item id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--save-snippet":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: clipboard \(rest[i]) needs an item id\n")
                    Foundation.exit(2)
                }
                saveSnippetId = rest[i + 1]
                i += 2
            case "--snippet-file", "--snippets-file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: clipboard \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                snippetFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "-h", "--help":
                printClipboardUsage()
                Foundation.exit(0)
            default:
                guard showId == nil else {
                    writeStderr("kwwk: unexpected clipboard argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                showId = rest[i]
                i += 1
            }
        }

        let requestedActionCount = [showId, saveSnippetId]
            .compactMap { $0 }
            .count
        if requestedActionCount > 1 {
            writeStderr("kwwk: clipboard actions cannot be combined\n")
            Foundation.exit(2)
        }

        let url = clipboardFile ?? LauncherClipboardHistoryStore.defaultURL()
        let history = LauncherClipboardHistoryStore.load(from: url)

        if let saveSnippetId {
            let record = requireClipboardRecord(saveSnippetId, in: history, source: url)
            saveClipboardSnippet(record, to: snippetFile ?? LauncherSnippetIndex.defaultURL(), asJSON: listJSON)
            return
        }

        if let showId {
            let record = requireClipboardRecord(showId, in: history, source: url)
            if listJSON {
                do {
                    print(try LauncherClipboardHistoryExport.json(for: LauncherClipboardHistory(records: [record])))
                } catch {
                    writeStderr("kwwk: failed to encode clipboard history: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                writeStdout(record.text)
                if !record.text.hasSuffix("\n") {
                    writeStdout("\n")
                }
            }
            return
        }

        printClipboardList(history, asJSON: listJSON)
    }

    static func printClipboardUsage() {
        print("""
        kwwk clipboard — inspect shared launcher clipboard history

        usage:
          kwwk clipboard                         list ~/.kwwk/launcher/clipboard-history.json
          kwwk clipboard --json                  list clipboard history as automation JSON
          kwwk clipboard --show <id>             print one clipboard item
          kwwk clipboard --show <id> --json      print one clipboard item as JSON
          kwwk clipboard --save-snippet <id>     save clipboard item as snippet
          kwwk clipboard --file <path> --json    read another clipboard history file
          kwwk clipboard --snippet-file <path>   write snippets to another JSON file

        The resident launcher writes clipboard text here when clipboard tracking
        is enabled or when Capture Current Clipboard is run. Use
        `latest-clipboard` as the id for the newest saved clipboard item.
        """)
    }

    static func printClipboardList(_ history: LauncherClipboardHistory, asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherClipboardHistoryExport.json(for: history))
            } catch {
                writeStderr("kwwk: failed to encode clipboard history: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\tcopiedAt\ttitle\tpreview\tlauncherCommand")
            let table = LauncherClipboardHistoryExport.table(for: history)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func saveClipboardSnippet(_ record: LauncherClipboardHistoryRecord, to url: URL, asJSON: Bool) {
        let snippet = LauncherSnippetIndex.snippet(from: record)
        do {
            try LauncherSnippetIndex.upsert(snippet, to: url)
            printSavedArtifact(
                LauncherSavedArtifactExportRecord(snippet: snippet, path: url),
                asJSON: asJSON
            )
        } catch {
            writeStderr("kwwk: failed to save snippet for clipboard item '\(record.id)': \(error)\n")
            Foundation.exit(1)
        }
    }

    static func requireClipboardRecord(
        _ id: String,
        in history: LauncherClipboardHistory,
        source: URL
    ) -> LauncherClipboardHistoryRecord {
        if let record = clipboardRecord(matching: id, in: history) {
            return record
        }
        writeStderr("kwwk: no clipboard history item matched '\(id)' in \(source.path)\n")
        Foundation.exit(2)
    }

    static func clipboardRecord(
        matching id: String,
        in history: LauncherClipboardHistory
    ) -> LauncherClipboardHistoryRecord? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == LauncherClipboardHistoryCommandFactory.latestCommandId {
            return history.records.first
        }

        let normalized = trimmed.hasPrefix(LauncherClipboardHistoryCommandFactory.commandPrefix)
            ? String(trimmed.dropFirst(LauncherClipboardHistoryCommandFactory.commandPrefix.count))
            : trimmed

        return history.records.first { record in
            record.id == normalized
                || record.id.hasPrefix(normalized)
                || record.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    static func runContext(rest: [String]) {
        var contextDirectory: URL?
        var listJSON = false
        var showId: String?
        var askCommandId: String?
        var savePromptId: String?
        var saveSnippetId: String?
        var saveWorkflowId: String?
        var promptFile: URL?
        var snippetFile: URL?
        var workflowFile: URL?
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-contexts":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--dir", "--directory":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a directory path\n")
                    Foundation.exit(2)
                }
                contextDirectory = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--show", "--output":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a context id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--ask-command", "--launcher-command", "--replay-command":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a context id\n")
                    Foundation.exit(2)
                }
                askCommandId = rest[i + 1]
                i += 2
            case "--save-prompt", "--save-prompt-command":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a context id\n")
                    Foundation.exit(2)
                }
                savePromptId = rest[i + 1]
                i += 2
            case "--save-snippet":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a context id\n")
                    Foundation.exit(2)
                }
                saveSnippetId = rest[i + 1]
                i += 2
            case "--save-workflow":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a context id\n")
                    Foundation.exit(2)
                }
                saveWorkflowId = rest[i + 1]
                i += 2
            case "--prompt-file", "--prompts-file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                promptFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--snippet-file", "--snippets-file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                snippetFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--workflow-file", "--workflows-file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: context \(rest[i]) needs a path\n")
                    Foundation.exit(2)
                }
                workflowFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "-h", "--help":
                printContextUsage()
                Foundation.exit(0)
            default:
                guard showId == nil else {
                    writeStderr("kwwk: unexpected context argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                showId = rest[i]
                i += 1
            }
        }

        let requestedActionCount = [showId, askCommandId, savePromptId, saveSnippetId, saveWorkflowId]
            .compactMap { $0 }
            .count
        if requestedActionCount > 1 {
            writeStderr("kwwk: context actions cannot be combined\n")
            Foundation.exit(2)
        }

        let directory = contextDirectory ?? LauncherCLIContextStore.defaultDirectory()
        let records = LauncherCLIContextIndex.scan(directory: directory)

        if let askCommandId {
            let record = requireContextRecord(askCommandId, in: records, source: directory)
            print(contextAskCommand(for: record, requestedId: askCommandId))
            return
        }

        if let savePromptId {
            let record = requireContextRecord(savePromptId, in: records, source: directory)
            saveContextPromptCommand(record, to: promptFile ?? LauncherPromptCommandIndex.defaultURL(), asJSON: listJSON)
            return
        }

        if let saveSnippetId {
            let record = requireContextRecord(saveSnippetId, in: records, source: directory)
            saveContextSnippet(record, to: snippetFile ?? LauncherSnippetIndex.defaultURL(), asJSON: listJSON)
            return
        }

        if let saveWorkflowId {
            let record = requireContextRecord(saveWorkflowId, in: records, source: directory)
            saveContextWorkflow(record, to: workflowFile ?? LauncherWorkflowIndex.defaultURL(), asJSON: listJSON)
            return
        }

        if let showId {
            let record = requireContextRecord(showId, in: records, source: directory)
            if listJSON {
                do {
                    print(try LauncherCLIContextExport.json(for: [record]))
                } catch {
                    writeStderr("kwwk: failed to encode terminal context: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                printContextText(record)
            }
            return
        }

        printContextList(records, asJSON: listJSON)
    }

    static func printContextUsage() {
        print("""
        kwwk context — inspect saved terminal contexts

        usage:
          kwwk context                         list ~/.kwwk/launcher/context/*.txt
          kwwk context --json                  list contexts as automation JSON
          kwwk context --show <id>             print one captured context
          kwwk context --show <id> --json      print one context as JSON
          kwwk context --ask-command <id>      print a launcher ask command
          kwwk context --save-prompt <id>      save a context prompt command
          kwwk context --save-snippet <id>     save captured output as a snippet
          kwwk context --save-workflow <id>    save a one-step context workflow
          kwwk context --dir <path> --json     read another context directory
          kwwk context --prompt-file <path>    write prompts to another JSON file
          kwwk context --snippet-file <path>   write snippets to another JSON file
          kwwk context --workflow-file <path>  write workflows to another JSON file

        `kwwk launcher --capture-stdin` writes captured terminal output here so
        scripts can seed launcher AI context now and inspect or replay it later.
        Use `latest-cli-context` as the id for the newest capture.
        """)
    }

    static func printContextList(_ records: [LauncherCLIContextRecord], asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherCLIContextExport.json(for: records))
            } catch {
                writeStderr("kwwk: failed to encode terminal contexts: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\ttitle\tbytes\tpath\tlauncherCommand")
            let table = LauncherCLIContextExport.table(for: records)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func printContextText(_ record: LauncherCLIContextRecord) {
        do {
            let text = try String(contentsOf: URL(fileURLWithPath: record.path), encoding: .utf8)
            writeStdout(text)
            if !text.hasSuffix("\n") {
                writeStdout("\n")
            }
        } catch {
            writeStderr("kwwk: failed to read terminal context '\(record.id)': \(error)\n")
            Foundation.exit(1)
        }
    }

    static func saveContextPromptCommand(_ record: LauncherCLIContextRecord, to url: URL, asJSON: Bool) {
        let promptCommand = LauncherPromptCommandIndex.promptCommand(from: record)
        do {
            try LauncherPromptCommandIndex.upsert(promptCommand, to: url)
            printSavedArtifact(
                LauncherSavedArtifactExportRecord(promptCommand: promptCommand, path: url),
                asJSON: asJSON
            )
        } catch {
            writeStderr("kwwk: failed to save prompt command for terminal context '\(record.id)': \(error)\n")
            Foundation.exit(1)
        }
    }

    static func saveContextSnippet(_ record: LauncherCLIContextRecord, to url: URL, asJSON: Bool) {
        guard let snippet = LauncherSnippetIndex.snippet(from: record) else {
            writeStderr("kwwk: failed to read terminal context '\(record.id)' as a snippet\n")
            Foundation.exit(1)
        }
        do {
            try LauncherSnippetIndex.upsert(snippet, to: url)
            printSavedArtifact(
                LauncherSavedArtifactExportRecord(snippet: snippet, path: url),
                asJSON: asJSON
            )
        } catch {
            writeStderr("kwwk: failed to save snippet for terminal context '\(record.id)': \(error)\n")
            Foundation.exit(1)
        }
    }

    static func saveContextWorkflow(_ record: LauncherCLIContextRecord, to url: URL, asJSON: Bool) {
        let workflow = LauncherWorkflowIndex.workflow(from: record)
        do {
            try LauncherWorkflowIndex.upsert(workflow, to: url)
            printSavedArtifact(
                LauncherSavedArtifactExportRecord(workflow: workflow, path: url),
                asJSON: asJSON
            )
        } catch {
            writeStderr("kwwk: failed to save workflow for terminal context '\(record.id)': \(error)\n")
            Foundation.exit(1)
        }
    }

    static func printSavedArtifact(_ record: LauncherSavedArtifactExportRecord, asJSON: Bool) {
        do {
            print(asJSON
                ? try LauncherSavedArtifactExport.json(for: record)
                : LauncherSavedArtifactExport.table(for: record)
            )
        } catch {
            writeStderr("kwwk: failed to encode saved launcher artifact: \(error)\n")
            Foundation.exit(1)
        }
    }

    static func contextAskCommand(for record: LauncherCLIContextRecord, requestedId: String) -> String {
        let trimmed = requestedId.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandId = trimmed == LauncherCLIContextIndex.latestCommandId
            ? LauncherCLIContextIndex.latestCommandId
            : LauncherCLIContextExportRecord(record: record).commandId
        return [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(commandId),
            "--run",
        ].joined(separator: " ")
    }

    static func requireContextRecord(
        _ id: String,
        in records: [LauncherCLIContextRecord],
        source: URL
    ) -> LauncherCLIContextRecord {
        if let record = contextRecord(matching: id, in: records) {
            return record
        }
        writeStderr("kwwk: no terminal context matched '\(id)' in \(source.path)\n")
        Foundation.exit(2)
    }

    static func contextRecord(
        matching id: String,
        in records: [LauncherCLIContextRecord]
    ) -> LauncherCLIContextRecord? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == LauncherCLIContextIndex.latestCommandId {
            return records.first
        }

        let withoutCommandPrefix = trimmed.hasPrefix(LauncherCLIContextIndex.commandPrefix)
            ? String(trimmed.dropFirst(LauncherCLIContextIndex.commandPrefix.count))
            : trimmed
        let normalized = LauncherCLIContextStore.filenameStem(from: withoutCommandPrefix) ?? withoutCommandPrefix

        return records.first { record in
            record.id == withoutCommandPrefix
                || record.id == normalized
                || record.id.hasPrefix(withoutCommandPrefix)
                || record.id.hasPrefix(normalized)
                || record.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    static func runProfile(rest: [String]) {
        var profileFile: URL?
        var listJSON = false
        var showId: String?
        var flagsId: String?
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-profiles":
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: profile --file needs a path\n")
                    Foundation.exit(2)
                }
                profileFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "--show":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: profile --show needs a profile id\n")
                    Foundation.exit(2)
                }
                showId = rest[i + 1]
                i += 2
            case "--flags":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: profile --flags needs a profile id\n")
                    Foundation.exit(2)
                }
                flagsId = rest[i + 1]
                i += 2
            case "-h", "--help":
                printProfileUsage()
                Foundation.exit(0)
            default:
                guard showId == nil else {
                    writeStderr("kwwk: unexpected profile argument '\(rest[i])'\n")
                    Foundation.exit(2)
                }
                showId = rest[i]
                i += 1
            }
        }

        let source = profileFile ?? LauncherAIProfileIndex.defaultURL()
        let profiles = LauncherAIProfileCatalog.availableProfiles(
            customProfiles: LauncherAIProfileIndex.load(from: source)
        )

        if let flagsId {
            print(requireProfile(flagsId, in: profiles, source: source).cliFlags)
            return
        }

        if let showId {
            let profile = requireProfile(showId, in: profiles, source: source)
            if listJSON {
                do {
                    print(try LauncherAIProfileExport.json(for: [profile]))
                } catch {
                    writeStderr("kwwk: failed to encode AI profiles: \(error)\n")
                    Foundation.exit(1)
                }
            } else {
                printProfile(profile)
            }
            return
        }

        printProfileList(profiles, asJSON: listJSON)
    }

    static func printProfileUsage() {
        print("""
        kwwk profile — inspect shared launcher AI runtime profiles

        usage:
          kwwk profile                         list default and custom profiles
          kwwk profile --json                  list profiles as automation JSON
          kwwk profile --show <id>             print one profile
          kwwk profile --show <id> --json      print one profile as JSON
          kwwk profile --flags <id>            print CLI flags for a profile
          kwwk profile --file <path> --json    read another profiles file

        Use `kwwk --profile <id> -p ...`, `kwwk --profile <id>`, or
        `kwwk --profile <id> workflow ...` to run with a saved launcher profile.
        Explicit --thinking, --model, and --context-1m flags override or extend
        the profile.
        """)
    }

    static func printProfileList(_ profiles: [LauncherAIProfile], asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherAIProfileExport.json(for: profiles))
            } catch {
                writeStderr("kwwk: failed to encode AI profiles: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\ttitle\tmodel\tthinking\tcontext1m\tflags")
            let table = LauncherAIProfileExport.table(for: profiles)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func printProfile(_ profile: LauncherAIProfile) {
        print("""
        id: \(profile.id)
        title: \(profile.title)
        model: \(profile.modelDisplayName)
        thinking: \(profile.thinking.rawValue)
        context1m: \(profile.context1m ? "true" : "false")
        flags: \(profile.cliFlags)
        headless: kwwk --profile \(KWWKShellCommand.quote(profile.id)) -p '<prompt>'
        """)
    }

    static func requireProfile(
        _ id: String,
        in profiles: [LauncherAIProfile],
        source: URL
    ) -> LauncherAIProfile {
        let normalized = id.hasPrefix(LauncherAIProfileCatalog.commandPrefix)
            ? String(id.dropFirst(LauncherAIProfileCatalog.commandPrefix.count))
            : id
        if let profile = profiles.first(where: { $0.id == normalized }) {
            return profile
        }
        writeStderr("kwwk: no AI profile matched '\(id)' in \(source.path)\n")
        Foundation.exit(2)
    }

    static func runLauncher(rest: [String]) {
        var mode: LauncherDeepLinkMode = .search
        var runImmediately = false
        var printURL = false
        var listCommands = false
        var listActions = false
        var listFeaturedActions = false
        var inspectCommand = false
        var listJSON = false
        var includeApps = false
        var includeWorkspaceFiles = false
        var captureStdinContext = false
        var captureStdinOnly = false
        var stdinContextName: String?
        var commandId: String?
        var actionId: String?
        var pathContexts: [String] = []
        var queryTokens: [String] = []
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list-commands", "--commands":
                listCommands = true
                i += 1
            case "--list-actions", "--actions":
                listActions = true
                i += 1
            case "--featured-actions", "--featured":
                listActions = true
                listFeaturedActions = true
                i += 1
            case "--inspect-command", "--inspect", "--preview-command", "--preview":
                inspectCommand = true
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--include-apps":
                includeApps = true
                i += 1
            case "--include-workspace-files", "--include-files":
                includeWorkspaceFiles = true
                i += 1
            case "--ask":
                mode = .ask
                runImmediately = true
                i += 1
            case "--ask-stdin", "--ask-context", "--stdin-context":
                mode = .ask
                runImmediately = true
                captureStdinContext = true
                i += 1
            case "--capture-stdin", "--save-stdin-context", "--save-stdin":
                captureStdinContext = true
                captureStdinOnly = true
                i += 1
            case "--stdin-name", "--context-name":
                guard i + 1 < rest.count else {
                    FileHandle.standardError.write(Data("kwwk: \(rest[i]) needs a context name\n".utf8))
                    Foundation.exit(2)
                }
                stdinContextName = rest[i + 1]
                i += 2
            case "--show":
                mode = .search
                i += 1
            case "--hide":
                mode = .hide
                runImmediately = false
                i += 1
            case "--toggle":
                mode = .toggle
                runImmediately = false
                i += 1
            case "--ask-path", "--ask-file":
                guard i + 1 < rest.count else {
                    FileHandle.standardError.write(Data("kwwk: \(rest[i]) needs a file or folder path\n".utf8))
                    Foundation.exit(2)
                }
                mode = .ask
                runImmediately = true
                pathContexts.append(rest[i + 1])
                i += 2
            case "--run":
                runImmediately = true
                i += 1
            case "--no-run":
                runImmediately = false
                i += 1
            case "--command", "--command-id":
                guard i + 1 < rest.count else {
                    FileHandle.standardError.write(Data("kwwk: \(rest[i]) needs a command id\n".utf8))
                    Foundation.exit(2)
                }
                commandId = rest[i + 1]
                i += 2
            case "--action", "--action-id":
                guard i + 1 < rest.count else {
                    FileHandle.standardError.write(Data("kwwk: \(rest[i]) needs an action id\n".utf8))
                    Foundation.exit(2)
                }
                actionId = rest[i + 1]
                i += 2
            case "--print-url":
                printURL = true
                i += 1
            case "-h", "--help":
                printLauncherUsage()
                Foundation.exit(0)
            case "--":
                queryTokens += rest.dropFirst(i + 1)
                i = rest.count
            default:
                queryTokens.append(rest[i])
                i += 1
            }
        }

        if stdinContextName != nil && !captureStdinContext {
            FileHandle.standardError.write(Data("kwwk: --stdin-name requires --ask-stdin or --capture-stdin\n".utf8))
            Foundation.exit(2)
        }
        if captureStdinOnly && !queryTokens.isEmpty {
            FileHandle.standardError.write(Data("kwwk: --capture-stdin does not take a prompt; use --stdin-name <name> to label the saved context\n".utf8))
            Foundation.exit(2)
        }
        if captureStdinContext && queryTokens == ["-"] {
            let flag = captureStdinOnly ? "--capture-stdin" : "--ask-stdin"
            FileHandle.standardError.write(Data("kwwk: \(flag) uses stdin as context; do not pass - as the prompt\n".utf8))
            Foundation.exit(2)
        }

        let query = readLauncherQuery(tokens: queryTokens)
        var capturedContextRecord: LauncherCLIContextRecord?
        if captureStdinContext {
            guard isatty(0) == 0 else {
                let flag = captureStdinOnly ? "--capture-stdin" : "--ask-stdin"
                FileHandle.standardError.write(Data("kwwk: \(flag) requires piped stdin\n".utf8))
                Foundation.exit(2)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let stdinText = String(data: data, encoding: .utf8) ?? ""
            do {
                let url = try LauncherCLIContextStore.saveStdinContext(
                    stdinText,
                    name: stdinContextName
                )
                guard let record = LauncherCLIContextIndex.record(for: url) else {
                    FileHandle.standardError.write(Data("kwwk: failed to index saved stdin context at \(url.path)\n".utf8))
                    Foundation.exit(1)
                }
                capturedContextRecord = record
                pathContexts.append(url.path)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                FileHandle.standardError.write(Data("kwwk: \(msg)\n".utf8))
                Foundation.exit(2)
            }
        }
        if captureStdinOnly {
            guard let capturedContextRecord else {
                FileHandle.standardError.write(Data("kwwk: failed to capture stdin context\n".utf8))
                Foundation.exit(1)
            }
            printCapturedCLIContext(capturedContextRecord, asJSON: listJSON)
            return
        }

        if listCommands {
            printLauncherCommands(
                query: query,
                includeApps: includeApps,
                includeWorkspaceFiles: includeWorkspaceFiles,
                asJSON: listJSON
            )
            return
        }
        if inspectCommand {
            printLauncherCommandDetail(
                query: query,
                commandId: commandId,
                includeApps: includeApps,
                includeWorkspaceFiles: includeWorkspaceFiles,
                asJSON: listJSON
            )
            return
        }
        if listActions {
            printLauncherActions(
                query: query,
                commandId: commandId,
                actionId: actionId,
                includeApps: includeApps,
                includeWorkspaceFiles: includeWorkspaceFiles,
                featuredOnly: listFeaturedActions,
                asJSON: listJSON
            )
            return
        }

        let request = LauncherDeepLinkRequest(
            mode: mode,
            query: query,
            commandId: commandId,
            actionId: actionId,
            pathContexts: pathContexts,
            runImmediately: runImmediately,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let url = request.url

        if printURL {
            print(url.absoluteString)
            return
        }

        openLauncher(url)
    }

    static func printLauncherUsage() {
        print("""
        kwwk launcher — macOS launcher bridge

        usage:
          kwwk launcher [query]             open the launcher with a search query
          kwwk launcher --show              show the resident launcher
          kwwk launcher --hide              hide the resident launcher
          kwwk launcher --toggle            show or hide the resident launcher
          kwwk launcher --ask <prompt>      run an AI prompt in the launcher
          kwwk launcher --ask -             read the AI prompt from stdin
          kwwk launcher --ask-stdin <prompt>
                                            save stdin as local context and ask
          kwwk launcher --ask-stdin --stdin-name <name> <prompt>
                                            label the saved stdin context file
          kwwk launcher --capture-stdin --stdin-name <name>
                                            save stdin as searchable context only
          kwwk launcher --ask-path <path> [prompt]
                                            run an AI prompt with file/folder context
                                            repeat --ask-path for multiple paths
          kwwk launcher --run [query]       open and run the selected command
          kwwk launcher --command <id> --run [input]
                                            run a specific launcher command
          kwwk launcher --command <id> --action <id> --run [input]
                                            run a specific secondary action
          kwwk launcher --print-url [query] print the deep link instead of opening
          kwwk launcher --list-commands [query]
                                            list command IDs; add --json for JSON
          kwwk launcher --list-actions [query]
                                            list Raycast-style actions for the top match
          kwwk launcher --featured-actions [query]
                                            list the compact preview-pane actions
          kwwk launcher --inspect-command [query]
                                            print preview and featured actions
          kwwk launcher --command <id> --list-actions [input]
                                            list actions for a specific command
          kwwk launcher --list-commands --include-apps
                                            include installed macOS app commands
          kwwk launcher --list-commands --include-workspace-files [query]
                                            include indexed files from the cwd
        """)
    }

    static func runWorkflow(
        rest: [String],
        thinkingLevel: ThinkingLevel,
        modelOverride: String?,
        context1m: Bool
    ) async {
        var list = false
        var listJSON = false
        var workflowFile: URL?
        var workflowId: String?
        var queryTokens: [String] = []
        var i = 0

        while i < rest.count {
            switch rest[i] {
            case "--list", "--list-workflows":
                list = true
                i += 1
            case "--json":
                listJSON = true
                i += 1
            case "--file":
                guard i + 1 < rest.count else {
                    writeStderr("kwwk: workflow --file needs a path\n")
                    Foundation.exit(2)
                }
                workflowFile = URL(fileURLWithPath: rest[i + 1]).standardizedFileURL
                i += 2
            case "-h", "--help":
                printWorkflowUsage()
                Foundation.exit(0)
            case "--":
                queryTokens += rest.dropFirst(i + 1)
                i = rest.count
            default:
                if workflowId == nil {
                    workflowId = rest[i]
                } else {
                    queryTokens.append(rest[i])
                }
                i += 1
            }
        }

        let workflowURL = workflowFile ?? LauncherWorkflowIndex.defaultURL()
        let workflows = LauncherWorkflowIndex.load(from: workflowURL)

        if list {
            printWorkflowList(workflows, asJSON: listJSON)
            return
        }

        guard let workflowId else {
            writeStderr("kwwk: workflow needs an id\n\n")
            printWorkflowUsage()
            Foundation.exit(2)
        }
        guard let workflow = workflow(matching: workflowId, in: workflows) else {
            writeStderr("kwwk: no workflow matched '\(workflowId)' in \(workflowURL.path)\n")
            Foundation.exit(2)
        }

        let code = await runWorkflow(
            workflow,
            query: readWorkflowQuery(tokens: queryTokens),
            executable: currentExecutablePath(),
            defaultThinking: KWWKThinkingLevel(rawValue: thinkingLevel.rawValue) ?? .medium,
            defaultModel: modelOverride,
            defaultContext1m: context1m
        )
        Foundation.exit(code)
    }

    static func printWorkflowUsage() {
        print("""
        kwwk workflow — run saved launcher workflows from the terminal

        usage:
          kwwk workflow --list              list ~/.kwwk/launcher/workflows.json
          kwwk workflow --list --json       list workflows as automation JSON
          kwwk workflow <id> [input]        run workflow id with optional input
          kwwk workflow <id> -              read workflow input from stdin
          kwwk workflow --file <path> <id>  load workflows from another JSON file

        workflow steps use the same templates as the macOS launcher. Prompt
        steps run through `kwwk -p -`; shell steps run under zsh in the current
        working directory. Step progress is written to stderr so stdout remains
        usable in pipes.
        """)
    }

    static func printWorkflowList(_ workflows: [LauncherWorkflow], asJSON: Bool = false) {
        if asJSON {
            do {
                print(try LauncherWorkflowExport.json(for: workflows))
            } catch {
                writeStderr("kwwk: failed to encode workflows: \(error)\n")
                Foundation.exit(1)
            }
        } else {
            print("id\ttitle\tsteps\truntime")
            let table = LauncherWorkflowExport.table(for: workflows)
            if !table.isEmpty {
                print(table)
            }
        }
    }

    static func workflow(matching id: String, in workflows: [LauncherWorkflow]) -> LauncherWorkflow? {
        let normalized = id.hasPrefix("workflow:")
            ? String(id.dropFirst("workflow:".count))
            : id
        return workflows.first { workflow in
            workflow.id == normalized
        }
    }

    static func readWorkflowQuery(tokens: [String]) -> String {
        if tokens == ["-"] {
            if isatty(0) != 0 {
                writeStderr("kwwk: workflow - requires stdin\n")
                Foundation.exit(2)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        return tokens.joined(separator: " ")
    }

    static func printCapturedCLIContext(_ record: LauncherCLIContextRecord, asJSON: Bool) {
        do {
            print(asJSON
                ? try LauncherCLIContextExport.json(for: record)
                : LauncherCLIContextExport.table(for: record)
            )
        } catch {
            FileHandle.standardError.write(Data("kwwk: failed to encode captured context: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func runWorkflow(
        _ workflow: LauncherWorkflow,
        query: String,
        executable: String,
        defaultThinking: KWWKThinkingLevel,
        defaultModel: String?,
        defaultContext1m: Bool
    ) async -> Int32 {
        let client = ProcessBackedKWWKCLIClient()
        let workingDirectory = FileManager.default.currentDirectoryPath
        let context = LauncherContextSnapshot(workingDirectory: workingDirectory)
        var previousOutput = ""

        for (index, step) in workflow.steps.enumerated() {
            let rendered = workflow.renderedTemplate(
                for: step,
                query: query,
                context: context,
                previousOutput: previousOutput
            )
            guard !rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                writeStderr("kwwk workflow: step \(index + 1), \(step.title), rendered an empty \(step.kind.rawValue) body\n")
                return 1
            }

            writeStderr("kwwk workflow: \(index + 1)/\(workflow.steps.count) \(step.title)\n")
            let invocation = workflow.invocation(
                for: step,
                renderedTemplate: rendered,
                query: query,
                executable: executable,
                defaultThinking: defaultThinking,
                defaultModel: defaultModel,
                defaultContext1M: defaultContext1m,
                workingDirectory: workingDirectory,
                context: context,
                previousOutput: previousOutput
            )

            do {
                let result = try await client.run(
                    invocation,
                    onStdout: { chunk in writeStdout(chunk) },
                    onStderr: { chunk in writeStderr(chunk) }
                )
                previousOutput = LauncherWorkflow.stepOutput(result)
                guard result.succeeded else {
                    writeStderr("kwwk workflow: step \(index + 1), \(step.title), exited \(result.exitCode)\n")
                    return result.exitCode == 0 ? 1 : result.exitCode
                }
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                writeStderr("kwwk workflow: step \(index + 1), \(step.title), failed: \(msg)\n")
                return 1
            }
        }

        return 0
    }

    static func currentExecutablePath() -> String {
        let raw = CommandLine.arguments.first ?? "kwwk"
        guard raw.contains("/") else { return raw }
        let url = URL(fileURLWithPath: raw)
        if url.path.hasPrefix("/") { return url.standardizedFileURL.path }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(raw)
            .standardizedFileURL
            .path
    }

    static func printLauncherCommands(
        query: String,
        includeApps: Bool,
        includeWorkspaceFiles: Bool,
        asJSON: Bool
    ) {
        let commands = launcherCommands(
            includeApps: includeApps,
            includeWorkspaceFiles: includeWorkspaceFiles,
            query: query
        )
        let filtered = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? commands
            : LauncherCommandFilter.filter(commands, query: query)

        do {
            print(asJSON
                ? try LauncherCommandExport.json(
                    for: filtered,
                    query: query,
                    workingDirectory: FileManager.default.currentDirectoryPath
                )
                : LauncherCommandExport.table(for: filtered)
            )
        } catch {
            FileHandle.standardError.write(Data("kwwk: failed to encode launcher commands: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func printLauncherCommandDetail(
        query: String,
        commandId: String?,
        includeApps: Bool,
        includeWorkspaceFiles: Bool,
        asJSON: Bool
    ) {
        let commands = launcherCommands(
            includeApps: includeApps,
            includeWorkspaceFiles: includeWorkspaceFiles,
            query: query
        )
        let command: LauncherCommand?

        if let commandId {
            command = commands.first { $0.id == commandId }
        } else {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else {
                FileHandle.standardError.write(Data(
                    "kwwk: --inspect-command needs --command <id> or a query\n".utf8
                ))
                Foundation.exit(2)
            }
            command = commands.first { $0.id == trimmedQuery }
                ?? LauncherCommandFilter.filter(commands, query: trimmedQuery).first
        }

        guard let command else {
            let target = commandId ?? query
            FileHandle.standardError.write(Data("kwwk: no launcher command matched '\(target)'\n".utf8))
            Foundation.exit(2)
        }

        let workingDirectory = FileManager.default.currentDirectoryPath
        let context = LauncherContextSnapshot(workingDirectory: workingDirectory)
        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: query,
            context: context,
            workingDirectory: workingDirectory
        )
        let record = LauncherCommandDetailExportRecord(
            command: command,
            preview: LauncherCommandPreview.text(
                for: command,
                query: query,
                context: context,
                workingDirectory: workingDirectory,
                availableCommands: commands
            ),
            featuredActions: LauncherActionCatalog.featuredActions(from: actions),
            query: query,
            workingDirectory: workingDirectory
        )

        do {
            print(asJSON
                ? try LauncherCommandDetailExport.json(for: record)
                : LauncherCommandDetailExport.text(for: record)
            )
        } catch {
            FileHandle.standardError.write(Data("kwwk: failed to encode launcher command detail: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func printLauncherActions(
        query: String,
        commandId: String?,
        actionId: String?,
        includeApps: Bool,
        includeWorkspaceFiles: Bool,
        featuredOnly: Bool,
        asJSON: Bool
    ) {
        let commands = launcherCommands(
            includeApps: includeApps,
            includeWorkspaceFiles: includeWorkspaceFiles,
            query: query
        )
        let command: LauncherCommand?

        if let commandId {
            command = commands.first { $0.id == commandId }
        } else {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else {
                FileHandle.standardError.write(Data(
                    "kwwk: --list-actions needs --command <id> or a query\n".utf8
                ))
                Foundation.exit(2)
            }
            command = commands.first { $0.id == trimmedQuery }
                ?? LauncherCommandFilter.filter(commands, query: trimmedQuery).first
        }

        guard let command else {
            let target = commandId ?? query
            FileHandle.standardError.write(Data("kwwk: no launcher command matched '\(target)'\n".utf8))
            Foundation.exit(2)
        }

        let allActions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: query,
            context: LauncherContextSnapshot(workingDirectory: FileManager.default.currentDirectoryPath),
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let actions: [LauncherActionItem]
        if let actionId {
            actions = allActions.filter { $0.id == actionId }
            guard !actions.isEmpty else {
                FileHandle.standardError.write(Data(
                    "kwwk: no launcher action matched '\(actionId)' for command '\(command.id)'\n".utf8
                ))
                Foundation.exit(2)
            }
        } else if featuredOnly {
            actions = LauncherActionCatalog.featuredActions(from: allActions)
        } else {
            actions = allActions
        }

        do {
            print(asJSON
                ? try LauncherActionExport.json(
                    for: actions,
                    command: command,
                    query: query,
                    workingDirectory: FileManager.default.currentDirectoryPath
                )
                : LauncherActionExport.table(
                    for: actions,
                    command: command,
                    query: query,
                    workingDirectory: FileManager.default.currentDirectoryPath
                )
            )
        } catch {
            FileHandle.standardError.write(Data("kwwk: failed to encode launcher actions: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func launcherCommands(
        includeApps: Bool,
        includeWorkspaceFiles: Bool = false,
        query: String = ""
    ) -> [LauncherCommand] {
        var commands = LauncherShellCommandFactory.commands(for: query)
        commands += LauncherPathCommandFactory.commands(
            for: query,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        commands += LauncherCalculatorCommandFactory.commands(for: query)
        commands += LauncherUnitConversionCommandFactory.commands(for: query)
        commands += LauncherWebCommandFactory.commands(for: query)
        commands += LauncherDynamicCommandFactory.commands(for: query)
        commands += LauncherCommandCatalog.defaults
        commands += AIRunHistoryCommandFactory.commands(for: AIRunHistoryStore.load())
        commands += LauncherClipboardHistoryCommandFactory.commands(for: LauncherClipboardHistoryStore.load())
        commands += LauncherAIProfileCatalog.commands(
            for: LauncherAIProfileIndex.load(),
            reservedCommandIds: LauncherAIProfileCatalog.defaultCommandIds
        )
        commands += LauncherCLIContextIndex.commands(
            for: LauncherCLIContextIndex.scan()
        )
        commands += LauncherPromptCommandIndex.commands(for: LauncherPromptCommandIndex.load())
        commands += LauncherWorkflowIndex.commands(for: LauncherWorkflowIndex.load())
        commands += LauncherQuicklinkIndex.commands(for: LauncherQuicklinkIndex.load())
        commands += LauncherSnippetIndex.commands(for: LauncherSnippetIndex.load())
        commands += LauncherScriptCommandIndex.commands(
            for: LauncherScriptCommandIndex.scan(roots: LauncherScriptCommandIndex.defaultRoots())
        )
        commands += LauncherWorkspaceCommandFactory.commands(for: FileManager.default.currentDirectoryPath)
        commands += LauncherWorkspaceTaskCommandFactory.commands(for: FileManager.default.currentDirectoryPath)

        if includeWorkspaceFiles {
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            commands += LauncherWorkspaceFileIndex.commands(for: LauncherWorkspaceFileIndex.scan(root: root))
        }

        if includeApps {
            commands += ApplicationIndex.commands(for: ApplicationIndex.scan(roots: ApplicationIndex.defaultRoots()))
        }
        commands += LauncherCommandAliasIndex.commands(
            for: LauncherCommandAliasIndex.load(),
            availableCommands: commands
        )

        return commands
    }

    static func readLauncherQuery(tokens: [String]) -> String {
        if tokens == ["-"] {
            if isatty(0) != 0 {
                FileHandle.standardError.write(Data(
                    "kwwk: launcher - requires stdin\n".utf8
                ))
                Foundation.exit(2)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }
        return tokens.joined(separator: " ")
    }

    static func readDraftPrompt(_ value: String?) -> String {
        guard let value else { return "" }
        guard value == "-" else { return value }
        if isatty(0) != 0 {
            FileHandle.standardError.write(Data(
                "kwwk: --draft - requires stdin\n".utf8
            ))
            Foundation.exit(2)
        }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func openLauncher(_ url: URL) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            process.waitUntilExit()
            Foundation.exit(process.terminationStatus)
        } catch {
            FileHandle.standardError.write(Data("kwwk: failed to open launcher: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
        #else
        FileHandle.standardError.write(Data(
            "kwwk: launcher bridge requires macOS. Deep link: \(url.absoluteString)\n".utf8
        ))
        Foundation.exit(1)
        #endif
    }

    /// Pull `--thinking <level>` out of argv and return the remaining args
    /// plus the parsed level. A missing flag defaults to `.medium`; an
    /// invalid value exits with usage.
    static func extractThinking(_ argv: [String]) -> ([String], ThinkingLevel, Bool) {
        var out: [String] = []
        var level: ThinkingLevel = .medium
        var seen = false
        var i = 0
        while i < argv.count {
            if argv[i] == "--thinking" {
                guard i + 1 < argv.count, let parsed = ThinkingLevel(rawValue: argv[i + 1]) else {
                    FileHandle.standardError.write(Data(
                        "kwwk: --thinking needs one of: off, minimal, low, medium, high, xhigh\n".utf8
                    ))
                    Foundation.exit(2)
                }
                level = parsed
                seen = true
                i += 2
            } else {
                out.append(argv[i])
                i += 1
            }
        }
        return (out, level, seen)
    }

    /// Pull `<flag> <value>` out of argv and return the remaining args plus
    /// the (optional) value. Missing flag → `nil`. Flag without a value →
    /// usage error.
    static func extractStringFlag(_ argv: [String], _ flag: String) -> ([String], String?) {
        var out: [String] = []
        var value: String? = nil
        var i = 0
        while i < argv.count {
            if argv[i] == flag {
                guard i + 1 < argv.count else {
                    FileHandle.standardError.write(Data(
                        "kwwk: \(flag) needs an argument\n".utf8
                    ))
                    Foundation.exit(2)
                }
                value = argv[i + 1]
                i += 2
            } else {
                out.append(argv[i])
                i += 1
            }
        }
        return (out, value)
    }

    /// Pull a boolean `<flag>` out of argv. Returns `(remaining, true)` if
    /// present, `(argv, false)` if not.
    static func extractBoolFlag(_ argv: [String], _ flag: String) -> ([String], Bool) {
        var out: [String] = []
        var seen = false
        for arg in argv {
            if arg == flag { seen = true } else { out.append(arg) }
        }
        return (out, seen)
    }

    /// Handle `-p` / `--print`. Everything after the flag is joined into
    /// the prompt; if nothing is supplied (or the token is a bare `-`),
    /// the prompt is read from stdin until EOF.
    ///
    /// `-p` is quiet by design: on a successful run stdout carries only
    /// the assistant reply and stderr stays empty. Failures (no prompt,
    /// missing credentials, stream error) still print a one-line message
    /// to stderr so a non-zero exit isn't mysterious. Exit codes: 2 = bad
    /// invocation, 1 = runtime/auth failure, 0 = success.
    static func runPrint(
        rest: [String],
        thinkingLevel: ThinkingLevel,
        modelOverride: String?,
        context1m: Bool
    ) async {
        let prompt: String
        if rest.isEmpty || rest == ["-"] {
            // Use fd 0 directly instead of `fileno(stdin)` — on Linux
            // Glibc exposes `stdin` as a non-Sendable mutable var that
            // Swift 6 strict concurrency rejects. stdin's fd is always 0.
            if isatty(0) != 0 {
                FileHandle.standardError.write(Data(
                    "kwwk: -p requires a prompt argument when stdin is a terminal\n".utf8
                ))
                Foundation.exit(2)
            }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            prompt = String(data: data, encoding: .utf8) ?? ""
        } else {
            prompt = rest.joined(separator: " ")
        }

        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            FileHandle.standardError.write(Data(
                "kwwk: -p requires a non-empty prompt (as argument or via stdin)\n".utf8
            ))
            Foundation.exit(2)
        }

        do {
            let capture = HeadlessRunCapture()
            let code = try await KWWK.runHeadless(
                prompt: prompt,
                thinkingLevel: thinkingLevel,
                modelOverride: modelOverride,
                context1m: context1m,
                onStdout: { capture.appendStdout($0) },
                onStderr: { capture.appendStderr($0) }
            )
            recordHeadlessHistory(
                prompt: prompt,
                capture: capture,
                exitCode: code,
                thinkingLevel: thinkingLevel,
                modelOverride: modelOverride,
                context1m: context1m
            )
            Foundation.exit(code)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            FileHandle.standardError.write(Data("kwwk: \(msg)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func recordHeadlessHistory(
        prompt: String,
        capture: HeadlessRunCapture,
        exitCode: Int32,
        thinkingLevel: ThinkingLevel,
        modelOverride: String?,
        context1m: Bool
    ) {
        let thinking = KWWKThinkingLevel(rawValue: thinkingLevel.rawValue) ?? .medium
        let invocation = KWWKCLIInvocation.headless(
            prompt: prompt,
            executable: currentExecutablePath(),
            thinking: thinking,
            model: modelOverride,
            context1m: context1m,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        let historyLimit = UserDefaults.standard.object(forKey: LauncherPreferenceKeys.aiHistoryLimit) as? Int
            ?? LauncherPreferences.defaultHistoryLimit
        let record = AIRunHistoryRecord(
            prompt: prompt,
            output: capture.stdout,
            errorOutput: capture.stderr,
            exitCode: exitCode,
            model: modelOverride,
            command: invocation.shellCommand,
            workingDirectory: FileManager.default.currentDirectoryPath
        )
        try? AIRunHistoryStore.append(
            record,
            limit: LauncherPreferences.normalizedHistoryLimit(historyLimit)
        )
    }

    /// Run the async body and surface any thrown error on stderr before
    /// exiting with a non-zero code. Swift async `@main` has no throwing
    /// overload, so this is the workaround.
    static func runOrExit(_ body: @Sendable () async throws -> Void) async {
        do {
            try await body()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            FileHandle.standardError.write(Data("kwwk: \(msg)\n".utf8))
            Foundation.exit(1)
        }
    }
}

private func writeStdout(_ value: String) {
    FileHandle.standardOutput.write(Data(value.utf8))
}

private func writeStderr(_ value: String) {
    FileHandle.standardError.write(Data(value.utf8))
}

final class HeadlessRunCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutChunks: [String] = []
    private var stderrChunks: [String] = []

    var stdout: String {
        lock.withLock { stdoutChunks.joined() }
    }

    var stderr: String {
        lock.withLock { stderrChunks.joined() }
    }

    func appendStdout(_ value: String) {
        lock.withLock {
            stdoutChunks.append(value)
        }
    }

    func appendStderr(_ value: String) {
        lock.withLock {
            stderrChunks.append(value)
        }
    }
}
