import KWWKLauncherCore
import Testing

@Suite("Launcher context commands")
struct LauncherContextTests {
    @Test
    func emptyContextDoesNotCreateCommands() {
        let commands = LauncherContextCommandFactory.commands(for: LauncherContextSnapshot())

        #expect(commands.isEmpty)
    }

    @Test
    func workspaceContextCreatesAskCommand() throws {
        let commands = LauncherContextCommandFactory.commands(for: LauncherContextSnapshot(
            workingDirectory: "/Users/f/project"
        ))

        let command = try #require(commands.first { $0.id == "context:workspace" })

        #expect(command.title == "Ask About Workspace")
        #expect(command.category == .ai)
        #expect(command.keywords.contains("/Users/f/project"))
        #expect(command.action == .askContext(.workspace))
    }

    @Test
    func finderSelectionContextCreatesAskCommand() throws {
        let commands = LauncherContextCommandFactory.commands(for: LauncherContextSnapshot(
            finderSelectionPaths: ["/Users/f/a.txt", "/Users/f/b.txt"]
        ))

        let command = try #require(commands.first { $0.id == "context:finder-selection" })

        #expect(command.title == "Ask About Finder Selection")
        #expect(command.subtitle == "2 items selected in Finder")
        #expect(command.action == .askContext(.finderSelection))
    }

    @Test
    func desktopPromptIncludesAllAvailableContext() {
        let snapshot = LauncherContextSnapshot(
            workingDirectory: "/Users/f/project",
            finderSelectionPaths: ["/Users/f/project/Package.swift"],
            frontmostApplicationName: "Finder"
        )

        let prompt = LauncherContextPromptBuilder.prompt(
            for: .desktop,
            query: "what should I do next?",
            context: snapshot
        )

        #expect(prompt.contains("User request:\nwhat should I do next?"))
        #expect(prompt.contains("- Frontmost app: Finder"))
        #expect(prompt.contains("- Working directory: /Users/f/project"))
        #expect(prompt.contains("  - /Users/f/project/Package.swift"))
    }

    @Test
    func duplicateFinderPathsAreCollapsed() {
        let snapshot = LauncherContextSnapshot(
            finderSelectionPaths: ["/Users/f/a.txt", "/Users/f/./a.txt"]
        )

        #expect(snapshot.finderSelectionPaths == ["/Users/f/a.txt"])
    }
}
