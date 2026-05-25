import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher action catalog")
struct LauncherActionCatalogTests {
    @Test
    func applicationCommandsExposeRaycastStyleActions() {
        let command = LauncherCommand(
            id: "app:/Applications/Fixture.app",
            title: "Fixture",
            subtitle: "dev.kwwk.fixture",
            systemImage: "app",
            category: .app,
            keywords: [],
            action: .openApplication("/Applications/Fixture.app")
        )

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(actions.map(\.id).contains("primary"))
        #expect(actions.map(\.id).contains("favorite"))
        #expect(actions.map(\.id).contains("ask-kwwk"))
        #expect(actions.map(\.id).contains("reveal"))
        #expect(actions.map(\.id).contains("copy-path"))
    }

    @Test
    func favoriteActionReflectsCurrentState() {
        let command = LauncherCommandCatalog.defaults[0]

        let favorite = LauncherActionCatalog.actions(for: command, isFavorite: false)
            .first { $0.id == "favorite" }
        let unfavorite = LauncherActionCatalog.actions(for: command, isFavorite: true)
            .first { $0.id == "favorite" }

        #expect(favorite?.title == "Favorite")
        #expect(unfavorite?.title == "Remove Favorite")
    }

    @Test
    func featuredActionsPrioritizeCommandSpecificActions() {
        let command = LauncherCommand(
            id: "app:/Applications/Fixture.app",
            title: "Fixture",
            subtitle: "dev.kwwk.fixture",
            systemImage: "app",
            category: .app,
            keywords: [],
            action: .openApplication("/Applications/Fixture.app")
        )
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        let featured = LauncherActionCatalog.featuredActions(from: actions)

        #expect(featured.map(\.id) == ["reveal", "copy-path", "open-context-draft"])
    }

    @Test
    func featuredActionsRespectLimitAndSkipLauncherAutomationCopies() throws {
        let command = try #require(LauncherDynamicCommandFactory.commands(for: "summarize current project").first)
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        let featured = LauncherActionCatalog.featuredActions(from: actions, limit: 2)

        #expect(featured.map(\.id) == ["open-terminal", "open-cli-draft"])
        #expect(!featured.map(\.id).contains("copy-launcher-command"))
        #expect(!featured.map(\.id).contains("copy-launcher-url"))
        #expect(!featured.map(\.id).contains("copy-inspect-command"))
    }

    @Test
    func featuredActionsFallbackToContextDraftForGenericCommands() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "open-cli" })
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        let featured = LauncherActionCatalog.featuredActions(from: actions)

        #expect(featured.map(\.id) == ["open-context-draft"])
    }

    @Test
    func askActionCarriesSelectedCommandContext() {
        let command = LauncherCommandCatalog.defaults[0]

        let ask = LauncherActionCatalog.actions(for: command, isFavorite: false)
            .first { $0.id == "ask-kwwk" }

        guard case .askKWWK(let prompt) = ask?.kind else {
            Issue.record("Expected ask action")
            return
        }
        #expect(prompt.contains("Title: Ask KWWK"))
        #expect(prompt.contains("Category: AI"))
    }

    @Test
    func promptCommandAskContextIncludesRenderedPrompt() throws {
        let promptCommand = LauncherPromptCommand(
            id: "review-code",
            title: "Review Code",
            keywords: ["review"],
            promptTemplate: "Review {query}\nClipboard: {clipboard}\nWorkspace: {workspace}\nFinder:\n{finderSelection}\nApp: {frontmostApp}"
        )
        let command = try #require(LauncherPromptCommandIndex.commands(for: [promptCommand]).first)

        let ask = try #require(LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "Review Code Package.swift",
            clipboard: "diff --git",
            context: LauncherContextSnapshot(
                workingDirectory: "/Users/f/project",
                finderSelectionPaths: ["/Users/f/project/Package.swift"],
                frontmostApplicationName: "Xcode"
            )
        ).first { $0.id == "ask-kwwk" })

        guard case .askKWWK(let prompt) = ask.kind else {
            Issue.record("Expected ask action")
            return
        }

        #expect(prompt.contains("Prompt command template: Review {query}"))
        #expect(prompt.contains("""
        Rendered prompt:
        Review Package.swift
        Clipboard: diff --git
        Workspace: /Users/f/project
        Finder:
        /Users/f/project/Package.swift
        App: Xcode
        """))
    }

    @Test
    func snippetAskContextIncludesRenderedText() throws {
        let snippet = LauncherSnippet(
            id: "thanks",
            title: "Thanks",
            keywords: ["ty"],
            textTemplate: "Thanks, {query}.\nClipboard: {clipboard}\nCWD: {cwd}"
        )
        let command = try #require(LauncherSnippetIndex.commands(for: [snippet]).first)

        let ask = try #require(LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "Thanks Martin",
            clipboard: "release notes",
            context: LauncherContextSnapshot(workingDirectory: "/Users/f/project")
        ).first { $0.id == "ask-kwwk" })

        guard case .askKWWK(let prompt) = ask.kind else {
            Issue.record("Expected ask action")
            return
        }

        #expect(prompt.contains("Snippet template: Thanks, {query}."))
        #expect(prompt.contains("""
        Rendered snippet:
        Thanks, Martin.
        Clipboard: release notes
        CWD: /Users/f/project
        """))
    }

    @Test
    func quicklinkAskContextIncludesRenderedURL() throws {
        let quicklink = LauncherQuicklink(
            id: "github-search",
            title: "GitHub Search",
            keywords: ["gh"],
            urlTemplate: "https://github.com/search?q={query}&type=code"
        )
        let command = try #require(LauncherQuicklinkIndex.commands(for: [quicklink]).first)

        let ask = try #require(LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "GitHub Search swift package"
        ).first { $0.id == "ask-kwwk" })

        guard case .askKWWK(let prompt) = ask.kind else {
            Issue.record("Expected ask action")
            return
        }

        #expect(prompt.contains("Quicklink URL: https://github.com/search?q={query}&type=code"))
        #expect(prompt.contains("Rendered URL: https://github.com/search?q=swift%20package&type=code"))
    }

    @Test
    func presetAskContextIncludesResolvedInputAndRenderedPrompt() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "ai-preset:shell-command" })

        let ask = try #require(LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "Generate Shell Command list modified files"
        ).first { $0.id == "ask-kwwk" })

        guard case .askKWWK(let prompt) = ask.kind else {
            Issue.record("Expected ask action")
            return
        }

        #expect(prompt.contains("Resolved preset input:\nlist modified files"))
        #expect(prompt.contains("Rendered preset prompt:"))
        #expect(prompt.contains("Input:\nlist modified files"))
    }

    @Test
    func selectedCommandContextCanOpenAsInteractiveCLIDraft() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "open-cli" })
        let expectedPrompt = """
        Explain this launcher result and suggest the most useful next actions.

        Title: Open KWWK CLI
        Category: CLI
        Description: Start the interactive terminal agent
        """

        let draft = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            executable: "/tmp/kwwk helper",
            thinking: .high,
            model: "gpt-5.4",
            context1m: true,
            workingDirectory: "/Users/f/My Project"
        ).first { $0.id == "open-context-draft" }

        #expect(draft?.title == "Open Context Draft in CLI")
        #expect(draft?.kind == .openTerminalCommand(KWWKCLIInvocation.interactiveDraftTerminalCommand(
            prompt: expectedPrompt,
            executable: "/tmp/kwwk helper",
            thinking: .high,
            model: "gpt-5.4",
            context1m: true,
            workingDirectory: "/Users/f/My Project"
        )))
    }

    @Test
    func actionsExposeReusableLauncherCommand() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "open-cli" })

        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            workingDirectory: "/Users/f/project"
        )
        let copy = actions.first { $0.id == "copy-launcher-command" }
        let copyURL = actions.first { $0.id == "copy-launcher-url" }
        let copyInspect = actions.first { $0.id == "copy-inspect-command" }
        let saveAlias = actions.first { $0.id == "save-command-alias" }

        #expect(copy?.kind == .copyText("kwwk launcher --command open-cli --run"))
        #expect(copyURL?.kind == .copyText(
            "kwwk://launcher?command=open-cli&run=1&cwd=/Users/f/project"
        ))
        #expect(copyInspect?.kind == .copyText(
            "kwwk launcher --inspect-command --command open-cli --json"
        ))
        #expect(saveAlias?.kind == .saveCommandAlias(LauncherCommandAlias(
            id: "saved-open-cli",
            title: "Open KWWK CLI",
            subtitle: "Alias for Open KWWK CLI",
            targetCommandId: "open-cli",
            systemImage: "terminal",
            keywords: [
                "open-cli",
                "Open KWWK CLI",
                "Start the interactive terminal agent",
                "CLI",
                "terminal",
                "interactive",
                "tui",
                "cli",
                "kwwk",
            ]
        )))
    }

    @Test
    func dynamicAskCommandCopiesAskBridgeCommand() throws {
        let command = try #require(LauncherDynamicCommandFactory.commands(for: "summarize current project").first)

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)
        let copy = actions
            .first { $0.id == "copy-launcher-command" }

        #expect(copy?.kind == .copyText("kwwk launcher --ask 'summarize current project'"))
        #expect(actions.contains { $0.id == "save-command-alias" } == false)
    }

    @Test
    func dynamicAskCommandCopiesRunnableLauncherURL() throws {
        let command = try #require(LauncherDynamicCommandFactory.commands(for: "summarize current project").first)

        let copyURL = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            workingDirectory: "/Users/f/project"
        ).first { $0.id == "copy-launcher-url" }

        #expect(copyURL?.kind == .copyText(
            "kwwk://launcher/ask?prompt=summarize%20current%20project&run=1&cwd=/Users/f/project"
        ))
    }

    @Test
    func dynamicAskCommandCanSavePromptCommand() throws {
        let command = try #require(LauncherDynamicCommandFactory.commands(for: "summarize current project").first)
        let promptCommand = try #require(LauncherPromptCommandIndex.promptCommand(
            fromPrompt: "summarize current project"
        ))
        let workflow = try #require(LauncherWorkflowIndex.workflow(fromPrompt: "summarize current project"))
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        let savePrompt = actions.first { $0.id == "save-prompt-command" }
        let saveWorkflow = actions.first { $0.id == "save-workflow" }

        #expect(savePrompt?.title == "Save as Prompt Command")
        #expect(savePrompt?.kind == .savePromptTemplate(promptCommand))
        #expect(saveWorkflow?.title == "Save as Workflow")
        #expect(saveWorkflow?.kind == .saveWorkflow(workflow))
    }

    @Test
    func dynamicAskCommandCanOpenPromptInTerminalWithLauncherOptions() throws {
        let command = try #require(LauncherDynamicCommandFactory.commands(for: "summarize current project").first)

        let openTerminal = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            executable: "/tmp/kwwk helper",
            thinking: .high,
            model: "gpt-5.4",
            context1m: true,
            workingDirectory: "/Users/f/My Project"
        ).first { $0.id == "open-terminal" }

        #expect(openTerminal?.kind == .openTerminalCommand(
            "cd '/Users/f/My Project' && printf %s 'summarize current project' | '/tmp/kwwk helper' --thinking high --model gpt-5.4 --context-1m -p -"
        ))

        let openDraft = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            executable: "/tmp/kwwk helper",
            thinking: .high,
            model: "gpt-5.4",
            context1m: true,
            workingDirectory: "/Users/f/My Project"
        ).first { $0.id == "open-cli-draft" }

        #expect(openDraft?.kind == .openTerminalCommand(
            "cd '/Users/f/My Project' && '/tmp/kwwk helper' --thinking high --model gpt-5.4 --context-1m --draft 'summarize current project'"
        ))
    }

    @Test
    func modelCommandsExposeRunnableLauncherBridge() throws {
        let commands = LauncherModelCommandCatalog.commands()
        let model = try #require(commands.first { $0.id == "model:gpt-5.4" })
        let clear = try #require(commands.first { $0.id == "model:provider-default" })

        #expect(LauncherActionCatalog.primaryTitle(for: model) == "Use Model")
        #expect(LauncherActionCatalog.primaryTitle(for: clear) == "Clear")
        #expect(LauncherActionCatalog.actions(for: model, isFavorite: false)
            .first { $0.id == "copy-launcher-command" }?.kind == .copyText(
                "kwwk launcher --command model:gpt-5.4 --run"
            ))
        #expect(LauncherActionCatalog.actions(for: clear, isFavorite: false)
            .first { $0.id == "copy-launcher-command" }?.kind == .copyText(
                "kwwk launcher --command model:provider-default --run"
            ))
    }

    @Test
    func shellCommandCopiesExactLauncherBridgeCommand() throws {
        let command = try #require(LauncherShellCommandFactory.commands(for: "$ git status --short").first)

        let copy = LauncherActionCatalog.actions(for: command, isFavorite: false)
            .first { $0.id == "copy-launcher-command" }

        #expect(copy?.kind == .copyText("kwwk launcher --command 'shell:git status --short' --run -- '$ git status --short'"))
    }

    @Test
    func inspectCommandActionCarriesDynamicResultQuery() throws {
        let command = try #require(LauncherShellCommandFactory.commands(for: "$ git status --short").first)

        let action = try #require(LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "$ git status --short"
        ).first { $0.id == "copy-inspect-command" })

        #expect(action.kind == .copyText(
            "kwwk launcher --inspect-command --command 'shell:git status --short' --json -- '$ git status --short'"
        ))
    }

    @Test
    func rerunPromptPrimaryTitleMatchesHistoryCommand() {
        let command = LauncherCommand(
            id: "ai-history:1",
            title: "Explain module",
            subtitle: "AI history",
            systemImage: "clock.arrow.circlepath",
            category: .ai,
            keywords: [],
            action: .rerunPrompt("Explain module")
        )

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Ask Again")
    }

    @Test
    func aiHistoryCommandsExposeResultActions() throws {
        let record = AIRunHistoryRecord(
            id: "history",
            prompt: "Explain module",
            output: "It coordinates launcher commands.",
            exitCode: 0,
            model: "gpt-5.4",
            command: "kwwk -p -"
        )
        let command = LauncherCommand(
            id: "ai-history:history",
            title: "Explain module",
            subtitle: "AI history",
            systemImage: "clock.arrow.circlepath",
            category: .ai,
            keywords: [],
            action: .rerunAIHistory(record)
        )

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Ask Again")
        #expect(actions.map(\.id).contains("copy-output"))
        #expect(actions.map(\.id).contains("copy-prompt"))
        #expect(actions.map(\.id).contains("save-prompt-command"))
        #expect(actions.map(\.id).contains("save-answer-snippet"))
        #expect(actions.map(\.id).contains("save-workflow"))
        #expect(actions.map(\.id).contains("open-cli-draft"))
        #expect(actions.map(\.id).contains("copy-command"))
        #expect(actions.map(\.id).contains("open-terminal"))
        let savePrompt = actions.first { $0.id == "save-prompt-command" }
        #expect(savePrompt?.title == "Save as Prompt Command")
        #expect(savePrompt?.kind == .savePromptCommand(record))
        let saveSnippet = actions.first { $0.id == "save-answer-snippet" }
        #expect(saveSnippet?.title == "Save Answer as Snippet")
        #expect(saveSnippet?.kind == .saveSnippet(try #require(
            LauncherSnippetIndex.snippet(fromAIHistoryOutput: record)
        )))
        let saveWorkflow = actions.first { $0.id == "save-workflow" }
        #expect(saveWorkflow?.title == "Save as Workflow")
        #expect(saveWorkflow?.kind == .saveWorkflow(LauncherWorkflowIndex.workflow(from: record)))
        let askContext = actions.first { $0.id == "ask-kwwk" }
        if case .askKWWK(let prompt) = askContext?.kind {
            #expect(prompt.contains("Original prompt: Explain module"))
            #expect(prompt.contains("Previous answer:\nIt coordinates launcher commands."))
        } else {
            Issue.record("expected ask context action to carry AI history prompt")
        }
        let openDraft = actions.first { $0.id == "open-cli-draft" }
        #expect(openDraft?.kind == .openTerminalCommand(
            "kwwk --thinking medium --model gpt-5.4 --draft 'Explain module'"
        ))
        let openTerminal = actions.first { $0.id == "open-terminal" }
        #expect(openTerminal?.kind == .openTerminalCommand("printf %s 'Explain module' | kwwk -p -"))
    }

    @Test
    func failedAIHistoryContextIncludesErrorOutput() throws {
        let record = AIRunHistoryRecord(
            id: "failed-history",
            prompt: "Fix failing build",
            output: "",
            errorOutput: "Swift compiler exited with code 1.",
            exitCode: 1,
            model: nil,
            command: "kwwk -p -"
        )
        let command = LauncherCommand(
            id: "ai-history:failed-history",
            title: "Fix failing build",
            subtitle: "Failed AI run",
            systemImage: "exclamationmark.bubble",
            category: .ai,
            keywords: [],
            action: .rerunAIHistory(record)
        )

        let askContext = try #require(LauncherActionCatalog.actions(
            for: command,
            isFavorite: false
        ).first { $0.id == "ask-kwwk" })

        if case .askKWWK(let prompt) = askContext.kind {
            #expect(prompt.contains("Exit code: 1"))
            #expect(prompt.contains("Previous error output:\nSwift compiler exited with code 1."))
            #expect(!prompt.contains("Previous answer:"))
        } else {
            Issue.record("expected ask context action")
        }
    }

    @Test
    func copyCommandActionsCanOpenCommandInTerminal() {
        let command = LauncherCommand(
            id: "copy-command",
            title: "Copy Command",
            subtitle: "kwwk login",
            systemImage: "terminal",
            category: .cli,
            keywords: [],
            action: .copyCommand("kwwk login")
        )

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(actions.map(\.id).contains("copy-command"))
        #expect(actions.map(\.id).contains("open-terminal"))
        #expect(actions.first { $0.id == "open-terminal" }?.kind == .openTerminalCommand("kwwk login"))
    }

    @Test
    func shellCommandActionsCanCopyCommand() throws {
        let command = LauncherCommand(
            id: "shell:git status",
            title: "Run Shell Command",
            subtitle: "git status",
            systemImage: "terminal",
            category: .cli,
            keywords: [],
            action: .runShellCommand("git status")
        )

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run")
        #expect(actions.map(\.id).contains("copy-command"))
        let saveScript = actions.first { $0.id == "save-script-command" }
        let saveWorkflow = actions.first { $0.id == "save-workflow" }
        #expect(saveScript?.title == "Save as Script Command")
        #expect(saveScript?.kind == .saveScriptCommand(try #require(
            LauncherScriptCommandIndex.scriptDraft(fromShellCommand: "git status")
        )))
        #expect(saveWorkflow?.title == "Save as Workflow")
        #expect(saveWorkflow?.kind == .saveWorkflow(try #require(
            LauncherWorkflowIndex.workflow(fromShellCommand: "git status")
        )))
    }

    @Test
    func quicklinkActionsCanCopyRenderedURL() throws {
        let quicklink = LauncherQuicklink(
            id: "github-search",
            title: "GitHub Search",
            keywords: ["gh"],
            urlTemplate: "https://github.com/search?q={query}"
        )
        let command = try #require(LauncherQuicklinkIndex.commands(for: [quicklink]).first)

        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "gh swift package manager"
        )

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Open")
        #expect(actions.first { $0.id == "copy-url" }?.kind == .copyText(
            "https://github.com/search?q=swift%20package%20manager"
        ))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command quicklink:github-search --run -- 'swift package manager'"
        ))
    }

    @Test
    func dynamicURLActionsCanSaveQuicklinks() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "https://example.com/docs").first)

        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "https://example.com/docs"
        )

        let saveQuicklink = actions.first { $0.id == "save-quicklink" }
        #expect(saveQuicklink?.title == "Save as Quicklink")
        #expect(saveQuicklink?.kind == .saveQuicklink(try #require(
            LauncherQuicklinkIndex.quicklink(fromDynamicCommand: command)
        )))
    }

    @Test
    func dynamicSearchActionsCanSaveQuicklinks() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "web swift package manager").first)

        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "web swift package manager"
        )

        let saveQuicklink = actions.first { $0.id == "save-quicklink" }
        #expect(saveQuicklink?.title == "Save as Quicklink")
        #expect(saveQuicklink?.kind == .saveQuicklink(try #require(
            LauncherQuicklinkIndex.quicklink(fromDynamicCommand: command)
        )))
    }

    @Test
    func scriptCommandsExposePathActions() {
        let script = LauncherScriptCommand(
            id: "script",
            title: "Run Script",
            subtitle: "Local automation",
            scriptPath: "/Users/f/.kwwk/launcher/commands/script"
        )
        let command = LauncherScriptCommandIndex.commands(for: [script])[0]

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run Script")
        #expect(actions.map(\.id).contains("reveal"))
        #expect(actions.map(\.id).contains("copy-path"))
    }

    @Test
    func scriptFolderCommandsExposeExpectedPrimaryTitles() throws {
        let reveal = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reveal-script-commands" })
        let reload = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reload-script-commands" })

        #expect(LauncherActionCatalog.primaryTitle(for: reveal) == "Reveal")
        #expect(LauncherActionCatalog.primaryTitle(for: reload) == "Reload")
    }

    @Test
    func quicklinkFileCommandsExposeExpectedPrimaryTitles() throws {
        let reveal = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reveal-quicklinks" })
        let reload = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reload-quicklinks" })

        #expect(LauncherActionCatalog.primaryTitle(for: reveal) == "Reveal")
        #expect(LauncherActionCatalog.primaryTitle(for: reload) == "Reload")
    }

    @Test
    func aiHistoryFileCommandsExposeExpectedPrimaryTitles() throws {
        let reveal = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reveal-ai-history" })
        let reload = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reload-ai-history" })

        #expect(LauncherActionCatalog.primaryTitle(for: reveal) == "Reveal")
        #expect(LauncherActionCatalog.primaryTitle(for: reload) == "Reload")
        #expect(LauncherActionCatalog.actions(for: reveal, isFavorite: false)
            .first { $0.id == "copy-location" }?.kind == .copyText("~/.kwwk/launcher/ai-history.json"))
    }

    @Test
    func presetCommandsExposeInstructionActions() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "ai-preset:shell-command" })

        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "shell command list swift files"
        )

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run Preset")
        #expect(actions.map(\.id).contains("copy-instruction"))
        #expect(actions.first { $0.id == "open-terminal" }?.kind == .openTerminalCommand(
            "printf %s 'Convert this request into a zsh command for macOS. Prefer safe, inspectable commands and call out any destructive step instead of executing it.\n\nInput:\nlist swift files' | kwwk --thinking medium -p -"
        ))
    }

    @Test
    func dynamicAskCommandUsesAskPrimaryTitle() throws {
        let command = try #require(LauncherDynamicCommandFactory.commands(for: "explain this failure").first)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Ask")
    }

    @Test
    func recentCommandsExposeRunAgainPrimaryAction() throws {
        var usage = LauncherCommandUsage()
        usage.markUsed("open-cli", at: Date(timeIntervalSinceReferenceDate: 100))
        let command = try #require(LauncherRecentCommandFactory.commands(
            from: LauncherCommandCatalog.defaults,
            usage: usage
        ).first)

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run Again")
        #expect(actions.map(\.id).contains("copy-command-id"))
    }
}
