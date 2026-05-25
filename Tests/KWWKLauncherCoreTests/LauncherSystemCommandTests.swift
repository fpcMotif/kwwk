import KWWKLauncherCore
import Testing

@Suite("Launcher system commands")
struct LauncherSystemCommandTests {
    @Test
    func exposesSystemCommandsInDefaultCatalog() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "system:lock-screen" })

        #expect(command.title == "Lock Screen")
        #expect(command.category == .system)
        #expect(command.keywords.contains("system"))
        #expect(command.keywords.contains("lock"))
        #expect(command.action == .runSystemCommand(LauncherSystemCommandCatalog.systemCommands[0]))
    }

    @Test
    func systemCommandsAreSearchableByIntent() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "lock screen")

        #expect(results.first?.id == "system:lock-screen")
    }

    @Test
    func systemScopeFiltersInsideSystemCategory() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "@system settings")

        #expect(results.first?.id == "system:open-system-settings")
        #expect(results.allSatisfy { $0.category == .system })
    }

    @Test
    func systemCommandActionsExposeReusableLauncherBridge() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "system:lock-screen" })
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run")
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command system:lock-screen --run"
        ))
    }
}
