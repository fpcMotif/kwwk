import KWWKLauncherCore
import Testing

@Suite("Launcher command preview")
struct LauncherCommandPreviewTests {
    @Test
    func promptCommandPreviewUsesRenderedLauncherContext() throws {
        let promptCommand = LauncherPromptCommand(
            id: "review",
            title: "Review Workspace",
            keywords: ["review"],
            promptTemplate: "Review {query}\nWorkspace: {workspace}\nClipboard: {clipboard}"
        )
        let command = try #require(LauncherPromptCommandIndex.commands(for: [promptCommand]).first)

        let preview = LauncherCommandPreview.text(
            for: command,
            query: "Review Workspace auth changes",
            clipboard: "diff --git",
            context: LauncherContextSnapshot(workingDirectory: "/Users/f/project")
        )

        #expect(preview.contains("Review auth changes"))
        #expect(preview.contains("Workspace: /Users/f/project"))
        #expect(preview.contains("Clipboard: diff --git"))
    }

    @Test
    func shellPreviewUsesActiveWorkingDirectory() throws {
        let command = try #require(LauncherShellCommandFactory.commands(for: "$ git status --short").first)

        let preview = LauncherCommandPreview.text(
            for: command,
            workingDirectory: "/Users/f/project"
        )

        #expect(preview == "cd /Users/f/project && git status --short")
    }

    @Test
    func aliasPreviewCarriesTargetCommandContext() {
        let target = LauncherCommandCatalog.defaults[0]
        let alias = LauncherCommandAlias(
            id: "ask",
            title: "Ask Shortcut",
            subtitle: "Alias for Ask",
            targetCommandId: target.id
        )
        let command = LauncherCommandAliasIndex.commands(
            for: [alias],
            availableCommands: [target]
        )[0]

        let preview = LauncherCommandPreview.text(
            for: command,
            availableCommands: [target]
        )

        #expect(preview.contains("Ask KWWK"))
        #expect(preview.contains("Run a headless coding-agent prompt"))
        #expect(preview.contains("Alias target: ask-kwwk"))
    }
}
