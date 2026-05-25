import KWWKLauncherCore
import Testing

@Suite("Launcher follow-up prompts")
struct LauncherFollowUpPromptTests {
    @Test
    func buildsFollowUpPromptFromPreviousResult() {
        let prompt = LauncherFollowUpPromptBuilder.prompt(
            request: "  turn this into a shell command  ",
            previousOutput: "\nUse ripgrep to find matching files.\n",
            sourceTitle: "Explain Search"
        )

        #expect(prompt.contains("Previous result source:\nExplain Search"))
        #expect(prompt.contains("Follow-up request:\nturn this into a shell command"))
        #expect(prompt.contains("Previous launcher result:\nUse ripgrep to find matching files."))
        #expect(prompt.contains("CLI-friendly"))
    }

    @Test
    func omitsBlankSourceTitle() {
        let prompt = LauncherFollowUpPromptBuilder.prompt(
            request: "summarize",
            previousOutput: "long output",
            sourceTitle: "  "
        )

        #expect(!prompt.contains("Previous result source:"))
        #expect(prompt.contains("Follow-up request:\nsummarize"))
    }

    @Test
    func buildsInteractiveDraftPromptFromCurrentResult() throws {
        let prompt = try #require(LauncherResultDraftPromptBuilder.prompt(
            output: "\nUse ripgrep, then run swift test.\n",
            sourceTitle: "Debug Error"
        ))

        #expect(prompt.contains("interactive CLI session"))
        #expect(prompt.contains("Launcher result source:\nDebug Error"))
        #expect(prompt.contains("Launcher result:\nUse ripgrep, then run swift test."))
    }

    @Test
    func resultDraftPromptRejectsBlankOutputAndBoundsLargeResults() throws {
        #expect(LauncherResultDraftPromptBuilder.prompt(output: "   ") == nil)

        let prompt = try #require(LauncherResultDraftPromptBuilder.prompt(
            output: "abcdef",
            maxOutputLength: 3
        ))

        #expect(prompt.contains("abc\n\n[truncated]"))
        #expect(!prompt.contains("Launcher result source:"))
    }
}
