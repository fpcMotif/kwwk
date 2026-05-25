import KWWKLauncherCore
import Testing

@Suite("Launcher web commands")
struct LauncherWebCommandTests {
    @Test
    func createsSearchWebCommandFromExplicitPrefix() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "web swift package manager").first)

        #expect(command.id == "web-search:swift package manager")
        #expect(command.title == "Search Web")
        #expect(command.subtitle == "swift package manager")
        #expect(command.category == .quicklink)

        guard case .openQuicklink(let quicklink) = command.action else {
            Issue.record("Expected quicklink action")
            return
        }

        #expect(quicklink.renderedURLString(query: "web swift package manager") == "https://duckduckgo.com/?q=swift%20package%20manager")
    }

    @Test
    func createsSearchWebCommandFromSearchWebPrefix() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "search web swift concurrency").first)

        #expect(command.id == "web-search:swift concurrency")
    }

    @Test
    func createsOpenURLCommandForHTTPAndWWWInputs() throws {
        let https = try #require(LauncherWebCommandFactory.commands(for: "https://example.com/docs?q=swift").first)
        let www = try #require(LauncherWebCommandFactory.commands(for: "www.example.com/docs").first)

        #expect(https.id == "open-url:https://example.com/docs?q=swift")
        #expect(https.title == "example.com")
        #expect(www.id == "open-url:https://www.example.com/docs")
        #expect(www.title == "www.example.com")
    }

    @Test
    func ignoresPlainNaturalLanguageAndUnsafeURLText() {
        #expect(LauncherWebCommandFactory.commands(for: "summarize this repo").isEmpty)
        #expect(LauncherWebCommandFactory.commands(for: "Package.swift").isEmpty)
        #expect(LauncherWebCommandFactory.commands(for: "https://example.com/bad path").isEmpty)
        #expect(LauncherWebCommandFactory.commands(for: "web   ").isEmpty)
    }

    @Test
    func searchWebRanksBeforeDynamicAskCommand() {
        let query = "web swift package manager"
        let commands = LauncherWebCommandFactory.commands(for: query)
            + LauncherDynamicCommandFactory.commands(for: query)
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "web-search:swift package manager")
    }

    @Test
    func scopedQuicklinkWebCommandFiltersInsideQuicklinks() throws {
        let query = "@quicklinks web swift package manager"
        let command = try #require(LauncherWebCommandFactory.commands(for: query).first)
        let commands = [command] + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "web-search:swift package manager")
        #expect(results.allSatisfy { $0.category == .quicklink })
    }

    @Test
    func webActionsCopyRenderedURLAndReplayableLauncherCommand() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "web swift package manager").first)

        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "web swift package manager"
        )

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Open")
        #expect(actions.first { $0.id == "copy-url" }?.kind == .copyText(
            "https://duckduckgo.com/?q=swift%20package%20manager"
        ))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command 'web-search:swift package manager' --run -- 'web swift package manager'"
        ))
    }

    @Test
    func urlActionsReplayTheOriginalURLQuery() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "https://example.com/docs").first)

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false, query: "https://example.com/docs")

        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command open-url:https://example.com/docs --run -- https://example.com/docs"
        ))
    }
}
