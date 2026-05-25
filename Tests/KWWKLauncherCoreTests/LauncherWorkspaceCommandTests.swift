import KWWKLauncherCore
import Testing

@Suite("Launcher workspace commands")
struct LauncherWorkspaceCommandTests {
    @Test
    func emptyWorkspaceDoesNotCreateCommands() {
        #expect(LauncherWorkspaceCommandFactory.commands(for: nil).isEmpty)
        #expect(LauncherWorkspaceCommandFactory.commands(for: "  ").isEmpty)
    }

    @Test
    func workspaceCommandsExposeActiveDirectory() throws {
        let commands = LauncherWorkspaceCommandFactory.commands(for: "/Users/f/project")

        #expect(commands.map(\.id) == [
            "workspace:open-cli",
            "workspace:reveal",
            "workspace:copy-path",
        ])
        #expect(commands.allSatisfy { $0.category == .workspace })

        let openCLI = try #require(commands.first)
        #expect(openCLI.title == "Open CLI Here")
        #expect(openCLI.subtitle == "Active workspace: project")
        #expect(openCLI.keywords.contains("/Users/f/project"))
        #expect(openCLI.action == .openInteractiveCLIAt("/Users/f/project"))
    }

    @Test
    func workspacePathIsStandardized() throws {
        let command = try #require(LauncherWorkspaceCommandFactory.commands(for: "/Users/f/project/../repo").first)

        #expect(command.action == .openInteractiveCLIAt("/Users/f/repo"))
        #expect(command.subtitle == "Active workspace: repo")
    }

    @Test
    func workspaceCommandsExposePathActions() throws {
        let commands = LauncherWorkspaceCommandFactory.commands(for: "/Users/f/project")
        let openCLI = try #require(commands.first { $0.id == "workspace:open-cli" })
        let reveal = try #require(commands.first { $0.id == "workspace:reveal" })
        let copy = try #require(commands.first { $0.id == "workspace:copy-path" })

        #expect(LauncherActionCatalog.primaryTitle(for: openCLI) == "Open CLI")
        #expect(LauncherActionCatalog.primaryTitle(for: reveal) == "Reveal")
        #expect(LauncherActionCatalog.primaryTitle(for: copy) == "Copy")

        let openActions = LauncherActionCatalog.actions(for: openCLI, isFavorite: false)
        let revealActions = LauncherActionCatalog.actions(for: reveal, isFavorite: false)
        let copyActions = LauncherActionCatalog.actions(for: copy, isFavorite: false)

        #expect(openActions.map(\.id).contains("reveal"))
        #expect(openActions.map(\.id).contains("copy-path"))
        #expect(revealActions.map(\.id).contains("copy-path"))
        #expect(copyActions.map(\.id).contains("reveal"))
    }
}
