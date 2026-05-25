import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher local path context")
struct LauncherLocalPathContextTests {
    @Test
    func textFileContextIncludesBoundedContentExcerpt() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Notes.md")
        try writeFile(file, "# Notes\nUseful launch context")

        let context = try #require(LauncherLocalPathContextBuilder.promptContext(
            for: file.path,
            displayPath: "Notes.md"
        ))

        #expect(context.contains("File content excerpt (Notes.md):"))
        #expect(context.contains("# Notes"))
        #expect(context.contains("Useful launch context"))
    }

    @Test
    func largeFileContextIsOmittedWithSizeNote() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large.txt")
        try writeFile(file, String(repeating: "x", count: 32))

        let context = try #require(LauncherLocalPathContextBuilder.promptContext(
            for: file.path,
            displayPath: "large.txt",
            maxBytes: 8
        ))

        #expect(context.contains("File content omitted"))
        #expect(context.contains("above the 8-byte launcher prompt limit"))
    }

    @Test
    func binaryFileContextIsOmitted() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("image.bin")
        try Data([0, 1, 2, 3]).write(to: file)

        let context = try #require(LauncherLocalPathContextBuilder.promptContext(
            for: file.path,
            displayPath: "image.bin"
        ))

        #expect(context.contains("does not look like UTF-8 text"))
    }

    @Test
    func directoryContextIncludesShallowSortedListing() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("b.txt"), "b")
        try writeFile(root.appendingPathComponent("a.txt"), "a")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )

        let context = try #require(LauncherLocalPathContextBuilder.promptContext(
            for: root.path,
            displayPath: ".",
            isDirectory: true
        ))

        #expect(context.contains("Directory listing (.):"))
        #expect(context.contains("a.txt\nb.txt\nSources/"))
    }

    @Test
    func workspaceFileAskPromptIncludesReadableFileContent() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("Sources/App/main.swift")
        try writeFile(fileURL, "print(\"hello\")")
        let file = LauncherWorkspaceFile(path: fileURL.path, relativePath: "Sources/App/main.swift")

        #expect(file.askPrompt.contains("Workspace file: Sources/App/main.swift"))
        #expect(file.askPrompt.contains("print(\"hello\")"))
    }

    @Test
    func pathAskPromptIncludesDirectoryListing() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("README.md"), "readme")
        let target = LauncherPathCommandTarget(path: root.path, displayPath: ".", isDirectory: true)

        #expect(target.askPrompt.contains("Folder: ."))
        #expect(target.askPrompt.contains("Directory listing (.):"))
        #expect(target.askPrompt.contains("README.md"))
    }

    @Test
    func multiPathAskPromptCombinesBoundedContexts() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let readme = root.appendingPathComponent("README.md")
        let package = root.appendingPathComponent("Package.swift")
        try writeFile(readme, "# Project")
        try writeFile(package, "let package = Package()")

        let prompt = try #require(LauncherPathAskPromptBuilder.prompt(
            pathArguments: ["./README.md", "./Package.swift"],
            request: "compare these files",
            workingDirectory: root.path
        ))

        #expect(prompt.contains("Use the local path contexts below"))
        #expect(prompt.contains("User request:\ncompare these files"))
        #expect(prompt.contains("File: ./README.md"))
        #expect(prompt.contains("# Project"))
        #expect(prompt.contains("File: ./Package.swift"))
        #expect(prompt.contains("let package = Package()"))
    }

    @Test
    func multiPathAskPromptRejectsMissingPaths() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let readme = root.appendingPathComponent("README.md")
        try writeFile(readme, "# Project")

        #expect(LauncherPathAskPromptBuilder.prompt(
            pathArguments: ["./README.md", "./Missing.md"],
            request: "compare these files",
            workingDirectory: root.path
        ) == nil)
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
