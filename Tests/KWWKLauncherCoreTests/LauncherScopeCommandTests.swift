import KWWKLauncherCore
import Testing

@Suite("Launcher scope commands")
struct LauncherScopeCommandTests {
    @Test
    func scopeCommandsExposeSearchQueries() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "scope:apps" })

        #expect(command.title == "Search Apps")
        #expect(command.category == .scope)
        #expect(command.action == .setSearchQuery("@apps "))
        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Search")
    }

    @Test
    func scopeShortcutsExposeCompactTitlesForTheLauncherStrip() {
        let shortcuts = LauncherScopeCommandCatalog.shortcuts()

        #expect(shortcuts.map(\.id) == [
            "ai",
            "cli",
            "apps",
            "scripts",
            "workspace",
            "workflows",
            "quicklinks",
            "snippets",
            "models",
        ])
        #expect(shortcuts.map(\.shortTitle) == [
            "AI",
            "CLI",
            "Apps",
            "Scripts",
            "Workspace",
            "Workflows",
            "Quicklinks",
            "Snippets",
            "Models",
        ])
    }

    @Test
    func scopeShortcutsReplaceOnlyTheLeadingScope() throws {
        let apps = try #require(LauncherScopeCommandCatalog.defaults.first { $0.id == "apps" })
        let scripts = try #require(LauncherScopeCommandCatalog.defaults.first { $0.id == "scripts" })

        #expect(LauncherScopeCommandCatalog.query(replacingScopeIn: "terminal", with: apps) == "@apps terminal")
        #expect(LauncherScopeCommandCatalog.query(replacingScopeIn: "@apps Xcode", with: scripts) == "@scripts Xcode")
        #expect(LauncherScopeCommandCatalog.query(replacingScopeIn: "@apps", with: scripts) == "@scripts ")
        #expect(LauncherScopeCommandCatalog.query(replacingScopeIn: "@scripts deploy", with: nil) == "deploy")
        #expect(LauncherScopeCommandCatalog.query(replacingScopeIn: "deploy", with: nil) == "deploy")
    }

    @Test
    func activeShortcutIdReadsTheCurrentScopePrefix() {
        #expect(LauncherScopeCommandCatalog.activeShortcutId(for: "@apps Xcode") == "apps")
        #expect(LauncherScopeCommandCatalog.activeShortcutId(for: " @quicklinks gh issue ") == "quicklinks")
        #expect(LauncherScopeCommandCatalog.activeShortcutId(for: "plain search") == nil)
        #expect(LauncherScopeCommandCatalog.activeShortcutId(for: "@unknown search") == nil)
    }

    @Test
    func scopeCommandsAreSearchableByIntent() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "search apps")

        #expect(results.first?.id == "scope:apps")
    }

    @Test
    func scopesScopeFiltersScopeCommands() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "@scopes apps")

        #expect(results.first?.id == "scope:apps")
        #expect(results.allSatisfy { $0.category == .scope })
    }

    @Test
    func scopeCommandsExportLauncherBridge() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "scope:apps" })

        #expect(LauncherActionCatalog.launcherCommand(for: command) == "kwwk launcher '@apps'")
        #expect(LauncherActionCatalog.launcherURL(for: command) == "kwwk://launcher?query=@apps")
    }

    @Test
    func copyLauncherCommandActionUsesScopeQuery() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "scope:apps" })
        let action = try #require(LauncherActionCatalog.actions(for: command, isFavorite: false)
            .first { $0.id == "copy-launcher-command" })

        guard case .copyText(let value) = action.kind else {
            Issue.record("Expected copy action")
            return
        }

        #expect(action.subtitle == "kwwk launcher '@apps'")
        #expect(value == "kwwk launcher '@apps'")
    }
}
