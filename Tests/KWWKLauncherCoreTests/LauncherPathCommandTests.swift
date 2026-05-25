import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher path commands")
struct LauncherPathCommandTests {
    @Test
    func createsAbsoluteFileCommand() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notes.txt")
        try writeFile(file, "notes")

        let command = try #require(LauncherPathCommandFactory.commands(for: file.path).first)
        let target = LauncherPathCommandTarget(path: file.path, displayPath: file.path, isDirectory: false)

        #expect(command.id == "path:\(target.path)")
        #expect(command.title == "Open notes.txt")
        #expect(command.subtitle == target.displayPath)
        #expect(command.systemImage == "doc.text")
        #expect(command.category == .workspace)
        #expect(command.action == .openPath(target))
    }

    @Test
    func resolvesRelativePathsFromWorkingDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Sources/App/main.swift")
        try writeFile(file, "swift")

        let command = try #require(LauncherPathCommandFactory.commands(
            for: "./Sources/App/main.swift",
            workingDirectory: root.path
        ).first)
        let target = LauncherPathCommandTarget(
            path: file.path,
            displayPath: "./Sources/App/main.swift",
            isDirectory: false
        )

        #expect(command.id == "path:\(target.path)")
        #expect(command.subtitle == "./Sources/App/main.swift")
        #expect(command.action == .openPath(target))
    }

    @Test
    func createsDirectoryCommand() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let command = try #require(LauncherPathCommandFactory.commands(
            for: "./Docs",
            workingDirectory: root.path
        ).first)
        let target = LauncherPathCommandTarget(path: directory.path, displayPath: "./Docs", isDirectory: true)

        #expect(command.title == "Open Docs")
        #expect(command.systemImage == "folder")
        #expect(command.action == .openPath(target))
        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Open")
    }

    @Test
    func ignoresBareFileNames() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("Package.swift"), "package")

        #expect(LauncherPathCommandFactory.commands(
            for: "Package.swift",
            workingDirectory: root.path
        ).isEmpty)
    }

    @Test
    func explicitPathRanksBeforeDynamicAsk() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notes path file.txt")
        try writeFile(file, "notes")
        let query = "./notes path file.txt"
        let commands = LauncherPathCommandFactory.commands(for: query, workingDirectory: root.path)
            + LauncherDynamicCommandFactory.commands(for: query)

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id.hasPrefix(LauncherPathCommandFactory.commandPrefix) == true)
    }

    @Test
    func actionCatalogExportsReusableAbsolutePathCommand() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("README.md")
        try writeFile(file, "readme")

        let command = try #require(LauncherPathCommandFactory.commands(
            for: "./README.md",
            workingDirectory: root.path
        ).first)
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)
        let launcherCommand = LauncherActionCatalog.launcherCommand(for: command)

        #expect(actions.map(\.id).contains("ask-path"))
        #expect(actions.map(\.id).contains("reveal"))
        #expect(actions.map(\.id).contains("copy-path"))
        #expect(launcherCommand.contains("--command"))
        #expect(launcherCommand.contains("path:\(file.path)"))
        #expect(launcherCommand.contains("--run --"))
        #expect(launcherCommand.contains(file.path))
    }

    @Test
    func pathAskPromptBuilderCombinesUserRequestAndLocalContext() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("README.md")
        try writeFile(file, "# Project\nLauncher details")

        let prompt = try #require(LauncherPathAskPromptBuilder.prompt(
            pathArgument: "./README.md",
            request: "summarize this file",
            workingDirectory: root.path
        ))

        #expect(prompt.contains("User request:\nsummarize this file"))
        #expect(prompt.contains("File: ./README.md"))
        #expect(prompt.contains("# Project"))
        #expect(prompt.contains("Launcher details"))
    }

    @Test
    func pathAskPromptBuilderReturnsDefaultPathPromptWithoutUserRequest() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("README.md"), "readme")

        let prompt = try #require(LauncherPathAskPromptBuilder.prompt(
            pathArgument: "./README.md",
            workingDirectory: root.path
        ))

        #expect(prompt.hasPrefix("Use this local path as context."))
        #expect(!prompt.contains("User request:"))
    }

    @Test
    func workspaceScopeKeepsExplicitPathCommand() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("README.md")
        try writeFile(file, "readme")
        let query = "@workspace ./README.md"
        let commands = LauncherPathCommandFactory.commands(for: query, workingDirectory: root.path)
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id.hasPrefix(LauncherPathCommandFactory.commandPrefix) == true)
        #expect(results.allSatisfy { $0.category == .workspace })
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL, _ text: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
