import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher end-to-end flows")
struct LauncherEndToEndTests {
    @Test
    func promptCommandCanFlowFromPaletteQueryToInspectableReplayActions() throws {
        let prompt = LauncherPromptCommand(
            id: "review",
            title: "Review Workspace",
            keywords: ["review"],
            promptTemplate: "Review {query}\nWorkspace: {workspace}\nClipboard: {clipboard}"
        )
        let query = "Review Workspace staged diff"
        let workingDirectory = "/Users/f/project"
        let commands = LauncherDynamicCommandFactory.commands(for: query)
            + LauncherPromptCommandIndex.commands(for: [prompt])
            + LauncherCommandCatalog.defaults
        let selected = try #require(LauncherCommandFilter.filter(commands, query: query).first)
        let context = LauncherContextSnapshot(workingDirectory: workingDirectory)
        let actions = LauncherActionCatalog.actions(
            for: selected,
            isFavorite: false,
            query: query,
            clipboard: "diff --git",
            context: context,
            workingDirectory: workingDirectory
        )
        let detail = LauncherCommandDetailExportRecord(
            command: selected,
            preview: LauncherCommandPreview.text(
                for: selected,
                query: query,
                clipboard: "diff --git",
                context: context,
                workingDirectory: workingDirectory,
                availableCommands: commands
            ),
            featuredActions: LauncherActionCatalog.featuredActions(from: actions),
            query: query,
            workingDirectory: workingDirectory
        )

        #expect(selected.id == "prompt:review")
        #expect(detail.primaryActionTitle == "Run Prompt")
        #expect(detail.preview.contains("Review staged diff"))
        #expect(detail.preview.contains("Workspace: /Users/f/project"))
        #expect(detail.featuredActions.map(\.id) == ["copy-prompt", "open-terminal", "open-cli-draft"])
        #expect(detail.featuredActions[1].launcherCommand == "kwwk launcher --command prompt:review --action open-terminal --run -- 'staged diff'")
        #expect(try LauncherCommandDetailExport.json(for: detail).contains("\"featuredActions\""))
        #expect(LauncherCommandDetailExport.text(for: detail).contains("open-terminal: Open in Terminal"))
    }

    @Test
    func workspaceFileCanFlowFromScopedQueryToPreviewActionsWithoutNetwork() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let file = sources.appendingPathComponent("Demo.swift")
        try "struct Demo {}\n".write(to: file, atomically: true, encoding: .utf8)

        let files = LauncherWorkspaceFileIndex.scan(root: root)
        let commands = LauncherWorkspaceFileIndex.commands(for: files) + LauncherCommandCatalog.defaults
        let query = "@workspace Demo.swift"
        let selected = try #require(LauncherCommandFilter.filter(commands, query: query).first)
        let actions = LauncherActionCatalog.actions(
            for: selected,
            isFavorite: false,
            query: query,
            workingDirectory: root.path
        )
        let detail = LauncherCommandDetailExportRecord(
            command: selected,
            preview: LauncherCommandPreview.text(
                for: selected,
                query: query,
                workingDirectory: root.path,
                availableCommands: commands
            ),
            featuredActions: LauncherActionCatalog.featuredActions(from: actions),
            query: query,
            workingDirectory: root.path
        )

        #expect(selected.title == "Demo.swift")
        #expect(selected.category == .workspace)
        #expect(detail.preview.contains("Sources/Demo.swift"))
        #expect(actions.map(\.id).contains("ask-file"))
        #expect(actions.map(\.id).contains("copy-relative-path"))
        #expect(detail.featuredActions.map(\.id) == ["ask-file", "reveal", "copy-path"])
        #expect(detail.launcherURL.contains("command=workspace-file:"))
        #expect(detail.launcherURL.contains("cwd=\(root.path)"))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
