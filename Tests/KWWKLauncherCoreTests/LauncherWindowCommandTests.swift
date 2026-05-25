import KWWKLauncherCore
import Testing

@Suite("Launcher window commands")
struct LauncherWindowCommandTests {
    @Test
    func exposesWindowCommandsInDefaultCatalog() throws {
        let left = try #require(LauncherCommandCatalog.defaults.first { $0.id == "window:left-half" })
        let center = try #require(LauncherCommandCatalog.defaults.first { $0.id == "window:center" })

        #expect(left.category == .window)
        #expect(left.title == "Move Window Left Half")
        #expect(left.action == .runWindowCommand(LauncherWindowCommandCatalog.windowCommands[0]))
        #expect(center.category == .window)
    }

    @Test
    func windowScopeFiltersInsideWindowCategory() {
        let results = LauncherCommandFilter.filter(
            LauncherCommandCatalog.defaults,
            query: "@window left"
        )

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .window })
        #expect(results.first?.id == "window:left-half")
    }

    @Test
    func windowActionsExposeMovePrimaryAndReplayableCommand() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "window:maximize" })
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Move")
        #expect(actions.first?.id == "primary")
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command window:maximize --run"
        ))
    }
}
