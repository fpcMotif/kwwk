import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher saved artifact summaries")
struct LauncherSavedArtifactSummaryTests {
    @Test
    func promptCommandSummaryIncludesPathCommandIdAndLauncherReplay() {
        let prompt = LauncherPromptCommand(
            id: "review-code",
            title: "Review Code",
            promptTemplate: "Review {query}"
        )
        let path = URL(fileURLWithPath: "/tmp/kwwk/prompts.json")

        let text = LauncherSavedArtifactSummary.text(promptCommand: prompt, path: path)

        #expect(text == """
        Review Code

        Saved to:
        /tmp/kwwk/prompts.json

        Command ID:
        prompt:review-code

        Launcher command:
        kwwk launcher --command prompt:review-code --run -- '<query>'

        Launcher URL:
        kwwk://launcher?command=prompt:review-code
        """)
    }

    @Test
    func snippetQuicklinkAliasAndScriptSummariesExposeReplayCommandsAndURLs() {
        let snippet = LauncherSnippet(
            id: "thanks",
            title: "Thanks",
            textTemplate: "Thanks, {query}."
        )
        let quicklink = LauncherQuicklink(
            id: "docs",
            title: "Docs",
            urlTemplate: "https://example.com?q={query}"
        )
        let alias = LauncherCommandAlias(
            id: "term",
            title: "Terminal Here",
            targetCommandId: "open-cli"
        )
        let script = LauncherScriptCommand(
            id: "deploy",
            title: "Deploy",
            subtitle: "Run deploy script",
            scriptPath: "/tmp/kwwk/commands/deploy.zsh",
            argumentMode: .argument
        )

        #expect(LauncherSavedArtifactSummary.text(
            snippet: snippet,
            path: URL(fileURLWithPath: "/tmp/kwwk/snippets.json")
        ).contains("kwwk launcher --command snippet:thanks --run -- '<query>'"))
        #expect(LauncherSavedArtifactSummary.text(
            snippet: snippet,
            path: URL(fileURLWithPath: "/tmp/kwwk/snippets.json")
        ).contains("Launcher URL:\nkwwk://launcher?command=snippet:thanks"))
        #expect(LauncherSavedArtifactSummary.text(
            quicklink: quicklink,
            path: URL(fileURLWithPath: "/tmp/kwwk/quicklinks.json")
        ).contains("Command ID:\nquicklink:docs"))
        #expect(LauncherSavedArtifactSummary.text(
            quicklink: quicklink,
            path: URL(fileURLWithPath: "/tmp/kwwk/quicklinks.json")
        ).contains("Launcher URL:\nkwwk://launcher?command=quicklink:docs"))
        #expect(LauncherSavedArtifactSummary.text(
            alias: alias,
            path: URL(fileURLWithPath: "/tmp/kwwk/aliases.json")
        ).contains("kwwk launcher --command alias:term --run"))
        #expect(LauncherSavedArtifactSummary.text(
            alias: alias,
            path: URL(fileURLWithPath: "/tmp/kwwk/aliases.json")
        ).contains("Launcher URL:\nkwwk://launcher?command=alias:term&run=1"))
        #expect(LauncherSavedArtifactSummary.text(
            script: script,
            path: URL(fileURLWithPath: script.scriptPath)
        ).contains("kwwk launcher --command script:deploy --run -- '<query>'"))
        #expect(LauncherSavedArtifactSummary.text(
            script: script,
            path: URL(fileURLWithPath: script.scriptPath)
        ).contains("Launcher URL:\nkwwk://launcher?command=script:deploy"))
    }

    @Test
    func workflowSummaryIncludesLauncherReplayAndDirectCLICommand() {
        let workflow = LauncherWorkflow(
            id: "review-and-test",
            title: "Review And Test",
            steps: [
                LauncherWorkflowStep(id: "review", title: "Review", kind: .prompt, template: "Review {query}"),
            ]
        )

        let text = LauncherSavedArtifactSummary.text(
            workflow: workflow,
            path: URL(fileURLWithPath: "/tmp/kwwk/workflows.json")
        )

        #expect(text.contains("Command ID:\nworkflow:review-and-test"))
        #expect(text.contains("Launcher command:\nkwwk launcher --command workflow:review-and-test --run -- '<query>'"))
        #expect(text.contains("Launcher URL:\nkwwk://launcher?command=workflow:review-and-test&run=1"))
        #expect(text.contains("CLI command:\nkwwk workflow review-and-test -- '<query>'"))
    }
}
