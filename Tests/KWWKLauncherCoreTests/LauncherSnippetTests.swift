import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher snippets")
struct LauncherSnippetTests {
    @Test
    func rendersTextPlaceholdersWithLauncherContext() {
        let snippet = LauncherSnippet(
            id: "handoff",
            title: "Handoff Note",
            keywords: ["handoff"],
            textTemplate: """
            Hi {query},

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

        let rendered = snippet.renderedText(
            query: "handoff Alice",
            clipboard: "build passed",
            context: context
        )

        #expect(rendered.contains("Hi Alice,"))
        #expect(rendered.contains("build passed"))
        #expect(rendered.contains("Workspace: /Users/f/project"))
        #expect(rendered.contains("/Users/f/project/Package.swift"))
        #expect(rendered.contains("Frontmost: Ghostty"))
    }

    @Test
    func fixedTextSnippetsDoNotAppendQueryText() {
        let snippet = LauncherSnippet(
            id: "thanks",
            title: "Thanks",
            textTemplate: "Thanks, I will take a look."
        )

        #expect(snippet.renderedText(query: "anything") == "Thanks, I will take a look.")
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
            "id": "thanks",
            "title": "Thanks",
            "subtitle": "Short acknowledgement",
            "keywords": ["ty"],
            "text": "Thanks, {query}."
          }
        ]
        """.write(to: arrayURL, atomically: true, encoding: .utf8)

        try """
        {
          "snippets": [
            {
              "id": "handoff",
              "title": "Handoff",
              "systemImage": "text.quote",
              "template": "Next steps:\\n{clipboard}"
            }
          ]
        }
        """.write(to: documentURL, atomically: true, encoding: .utf8)

        let arraySnippet = try #require(LauncherSnippetIndex.load(from: arrayURL).first)
        let documentSnippet = try #require(LauncherSnippetIndex.load(from: documentURL).first)

        #expect(arraySnippet.id == "thanks")
        #expect(arraySnippet.textTemplate == "Thanks, {query}.")
        #expect(documentSnippet.id == "handoff")
        #expect(documentSnippet.textTemplate == "Next steps:\n{clipboard}")
    }

    @Test
    func snippetsBecomeSearchableLauncherCommands() throws {
        let snippet = LauncherSnippet(
            id: "standup",
            title: "Standup Note",
            subtitle: "Daily update",
            keywords: ["standup"],
            textTemplate: "Yesterday: {clipboard}\nToday: {query}"
        )

        let command = try #require(LauncherSnippetIndex.commands(for: [snippet]).first)

        #expect(command.id == "snippet:standup")
        #expect(command.category == .snippet)
        #expect(command.keywords.contains("snippet"))
        #expect(command.action == .copySnippet(snippet))
    }

    @Test
    func snippetExportIncludesReplayableLauncherCommands() throws {
        let snippet = LauncherSnippet(
            id: "standup",
            title: "Standup Note",
            subtitle: "Daily update",
            keywords: ["standup"],
            textTemplate: "Yesterday: {clipboard}\nToday: {query}"
        )

        let table = LauncherSnippetExport.table(for: [snippet])
        let json = try LauncherSnippetExport.json(for: snippet)

        #expect(table == """
        standup\tStandup Note\tDaily update\tYesterday: {clipboard} Today: {query}\tkwwk launcher --command snippet:standup --run -- '<query>'
        """)
        #expect(json.contains("\"commandId\" : \"snippet:standup\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command snippet:standup --run -- '<query>'\""))
        #expect(json.contains("\"launcherURL\" : \"kwwk:\\/\\/launcher?command=snippet:standup\""))
        #expect(json.contains("\"textTemplate\" : \"Yesterday: {clipboard}\\nToday: {query}\""))
        #expect(LauncherSnippetExport.launcherURL(
            for: snippet,
            query: "standup shipped launcher URLs",
            workingDirectory: "/Users/f/project"
        ) == "kwwk://launcher?query=shipped%20launcher%20URLs&command=snippet:standup&run=1&cwd=/Users/f/project")
    }

    @Test
    func clipboardHistoryRecordsBecomeReusableSnippets() {
        let record = LauncherClipboardHistoryRecord(
            id: "abc",
            text: "Release handoff\nShip the launcher"
        )

        let snippet = LauncherSnippetIndex.snippet(from: record)

        #expect(snippet.id == "clipboard-abc")
        #expect(snippet.title == "Release handoff")
        #expect(snippet.subtitle == "Saved from clipboard history")
        #expect(snippet.keywords.contains("clipboard"))
        #expect(snippet.textTemplate == "Release handoff\nShip the launcher")
    }

    @Test
    func aiHistoryAnswersBecomeReusableSnippets() throws {
        let record = AIRunHistoryRecord(
            id: "abc",
            prompt: "Draft release note",
            output: "Ship the launcher.\nAdd CLI replay.",
            exitCode: 0,
            command: "kwwk -p -"
        )

        let snippet = try #require(LauncherSnippetIndex.snippet(fromAIHistoryOutput: record))

        #expect(snippet.id == "ai-output-abc")
        #expect(snippet.title == "Ship the launcher.")
        #expect(snippet.subtitle == "Saved from AI answer")
        #expect(snippet.keywords.contains("ai"))
        #expect(snippet.textTemplate == "Ship the launcher.\nAdd CLI replay.")
    }

    @Test
    func failedAIHistoryErrorsBecomeReusableSnippets() throws {
        let record = AIRunHistoryRecord(
            id: "failed",
            prompt: "Fix build",
            output: "",
            errorOutput: "Build failed at Package.swift",
            exitCode: 1,
            command: "kwwk -p -"
        )

        let snippet = try #require(LauncherSnippetIndex.snippet(fromAIHistoryOutput: record))

        #expect(snippet.id == "ai-output-failed")
        #expect(snippet.title == "Build failed at Package.swift")
        #expect(snippet.subtitle == "Saved from AI error")
        #expect(snippet.keywords.contains("error"))
        #expect(!snippet.keywords.contains("answer"))
        #expect(snippet.textTemplate == "Build failed at Package.swift")
    }

    @Test
    func cliContextRecordsBecomeReusableSnippets() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("focused-test-11111111-2222-3333-4444-555555555555.txt")
        try "Swift test failed\nExpected ok\n".write(to: url, atomically: true, encoding: .utf8)
        let record = LauncherCLIContextRecord(
            id: "focused-test-11111111-2222-3333-4444-555555555555",
            title: "Focused Test",
            path: url.path,
            byteCount: 30
        )

        let snippet = try #require(LauncherSnippetIndex.snippet(from: record))

        #expect(snippet.id == "cli-context-\(record.id)")
        #expect(snippet.title == "Swift test failed")
        #expect(snippet.subtitle == "Saved from terminal context")
        #expect(snippet.systemImage == "terminal")
        #expect(snippet.keywords.contains("cli context"))
        #expect(snippet.textTemplate == "Swift test failed\nExpected ok")
    }

    @Test
    func visibleLauncherOutputBecomesReusableSnippet() throws {
        let snippet = try #require(LauncherSnippetIndex.snippet(
            fromLauncherOutput: "\nShip the launcher.\nAdd CLI replay.\n",
            sourceTitle: "Ask KWWK",
            sourceId: "ask-kwwk"
        ))

        #expect(snippet.id == "launcher-output-ask-kwwk-ship-the-launcher-add-cli-replay")
        #expect(snippet.title == "Ship the launcher.")
        #expect(snippet.subtitle == "Saved from Ask KWWK")
        #expect(snippet.keywords.contains("result"))
        #expect(snippet.keywords.contains("Ask KWWK"))
        #expect(snippet.textTemplate == "Ship the launcher.\nAdd CLI replay.")
    }

    @Test
    func blankLauncherOutputDoesNotBecomeSnippet() {
        #expect(LauncherSnippetIndex.snippet(fromLauncherOutput: " \n\t ") == nil)
    }

    @Test
    func calculatorResultsBecomeReusableSnippets() {
        let result = LauncherCalculatorResult(expression: "2+2", value: 4, formattedValue: "4")

        let snippet = LauncherSnippetIndex.snippet(from: result)

        #expect(snippet.id == "calculator-2-2")
        #expect(snippet.title == "2+2 = 4")
        #expect(snippet.subtitle == "Saved calculator result")
        #expect(snippet.systemImage == "function")
        #expect(snippet.keywords.contains("calculator"))
        #expect(snippet.textTemplate == "2+2 = 4")
    }

    @Test
    func conversionResultsBecomeReusableSnippets() {
        let result = LauncherUnitConversionResult(
            expression: "10 km to m",
            inputValue: 10,
            inputUnit: "km",
            outputValue: 10_000,
            outputUnit: "m",
            formattedInput: "10 km",
            formattedOutput: "10000 m"
        )

        let snippet = LauncherSnippetIndex.snippet(from: result)

        #expect(snippet.id == "conversion-10-km-to-m")
        #expect(snippet.title == "10 km = 10000 m")
        #expect(snippet.subtitle == "Saved unit conversion")
        #expect(snippet.systemImage == "arrow.left.arrow.right")
        #expect(snippet.keywords.contains("conversion"))
        #expect(snippet.textTemplate == "10 km = 10000 m")
    }

    @Test
    func upsertWritesAndReplacesSnippets() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snippets.json")
        let first = LauncherSnippet(
            id: "clipboard-abc",
            title: "Old Clipboard",
            textTemplate: "old"
        )
        let replacement = LauncherSnippet(
            id: "clipboard-abc",
            title: "New Clipboard",
            textTemplate: "new"
        )

        try LauncherSnippetIndex.upsert(first, to: url)
        try LauncherSnippetIndex.upsert(replacement, to: url)

        let snippets = LauncherSnippetIndex.load(from: url)
        #expect(snippets.count == 1)
        #expect(snippets.first?.title == "New Clipboard")
        #expect(snippets.first?.textTemplate == "new")
    }

    @Test
    func actionCatalogExposesSnippetActionsAndCLIReplay() throws {
        let snippet = LauncherSnippet(
            id: "thanks",
            title: "Thanks",
            keywords: ["ty"],
            textTemplate: "Thanks, {query}."
        )
        let command = try #require(LauncherSnippetIndex.commands(for: [snippet]).first)

        let actions = LauncherActionCatalog.actions(
            for: command,
            isFavorite: false,
            query: "ty Alice"
        )

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Copy")
        #expect(actions.first { $0.id == "copy-snippet" }?.kind == .copyText("Thanks, Alice."))
        #expect(actions.first { $0.id == "copy-template" }?.kind == .copyText("Thanks, {query}."))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command snippet:thanks --run -- Alice"
        ))
    }

    @Test
    func snippetFileCommandsExposeExpectedPrimaryTitles() throws {
        let reveal = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reveal-snippets" })
        let reload = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reload-snippets" })

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
