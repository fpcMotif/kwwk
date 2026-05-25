import KWWKLauncherCore
import Foundation
import Testing

@Suite("Launcher command export")
struct LauncherCommandExportTests {
    @Test
    func tableListsStableCommandIdsForAutomation() {
        let commands = [
            LauncherCommand(
                id: "script:deploy",
                title: "Deploy",
                subtitle: "Run deploy script",
                systemImage: "play",
                category: .script,
                keywords: [],
                action: .runScript(LauncherScriptCommand(
                    id: "deploy",
                    title: "Deploy",
                    subtitle: "Run deploy script",
                    scriptPath: "/tmp/deploy"
                ))
            ),
            LauncherCommand(
                id: "ask-kwwk",
                title: "Ask KWWK",
                subtitle: "Run prompt",
                systemImage: "sparkles",
                category: .ai,
                keywords: [],
                action: .askAI
            ),
        ]

        let table = LauncherCommandExport.table(for: commands)

        #expect(table == """
        ask-kwwk\tAI\tAsk KWWK\tRun prompt
        script:deploy\tScripts\tDeploy\tRun deploy script
        """)
    }

    @Test
    func jsonExportsSortedRecords() throws {
        let commands = [
            LauncherCommand(
                id: "workspace:copy-path",
                title: "Copy Workspace Path",
                subtitle: "/Users/f/project",
                systemImage: "doc.on.doc",
                category: .workspace,
                keywords: [],
                action: .copyWorkspacePath("/Users/f/project")
            ),
            LauncherCommand(
                id: "open-cli",
                title: "Open KWWK CLI",
                subtitle: "Start terminal",
                systemImage: "terminal",
                category: .cli,
                keywords: [],
                action: .openInteractiveCLI
            ),
        ]

        let json = try LauncherCommandExport.json(for: commands)

        #expect(json.contains("\"id\" : \"open-cli\""))
        #expect(json.contains("\"category\" : \"CLI\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command open-cli --run\""))
        #expect(json.contains("\"launcherURL\" : \"kwwk:\\/\\/launcher?command=open-cli&run=1\""))
        let cliRecordIndex = try #require(json.range(of: "\"id\" : \"open-cli\"")?.lowerBound)
        let workspaceRecordIndex = try #require(json.range(of: "\"id\" : \"workspace:copy-path\"")?.lowerBound)
        #expect(cliRecordIndex < workspaceRecordIndex)
    }

    @Test
    func recordsIncludeReplayableLauncherCommand() throws {
        let promptCommand = LauncherPromptCommand(
            id: "review-diff",
            title: "Review Diff",
            keywords: ["review"],
            promptTemplate: "Review {query}"
        )
        let command = try #require(LauncherPromptCommandIndex.commands(for: [promptCommand]).first)

        let record = try #require(LauncherCommandExport.records(for: [command]).first)

        #expect(record.launcherCommand == "kwwk launcher --command prompt:review-diff --run -- '<query>'")
        #expect(record.launcherURL == "kwwk://launcher?command=prompt:review-diff")
    }

    @Test
    func recordsIncludeScriptInputReplayPlaceholder() throws {
        let script = LauncherScriptCommand(
            id: "summarize",
            title: "Summarize Repo",
            subtitle: "Run local automation",
            scriptPath: "/Users/f/.kwwk/launcher/commands/summarize.zsh",
            argumentMode: .stdin
        )
        let command = try #require(LauncherScriptCommandIndex.commands(for: [script]).first)

        let record = try #require(LauncherCommandExport.records(for: [command]).first)
        let copy = try #require(LauncherActionCatalog.actions(for: command, isFavorite: false)
            .first { $0.id == "copy-launcher-command" })

        #expect(record.launcherCommand == "kwwk launcher --command script:summarize --run -- '<query>'")
        #expect(record.launcherURL == "kwwk://launcher?command=script:summarize")
        #expect(copy.kind == .copyText("kwwk launcher --command script:summarize --run -- '<query>'"))
    }

    @Test
    func scriptLauncherURLRunsOnlyWhenInputIsResolved() throws {
        let inputScript = LauncherScriptCommand(
            id: "summarize",
            title: "Summarize Repo",
            subtitle: "Run local automation",
            scriptPath: "/Users/f/.kwwk/launcher/commands/summarize.zsh",
            argumentMode: .stdin
        )
        let fixedScript = LauncherScriptCommand(
            id: "open-dashboard",
            title: "Open Dashboard",
            subtitle: "No input",
            scriptPath: "/Users/f/.kwwk/launcher/commands/open-dashboard.zsh"
        )
        let inputCommand = try #require(LauncherScriptCommandIndex.commands(for: [inputScript]).first)
        let fixedCommand = try #require(LauncherScriptCommandIndex.commands(for: [fixedScript]).first)

        #expect(LauncherActionCatalog.launcherURL(for: inputCommand) == "kwwk://launcher?command=script:summarize")
        #expect(LauncherActionCatalog.launcherURL(
            for: inputCommand,
            query: "staged diff",
            workingDirectory: "/Users/f/project"
        ) == "kwwk://launcher?query=staged%20diff&command=script:summarize&run=1&cwd=/Users/f/project")
        #expect(LauncherActionCatalog.launcherURL(for: fixedCommand) == """
        kwwk://launcher?command=script:open-dashboard&run=1
        """)
    }

    @Test
    func actionTablePreservesRaycastActionOrder() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "open-cli" })

        let table = LauncherActionExport.table(
            for: LauncherActionCatalog.actions(for: command, isFavorite: false),
            command: command
        )

        #expect(table == """
        primary\trunPrimary\tOpen CLI\tOpen KWWK CLI\tkwwk launcher --command open-cli --action primary --run
        favorite\ttoggleFavorite\tFavorite\tRank this command first\tkwwk launcher --command open-cli --action favorite --run
        ask-kwwk\taskKWWK\tAsk KWWK About This\tSend the selected result as context\tkwwk launcher --command open-cli --action ask-kwwk --run
        open-context-draft\topenTerminalCommand\tOpen Context Draft in CLI\tInteractive CLI draft\tkwwk launcher --command open-cli --action open-context-draft --run
        copy-launcher-command\tcopyText\tCopy Launcher Command\tkwwk launcher --command open-cli --run\tkwwk launcher --command open-cli --action copy-launcher-command --run
        copy-launcher-url\tcopyText\tCopy Launcher URL\tkwwk://launcher?command=open-cli&run=1\tkwwk launcher --command open-cli --action copy-launcher-url --run
        copy-inspect-command\tcopyText\tCopy Inspect Command\tkwwk launcher --inspect-command --command open-cli --json\tkwwk launcher --command open-cli --action copy-inspect-command --run
        save-command-alias\tsaveCommandAlias\tSave as Alias\topen-cli\tkwwk launcher --command open-cli --action save-command-alias --run
        """)
    }

    @Test
    func actionJSONIncludesAutomationPayloads() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "open-cli" })

        let json = try LauncherActionExport.json(
            for: LauncherActionCatalog.actions(for: command, isFavorite: false),
            command: command
        )

        #expect(json.contains("\"id\" : \"copy-launcher-command\""))
        #expect(json.contains("\"kind\" : \"copyText\""))
        #expect(json.contains("\"value\" : \"kwwk launcher --command open-cli --run\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command open-cli --action copy-launcher-command --run\""))
        #expect(json.contains("\"launcherURL\" : \"kwwk:\\/\\/launcher?command=open-cli&action=copy-launcher-command&run=1\""))
        #expect(json.contains("\"id\" : \"copy-launcher-url\""))
        #expect(json.contains("\"value\" : \"kwwk:\\/\\/launcher?command=open-cli&run=1\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command open-cli --action copy-launcher-url --run\""))
        #expect(json.contains("\"id\" : \"copy-inspect-command\""))
        #expect(json.contains("\"value\" : \"kwwk launcher --inspect-command --command open-cli --json\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command open-cli --action copy-inspect-command --run\""))
        #expect(json.contains("\"id\" : \"open-context-draft\""))
        #expect(json.contains("\"kind\" : \"openTerminalCommand\""))
        #expect(json.contains("\"id\" : \"save-command-alias\""))
        #expect(json.contains("\"kind\" : \"saveCommandAlias\""))
        #expect(json.contains("\"value\" : \"open-cli\""))
    }

    @Test
    func featuredActionExportMatchesPreviewActionStrip() throws {
        let command = LauncherCommand(
            id: "app:/Applications/Fixture.app",
            title: "Fixture",
            subtitle: "dev.kwwk.fixture",
            systemImage: "app",
            category: .app,
            keywords: [],
            action: .openApplication("/Applications/Fixture.app")
        )
        let actions = LauncherActionCatalog.featuredActions(
            from: LauncherActionCatalog.actions(for: command, isFavorite: false)
        )

        let table = LauncherActionExport.table(for: actions, command: command)
        let json = try LauncherActionExport.json(for: actions, command: command)

        #expect(table.split(separator: "\n").map { String($0.split(separator: "\t")[0]) } == [
            "reveal",
            "copy-path",
            "open-context-draft",
        ])
        #expect(table.contains("reveal\trevealPath\tReveal in Finder\t/Applications/Fixture.app"))
        #expect(table.contains("copy-path\tcopyText\tCopy Path\t/Applications/Fixture.app"))
        #expect(table.contains("open-context-draft\topenTerminalCommand\tOpen Context Draft in CLI\tInteractive CLI draft"))
        #expect(json.contains("\"id\" : \"reveal\""))
        #expect(json.contains("\"id\" : \"copy-path\""))
        #expect(json.contains("\"id\" : \"open-context-draft\""))
        #expect(!json.contains("\"id\" : \"copy-launcher-command\""))
        #expect(!json.contains("\"id\" : \"save-command-alias\""))
    }

    @Test
    func commandDetailJSONIncludesPreviewPrimaryActionAndFeaturedActions() throws {
        let promptCommand = LauncherPromptCommand(
            id: "review",
            title: "Review Workspace",
            keywords: ["review"],
            promptTemplate: "Review {query}\nWorkspace: {workspace}\nClipboard: {clipboard}"
        )
        let command = try #require(LauncherPromptCommandIndex.commands(for: [promptCommand]).first)
        let query = "Review Workspace staged diff"
        let context = LauncherContextSnapshot(workingDirectory: "/Users/f/project")
        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: query,
            clipboard: "diff --git",
            context: context,
            workingDirectory: "/Users/f/project"
        )
        let record = LauncherCommandDetailExportRecord(
            command: command,
            preview: LauncherCommandPreview.text(
                for: command,
                query: query,
                clipboard: "diff --git",
                context: context,
                workingDirectory: "/Users/f/project"
            ),
            featuredActions: LauncherActionCatalog.featuredActions(from: actions),
            query: query,
            workingDirectory: "/Users/f/project"
        )

        let json = try LauncherCommandDetailExport.json(for: record)
        let text = LauncherCommandDetailExport.text(for: record)

        #expect(json.contains("\"id\" : \"prompt:review\""))
        #expect(json.contains("\"primaryActionTitle\" : \"Run Prompt\""))
        #expect(json.contains("\"launcherURL\" : \"kwwk:\\/\\/launcher?query=staged%20diff&command=prompt:review&run=1&cwd=\\/Users\\/f\\/project\""))
        #expect(json.contains("Review staged diff"))
        #expect(json.contains("Workspace: \\/Users\\/f\\/project"))
        #expect(json.contains("Clipboard: diff --git"))
        #expect(json.contains("\"featuredActions\""))
        #expect(json.contains("\"id\" : \"copy-prompt\""))
        #expect(json.contains("\"id\" : \"open-terminal\""))
        #expect(text.contains("launcherURL: kwwk://launcher?query=staged%20diff&command=prompt:review&run=1&cwd=/Users/f/project"))
        #expect(text.contains("open-terminal: Open in Terminal [openTerminalCommand]"))
        #expect(text.contains("kwwk launcher --command prompt:review --action open-terminal --run -- 'staged diff'"))
    }

    @Test
    func actionJSONIncludesRenderedWorkspaceContextForPromptCommands() throws {
        let promptCommand = LauncherPromptCommand(
            id: "review",
            title: "Review Workspace",
            keywords: ["review"],
            promptTemplate: "Review {query}\nWorkspace: {workspace}\nCWD: {cwd}"
        )
        let command = try #require(LauncherPromptCommandIndex.commands(for: [promptCommand]).first)

        let json = try LauncherActionExport.json(
            for: LauncherActionCatalog.actions(
                for: command,
                isFavorite: false,
                query: "Review Workspace changed files",
                context: LauncherContextSnapshot(workingDirectory: "/Users/f/project"),
                workingDirectory: "/Users/f/project"
            ),
            command: command,
            query: "Review Workspace changed files"
        )

        #expect(json.contains("\"id\" : \"ask-kwwk\""))
        #expect(json.contains("Rendered prompt:"))
        #expect(json.contains("Review changed files"))
        #expect(json.contains("Workspace: \\/Users\\/f\\/project"))
        #expect(json.contains("CWD: \\/Users\\/f\\/project"))
    }

    @Test
    func actionExportReplaysDynamicCommandInput() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "web swift package manager").first)
        let copyURL = try #require(LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "web swift package manager"
        ).first { $0.id == "copy-url" })

        let record = try #require(LauncherActionExport.records(
            for: [copyURL],
            command: command,
            query: "web swift package manager"
        ).first)

        #expect(record.launcherCommand == "kwwk launcher --command 'web-search:swift package manager' --action copy-url --run -- 'web swift package manager'")
    }

    @Test
    func actionExportReplaysScriptInputPlaceholder() throws {
        let script = LauncherScriptCommand(
            id: "summarize",
            title: "Summarize Repo",
            subtitle: "Run local automation",
            scriptPath: "/Users/f/.kwwk/launcher/commands/summarize.zsh",
            argumentMode: .argument
        )
        let command = try #require(LauncherScriptCommandIndex.commands(for: [script]).first)
        let copy = try #require(LauncherActionCatalog.actions(for: command, isFavorite: false)
            .first { $0.id == "copy-launcher-command" })

        let record = try #require(LauncherActionExport.records(for: [copy], command: command).first)

        #expect(record.launcherCommand == """
        kwwk launcher --command script:summarize --action copy-launcher-command --run -- '<query>'
        """)
    }

    @Test
    func actionJSONIncludesSaveScriptPayloads() throws {
        let command = try #require(LauncherShellCommandFactory.commands(for: "$ git status --short").first)

        let json = try LauncherActionExport.json(
            for: LauncherActionCatalog.actions(for: command, isFavorite: false),
            command: command,
            query: "$ git status --short"
        )

        #expect(json.contains("\"id\" : \"save-script-command\""))
        #expect(json.contains("\"kind\" : \"saveScriptCommand\""))
        #expect(json.contains("\"value\" : \"git status --short\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command 'shell:git status --short' --action save-script-command --run -- '$ git status --short'\""))
        #expect(json.contains("\"id\" : \"save-workflow\""))
        #expect(json.contains("\"kind\" : \"saveWorkflow\""))
        #expect(json.contains("\"value\" : \"kwwk workflow saved-git-status-short -- '<query>'\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command 'shell:git status --short' --action save-workflow --run -- '$ git status --short'\""))
    }

    @Test
    func actionJSONIncludesSaveQuicklinkPayloads() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "https://example.com/docs").first)

        let json = try LauncherActionExport.json(
            for: LauncherActionCatalog.actions(
                for: command,
                isFavorite: false,
                query: "https://example.com/docs"
            ),
            command: command,
            query: "https://example.com/docs"
        )

        #expect(json.contains("\"id\" : \"save-quicklink\""))
        #expect(json.contains("\"kind\" : \"saveQuicklink\""))
        #expect(json.contains("\"value\" : \"https:\\/\\/example.com\\/docs\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command open-url:https:\\/\\/example.com\\/docs --action save-quicklink --run -- https:\\/\\/example.com\\/docs\""))
    }

    @Test
    func actionJSONIncludesSaveQuicklinkPayloadsForDynamicSearch() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "web swift package manager").first)

        let json = try LauncherActionExport.json(
            for: LauncherActionCatalog.actions(
                for: command,
                isFavorite: false,
                query: "web swift package manager"
            ),
            command: command,
            query: "web swift package manager"
        )

        #expect(json.contains("\"id\" : \"save-quicklink\""))
        #expect(json.contains("\"kind\" : \"saveQuicklink\""))
        #expect(json.contains("\"value\" : \"https:\\/\\/duckduckgo.com\\/?q=swift%20package%20manager\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command 'web-search:swift package manager' --action save-quicklink --run -- 'web swift package manager'\""))
    }

    @Test
    func actionJSONIncludesSavePromptPayloadsForDynamicPrompts() throws {
        let command = try #require(LauncherDynamicCommandFactory.commands(
            for: "summarize current project"
        ).first)

        let json = try LauncherActionExport.json(
            for: LauncherActionCatalog.actions(
                for: command,
                isFavorite: false,
                query: "summarize current project"
            ),
            command: command,
            query: "summarize current project"
        )

        #expect(json.contains("\"id\" : \"save-prompt-command\""))
        #expect(json.contains("\"kind\" : \"savePromptCommand\""))
        #expect(json.contains("\"value\" : \"summarize current project\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command 'ask-query:summarize current project' --action save-prompt-command --run -- 'summarize current project'\""))
    }

    @Test
    func actionJSONIncludesSaveSnippetPayloadsForCalculatorResults() throws {
        let command = try #require(LauncherCalculatorCommandFactory.commands(for: "=2+2").first)

        let json = try LauncherActionExport.json(
            for: LauncherActionCatalog.actions(for: command, isFavorite: false),
            command: command
        )

        #expect(json.contains("\"id\" : \"save-result-snippet\""))
        #expect(json.contains("\"kind\" : \"saveSnippet\""))
        #expect(json.contains("\"value\" : \"2+2 = 4\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command calculator:2+2 --action save-result-snippet --run -- =2+2\""))
    }

    @Test
    func actionJSONIncludesSaveSnippetPayloadsForConversionResults() throws {
        let command = try #require(LauncherUnitConversionCommandFactory.commands(for: "10 km to m").first)

        let json = try LauncherActionExport.json(
            for: LauncherActionCatalog.actions(for: command, isFavorite: false),
            command: command
        )

        #expect(json.contains("\"id\" : \"save-result-snippet\""))
        #expect(json.contains("\"kind\" : \"saveSnippet\""))
        #expect(json.contains("\"value\" : \"10 km = 10000 m\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command 'convert:10 km to m' --action save-result-snippet --run -- '10 km to m'\""))
    }

    @Test
    func actionJSONDistinguishesCLIContextOutputAndAskPrompt() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try LauncherCLIContextStore.saveStdinContext(
            "swift test failed\nExpected ok\n",
            name: "Focused Test",
            id: "11111111-2222-3333-4444-555555555555",
            directory: directory
        )
        let record = try #require(LauncherCLIContextIndex.record(for: url))
        let command = try #require(LauncherCLIContextIndex.commands(for: [record])
            .first { $0.id.hasPrefix(LauncherCLIContextIndex.commandPrefix) })

        let records = LauncherActionExport.records(
            for: LauncherActionCatalog.actions(for: command, isFavorite: false),
            command: command
        )
        let copyOutput = try #require(records.first { $0.id == "copy-context" })
        let copyPrompt = try #require(records.first { $0.id == "copy-context-prompt" })
        let commandPrefix = "kwwk launcher --command \(command.id)"

        #expect(copyOutput.title == "Copy Captured Output")
        #expect(copyOutput.kind == "copyText")
        #expect(copyOutput.value == "swift test failed\nExpected ok")
        #expect(copyOutput.launcherCommand == "\(commandPrefix) --action copy-context --run")
        #expect(copyPrompt.title == "Copy Ask Prompt")
        #expect(copyPrompt.kind == "copyText")
        #expect(copyPrompt.value == record.askPrompt)
        #expect(copyPrompt.launcherCommand == "\(commandPrefix) --action copy-context-prompt --run")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
