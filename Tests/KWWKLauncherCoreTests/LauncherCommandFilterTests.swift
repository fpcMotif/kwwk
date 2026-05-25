import KWWKLauncherCore
import Testing

@Suite("Launcher command filter")
struct LauncherCommandFilterTests {
    @Test
    func ranksExactTitleBeforeKeywordMatches() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "KWWK Login")

        #expect(results.first?.id == "login")
    }

    @Test
    func findsCliCommandsByIntent() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "terminal agent")

        #expect(results.first?.id == "open-cli")
    }

    @Test
    func recognizesPromptLikeQueries() {
        #expect(LauncherCommandFilter.looksLikePrompt("?summarize this repo"))
        #expect(LauncherCommandFilter.looksLikePrompt("summarize the current module"))
        #expect(!LauncherCommandFilter.looksLikePrompt("login"))
    }

    @Test
    func stripsQuestionPromptPrefix() {
        #expect(LauncherCommandFilter.promptText(from: "?  explain Package.swift") == "explain Package.swift")
    }

    @Test
    func stripsScopePrefixFromPromptText() {
        #expect(LauncherCommandFilter.promptText(from: "@ai ? explain Package.swift") == "explain Package.swift")
        #expect(LauncherCommandFilter.promptText(from: "@workspace Package.swift") == "Package.swift")
    }

    @Test
    func scopePrefixFiltersCommandsByCategory() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "@cli")

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .cli })
    }

    @Test
    func clipboardScopeFiltersClipboardCommands() throws {
        let record = LauncherClipboardHistoryRecord(text: "Release notes draft")
        let command = try #require(LauncherClipboardHistoryCommandFactory.commands(
            for: LauncherClipboardHistory(records: [record])
        ).first { $0.id == "clipboard:\(record.id)" })

        let results = LauncherCommandFilter.filter(
            [command] + LauncherCommandCatalog.defaults,
            query: "@clipboard release"
        )

        #expect(results.first?.id == "clipboard:\(record.id)")
        #expect(results.allSatisfy { $0.category == .clipboard })
    }

    @Test
    func snippetScopeFiltersSnippetCommands() throws {
        let snippet = LauncherSnippet(
            id: "standup",
            title: "Standup Note",
            textTemplate: "Yesterday: {clipboard}\nToday: {query}"
        )
        let command = try #require(LauncherSnippetIndex.commands(for: [snippet]).first)

        let results = LauncherCommandFilter.filter(
            [command] + LauncherCommandCatalog.defaults,
            query: "@snippets standup"
        )

        #expect(results.first?.id == "snippet:standup")
        #expect(results.allSatisfy { $0.category == .snippet })
    }

    @Test
    func dynamicAskCommandRanksForNaturalLanguagePrompt() {
        let commands = LauncherDynamicCommandFactory.commands(for: "summarize the current module")
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: "summarize the current module")

        #expect(results.first?.id == "ask-query:summarize the current module")
        #expect(results.first?.action == .askPrompt("summarize the current module"))
    }

    @Test
    func dynamicAskCommandHandlesQuestionPrefix() {
        let commands = LauncherDynamicCommandFactory.commands(for: "? summarize the current module")
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: "? summarize the current module")

        #expect(results.first?.id == "ask-query:summarize the current module")
    }

    @Test
    func scopedDynamicAskCommandUsesCleanPromptText() {
        let query = "@ai summarize the current module"
        let commands = LauncherDynamicCommandFactory.commands(for: query)
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "ask-query:summarize the current module")
        #expect(results.first?.action == .askPrompt("summarize the current module"))
        #expect(results.allSatisfy { $0.category == .ai })
    }

    @Test
    func explicitMultiwordPresetTriggerBeatsDynamicAskCommand() {
        let query = "shell command list large files"
        let commands = LauncherDynamicCommandFactory.commands(for: query)
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "ai-preset:shell-command")
    }

    @Test
    func scopePrefixKeepsRankingInsideCategory() {
        let query = "@ai shell command list large files"
        let commands = LauncherDynamicCommandFactory.commands(for: query)
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "ai-preset:shell-command")
        #expect(results.allSatisfy { $0.category == .ai })
    }

    @Test
    func shellPrefixCreatesRunnableShellCommand() throws {
        let command = try #require(LauncherShellCommandFactory.commands(for: "$ git status --short").first)

        #expect(command.id == "shell:git status --short")
        #expect(command.title == "Run Shell Command")
        #expect(command.category == .cli)
        #expect(command.action == .runShellCommand("git status --short"))
    }

    @Test
    func shellCommandRanksBeforeDynamicAsk() {
        let query = "$ git status --short"
        let commands = LauncherShellCommandFactory.commands(for: query)
            + LauncherDynamicCommandFactory.commands(for: query)
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "shell:git status --short")
    }

    @Test
    func scopedShellCommandCanBeCreatedUnderCliScope() throws {
        let query = "@cli $ git status --short"
        let command = try #require(LauncherShellCommandFactory.commands(for: query).first)
        let commands = [command] + LauncherDynamicCommandFactory.commands(for: query) + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(command.id == "shell:git status --short")
        #expect(results.first?.id == "shell:git status --short")
        #expect(results.allSatisfy { $0.category == .cli })
    }

    @Test
    func shellFactoryIgnoresOrdinaryPrompts() {
        #expect(LauncherShellCommandFactory.commands(for: "summarize this repo").isEmpty)
        #expect(LauncherShellCommandFactory.commands(for: "$   ").isEmpty)
    }

    @Test
    func commandSectionsGroupByCategoryAndExposeVisibleOrder() throws {
        let shell = try #require(LauncherShellCommandFactory.commands(for: "$ git status --short").first)
        let prompt = try #require(LauncherDynamicCommandFactory.commands(for: "summarize the current module").first)
        let login = try #require(LauncherCommandCatalog.defaults.first { $0.id == "login" })
        let script = LauncherScriptCommandIndex.commands(for: [
            LauncherScriptCommand(
                id: "deploy",
                title: "Deploy",
                subtitle: "Run deploy",
                scriptPath: "/tmp/deploy"
            ),
        ])[0]

        let sections = LauncherCommandSectionFactory.sections(from: [
            shell,
            prompt,
            login,
            script,
        ])

        #expect(sections.map(\.category) == [.cli, .ai, .script])
        #expect(sections.map(\.title) == ["CLI", "AI", "Scripts"])
        #expect(sections.map(\.count) == [2, 1, 1])
        #expect(sections[0].commands.map(\.id) == ["shell:git status --short", "login"])
        #expect(sections[1].commands.map(\.id) == ["ask-query:summarize the current module"])
        #expect(sections[2].commands.map(\.id) == ["script:deploy"])
        #expect(LauncherCommandSectionFactory.visibleCommands(from: [
            shell,
            prompt,
            login,
            script,
        ]).map(\.id) == [
            "shell:git status --short",
            "login",
            "ask-query:summarize the current module",
            "script:deploy",
        ])
    }

    @Test
    func scopedResultsProduceSingleVisibleSection() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "@cli terminal")
        let sections = LauncherCommandSectionFactory.sections(from: results)

        #expect(!results.isEmpty)
        #expect(sections.map(\.category) == [.cli])
        #expect(sections.first?.commands == results)
    }
}
