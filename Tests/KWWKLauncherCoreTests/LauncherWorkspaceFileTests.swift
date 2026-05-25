import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher workspace files")
struct LauncherWorkspaceFileTests {
    @Test
    func scansWorkspaceFilesAndSkipsGeneratedFolders() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("Package.swift"), "package")
        try writeFile(root.appendingPathComponent("Sources/App/main.swift"), "swift")
        try writeFile(root.appendingPathComponent(".git/config"), "git")
        try writeFile(root.appendingPathComponent("node_modules/pkg/index.js"), "node")
        try writeFile(root.appendingPathComponent("dist/app"), "bin")

        let files = LauncherWorkspaceFileIndex.scan(root: root)

        #expect(files.map(\.relativePath) == [
            "Package.swift",
            "Sources/App/main.swift",
        ])
    }

    @Test
    func scanHonorsDepthAndLimit() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("a.txt"), "a")
        try writeFile(root.appendingPathComponent("b.txt"), "b")
        try writeFile(root.appendingPathComponent("nested/deep/c.txt"), "c")

        let files = LauncherWorkspaceFileIndex.scan(root: root, maxDepth: 1, limit: 1)

        #expect(files.map(\.relativePath) == ["a.txt"])
    }

    @Test
    func convertsFilesToLauncherCommands() throws {
        let file = LauncherWorkspaceFile(
            path: "/Users/f/project/Sources/App/main.swift",
            relativePath: "Sources/App/main.swift"
        )

        let command = try #require(LauncherWorkspaceFileIndex.commands(for: [file]).first)

        #expect(command.id == "workspace-file:/Users/f/project/Sources/App/main.swift")
        #expect(command.title == "main.swift")
        #expect(command.subtitle == "Sources/App/main.swift")
        #expect(command.systemImage == "curlybraces")
        #expect(command.category == .workspace)
        #expect(command.keywords.contains("Sources/App/main.swift"))
        #expect(command.action == .openWorkspaceFile(file))
    }

    @Test
    func workspaceFileAskPromptCarriesFileContext() {
        let file = LauncherWorkspaceFile(
            path: "/Users/f/project/Sources/App/main.swift",
            relativePath: "Sources/App/main.swift"
        )

        #expect(file.askPrompt.contains("Workspace file: Sources/App/main.swift"))
        #expect(file.askPrompt.contains("File path: /Users/f/project/Sources/App/main.swift"))
    }

    @Test
    func workspaceFileActionsExposeOpenAskRevealAndCopy() {
        let file = LauncherWorkspaceFile(
            path: "/Users/f/project/README.md",
            relativePath: "README.md"
        )
        let command = LauncherWorkspaceFileIndex.commands(for: [file])[0]

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Open")
        #expect(actions.map(\.id).contains("ask-file"))
        #expect(actions.map(\.id).contains("reveal"))
        #expect(actions.map(\.id).contains("copy-path"))
        #expect(actions.map(\.id).contains("copy-relative-path"))

        let ask = actions.first { $0.id == "ask-file" }
        #expect(ask?.kind == .askKWWK(file.askPrompt))
    }

    @Test
    func workspaceFilesParticipateInFiltering() {
        let file = LauncherWorkspaceFile(
            path: "/Users/f/project/Package.swift",
            relativePath: "Package.swift"
        )
        let commands = LauncherWorkspaceFileIndex.commands(for: [file])

        let results = LauncherCommandFilter.filter(commands, query: "package")

        #expect(results.first?.id == "workspace-file:/Users/f/project/Package.swift")
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
