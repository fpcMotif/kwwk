import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher prompt commands")
struct LauncherPromptCommandTests {
    @Test
    func rendersPromptPlaceholdersWithLauncherContext() {
        let command = LauncherPromptCommand(
            id: "review",
            title: "Review Diff",
            keywords: ["review"],
            promptTemplate: """
            Review {query}
            Clipboard:
            {clipboard}
            Workspace: {workspace}
            Finder:
            {finderSelection}
            Frontmost: {frontmostApp}
            """
        )
        let context = LauncherContextSnapshot(
            workingDirectory: "/Users/f/project",
            finderSelectionPaths: ["/Users/f/project/Package.swift"],
            frontmostApplicationName: "Ghostty"
        )

        let rendered = command.renderedPrompt(
            query: "review staged changes",
            clipboard: "diff --git a/file b/file",
            context: context
        )

        #expect(rendered.contains("Review staged changes"))
        #expect(rendered.contains("diff --git a/file b/file"))
        #expect(rendered.contains("Workspace: /Users/f/project"))
        #expect(rendered.contains("/Users/f/project/Package.swift"))
        #expect(rendered.contains("Frontmost: Ghostty"))
    }

    @Test
    func loadsArrayAndDocumentJSONFormats() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let arrayURL = directory.appendingPathComponent("array.json")
        let documentURL = directory.appendingPathComponent("document.json")

        try """
        [
          {
            "id": "review-diff",
            "title": "Review Diff",
            "subtitle": "Review pasted diff",
            "keywords": ["review"],
            "prompt": "Review this diff: {query}"
          }
        ]
        """.write(to: arrayURL, atomically: true, encoding: .utf8)

        try """
        {
          "prompts": [
            {
              "id": "explain-error",
              "title": "Explain Error",
              "systemImage": "exclamationmark.triangle",
              "template": "Explain this failure: {clipboard}"
            }
          ]
        }
        """.write(to: documentURL, atomically: true, encoding: .utf8)

        let arrayPrompt = try #require(LauncherPromptCommandIndex.load(from: arrayURL).first)
        let documentPrompt = try #require(LauncherPromptCommandIndex.load(from: documentURL).first)

        #expect(arrayPrompt.id == "review-diff")
        #expect(arrayPrompt.promptTemplate == "Review this diff: {query}")
        #expect(documentPrompt.id == "explain-error")
        #expect(documentPrompt.promptTemplate == "Explain this failure: {clipboard}")
    }

    @Test
    func promptCommandsBecomeSearchableLauncherCommands() throws {
        let prompt = LauncherPromptCommand(
            id: "commit-message",
            title: "Draft Commit Message",
            subtitle: "Use copied diff",
            keywords: ["commit"],
            promptTemplate: "Draft a conventional commit for {clipboard}"
        )

        let command = try #require(LauncherPromptCommandIndex.commands(for: [prompt]).first)

        #expect(command.id == "prompt:commit-message")
        #expect(command.category == .ai)
        #expect(command.keywords.contains("template"))
        #expect(command.action == .runPromptCommand(prompt))
    }

    @Test
    func promptCommandExportIncludesReplayableLauncherCommands() throws {
        let prompt = LauncherPromptCommand(
            id: "review-diff",
            title: "Review Diff",
            subtitle: "Use copied diff",
            keywords: ["review"],
            promptTemplate: "Review {query}"
        )

        let table = LauncherPromptCommandExport.table(for: [prompt])
        let json = try LauncherPromptCommandExport.json(for: prompt)

        #expect(table == """
        review-diff\tReview Diff\tUse copied diff\tReview {query}\tkwwk launcher --command prompt:review-diff --run -- '<query>'
        """)
        #expect(json.contains("\"commandId\" : \"prompt:review-diff\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command prompt:review-diff --run -- '<query>'\""))
        #expect(json.contains("\"launcherURL\" : \"kwwk:\\/\\/launcher?command=prompt:review-diff\""))
        #expect(json.contains("\"promptTemplate\" : \"Review {query}\""))
        #expect(LauncherPromptCommandExport.launcherURL(
            for: prompt,
            query: "review staged changes",
            workingDirectory: "/Users/f/project"
        ) == "kwwk://launcher?query=staged%20changes&command=prompt:review-diff&run=1&cwd=/Users/f/project")
    }

    @Test
    func aiHistoryRecordsBecomeReusablePromptCommands() {
        let record = AIRunHistoryRecord(
            id: "abc",
            prompt: "Review this module",
            output: "Looks solid",
            exitCode: 0,
            model: "gpt-5.4",
            command: "kwwk -p -"
        )

        let prompt = LauncherPromptCommandIndex.promptCommand(from: record)

        #expect(prompt.id == "history-abc")
        #expect(prompt.title == "Review this module")
        #expect(prompt.subtitle == "Saved from AI history")
        #expect(prompt.keywords.contains("history"))
        #expect(prompt.promptTemplate == "Review this module")
    }

    @Test
    func oneOffPromptsBecomeReusablePromptCommands() throws {
        let prompt = try #require(LauncherPromptCommandIndex.promptCommand(
            fromPrompt: "Summarize current project and suggest next actions"
        ))

        #expect(prompt.id == "saved-summarize-current-project-and-suggest-next-actions")
        #expect(prompt.title == "Summarize Current Project And")
        #expect(prompt.subtitle == "Saved prompt")
        #expect(prompt.keywords.contains("saved"))
        #expect(prompt.keywords.contains("Summarize"))
        #expect(prompt.promptTemplate == "Summarize current project and suggest next actions")
        #expect(LauncherPromptCommandIndex.promptCommand(fromPrompt: "   ") == nil)
    }

    @Test
    func upsertWritesAndReplacesPromptCommands() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("prompts.json")

        let first = LauncherPromptCommand(
            id: "history-abc",
            title: "Review Module",
            promptTemplate: "Review this module"
        )
        let replacement = LauncherPromptCommand(
            id: "history-abc",
            title: "Review Module",
            promptTemplate: "Review this module carefully"
        )

        try LauncherPromptCommandIndex.upsert(first, to: url)
        try LauncherPromptCommandIndex.upsert(replacement, to: url)

        let prompts = LauncherPromptCommandIndex.load(from: url)
        #expect(prompts.count == 1)
        #expect(prompts.first?.promptTemplate == "Review this module carefully")
    }

    @Test
    func actionCatalogExposesPromptCommandActionsAndCLIReplay() throws {
        let prompt = LauncherPromptCommand(
            id: "review-diff",
            title: "Review Diff",
            keywords: ["review"],
            promptTemplate: "Review {query}"
        )
        let command = try #require(LauncherPromptCommandIndex.commands(for: [prompt]).first)

        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "review staged changes"
        )

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run Prompt")
        #expect(actions.first { $0.id == "copy-prompt" }?.kind == .copyText("Review staged changes"))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command prompt:review-diff --run -- 'staged changes'"
        ))
    }

    @Test
    func promptCommandFileCommandsExposeExpectedPrimaryTitles() throws {
        let reveal = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reveal-prompt-commands" })
        let reload = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reload-prompt-commands" })

        #expect(LauncherActionCatalog.primaryTitle(for: reveal) == "Reveal")
        #expect(LauncherActionCatalog.primaryTitle(for: reload) == "Reload")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
