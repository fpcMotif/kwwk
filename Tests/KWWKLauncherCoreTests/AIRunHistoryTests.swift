import Foundation
import KWWKLauncherCore
import Testing

@Suite("AI run history")
struct AIRunHistoryTests {
    @Test
    func keepsNewestRecordsFirstAndAppliesLimit() {
        var history = AIRunHistory()

        history.add(record("old", at: 1), limit: 2)
        history.add(record("new", at: 3), limit: 2)
        history.add(record("middle", at: 2), limit: 2)

        #expect(history.records.map(\.prompt) == ["new", "middle"])
    }

    @Test
    func createsSearchableRerunCommands() throws {
        let history = AIRunHistory(records: [
            AIRunHistoryRecord(
                id: "abc",
                prompt: "summarize this module",
                output: "summary",
                exitCode: 0,
                createdAt: Date(timeIntervalSinceReferenceDate: 1),
                model: "gpt-5.4",
                command: "kwwk -p -"
            ),
        ])

        let command = try #require(AIRunHistoryCommandFactory.commands(for: history)
            .first { $0.id.hasPrefix(AIRunHistoryCommandFactory.commandPrefix) })

        #expect(command.id == "ai-history:abc")
        #expect(command.category == .ai)
        #expect(command.keywords.contains("gpt-5.4"))
        guard case .rerunAIHistory(let record) = command.action else {
            Issue.record("Expected AI history action")
            return
        }
        #expect(record.id == "abc")
        #expect(record.prompt == "summarize this module")
        #expect(record.output == "summary")
    }

    @Test
    func latestHistoryRecordHasStableAutomationCommand() throws {
        let history = AIRunHistory(records: [
            AIRunHistoryRecord(
                id: "older",
                prompt: "explain older output",
                output: "older answer",
                exitCode: 0,
                createdAt: Date(timeIntervalSinceReferenceDate: 1),
                model: "gpt-5.3",
                command: "kwwk -p -"
            ),
            AIRunHistoryRecord(
                id: "newer",
                prompt: "explain newest failure",
                output: "newest answer",
                exitCode: 0,
                createdAt: Date(timeIntervalSinceReferenceDate: 2),
                model: "gpt-5.4",
                command: "kwwk --thinking high -p -"
            ),
        ])

        let commands = AIRunHistoryCommandFactory.commands(for: history)
        let latest = try #require(commands.first { $0.id == AIRunHistoryCommandFactory.latestCommandId })

        #expect(commands.first?.id == AIRunHistoryCommandFactory.latestCommandId)
        #expect(latest.title == "Latest AI Run")
        #expect(latest.subtitle == "AI history - explain newest failure")
        #expect(latest.action == .rerunAIHistory(history.records[0]))
        #expect(latest.keywords.contains("latest ai history"))
        #expect(LauncherActionCatalog.primaryTitle(for: latest) == "Ask Again")
        #expect(LauncherActionCatalog.launcherCommand(for: latest) == "kwwk launcher --command latest-ai-history --run")
        #expect(LauncherCommandPreview.text(for: latest).contains("newest answer"))

        let filtered = LauncherCommandFilter.filter(
            LauncherDynamicCommandFactory.commands(for: "latest ai history") + commands,
            query: "latest ai history"
        )
        #expect(filtered.first?.id == AIRunHistoryCommandFactory.latestCommandId)
    }

    @Test
    func historyRecordsBecomeReusableWorkflowsAndSavedArtifactExports() throws {
        let record = AIRunHistoryRecord(
            id: "abc",
            prompt: "Review this module",
            output: "Looks solid",
            exitCode: 0,
            model: "gpt-5.4",
            command: "kwwk -p -"
        )
        let workflow = LauncherWorkflowIndex.workflow(from: record)
        let snippet = try #require(LauncherSnippetIndex.snippet(fromAIHistoryOutput: record))
        let workflowURL = URL(fileURLWithPath: "/tmp/kwwk-workflows.json")
        let snippetURL = URL(fileURLWithPath: "/tmp/kwwk-snippets.json")
        let workflowExport = LauncherSavedArtifactExportRecord(
            workflow: workflow,
            path: workflowURL
        )
        let snippetExport = LauncherSavedArtifactExportRecord(
            snippet: snippet,
            path: snippetURL
        )
        let workflowJSON = try LauncherSavedArtifactExport.json(for: workflowExport)
        let snippetJSON = try LauncherSavedArtifactExport.json(for: snippetExport)

        #expect(workflow.id == "history-abc")
        #expect(workflow.title == "Review this module")
        #expect(workflow.subtitle == "Saved from AI history workflow")
        #expect(workflow.systemImage == "sparkles")
        #expect(workflow.keywords.contains("history"))
        #expect(workflow.keywords.contains("gpt-5.4"))
        #expect(workflow.steps.map(\.kind) == [.prompt])
        #expect(workflow.steps.first?.template == "Review this module")
        #expect(LauncherSavedArtifactExport.table(for: workflowExport) == [
            "workflow",
            "history-abc",
            "Review this module",
            workflowURL.path,
            "workflow:history-abc",
            "kwwk launcher --command workflow:history-abc --run",
        ].joined(separator: "\t"))
        #expect(workflowJSON.contains("\"kind\" : \"workflow\""))
        #expect(workflowJSON.contains("\"commandId\" : \"workflow:history-abc\""))
        #expect(LauncherSavedArtifactExport.table(for: snippetExport) == [
            "snippet",
            "ai-output-abc",
            "Looks solid",
            snippetURL.path,
            "snippet:ai-output-abc",
            "kwwk launcher --command snippet:ai-output-abc --run",
        ].joined(separator: "\t"))
        #expect(snippetJSON.contains("\"kind\" : \"snippet\""))
        #expect(snippetJSON.contains("\"commandId\" : \"snippet:ai-output-abc\""))
    }

    @Test
    func extractsRecordIdFromCommandId() {
        #expect(AIRunHistoryCommandFactory.recordId(for: "ai-history:abc") == "abc")
        #expect(AIRunHistoryCommandFactory.recordId(for: "login") == nil)
    }

    @Test
    func terminalReplayCommandPipesPromptIntoHeadlessStdinCommand() {
        let record = AIRunHistoryRecord(
            prompt: "summarize the repo",
            output: "summary",
            exitCode: 0,
            command: "kwwk --thinking medium -p -"
        )

        #expect(record.terminalReplayCommand == "printf %s 'summarize the repo' | kwwk --thinking medium -p -")
    }

    @Test
    func terminalReplayCommandPreservesWorkingDirectory() {
        let record = AIRunHistoryRecord(
            prompt: "explain failures",
            output: "analysis",
            exitCode: 0,
            command: "kwwk -p -",
            workingDirectory: "/Users/f/My Project"
        )

        #expect(record.terminalReplayCommand == "cd '/Users/f/My Project' && printf %s 'explain failures' | kwwk -p -")
    }

    @Test
    func terminalReplayCommandLeavesNonStdinCommandsAlone() {
        let record = AIRunHistoryRecord(
            prompt: "login",
            output: "",
            exitCode: 0,
            command: "kwwk login"
        )

        #expect(record.terminalReplayCommand == "kwwk login")
    }

    @Test
    func exportRecordsIncludeReplayableTerminalCommands() throws {
        let history = AIRunHistory(records: [
            AIRunHistoryRecord(
                id: "run-1",
                prompt: "summarize repo",
                output: "answer\nline",
                exitCode: 0,
                createdAt: Date(timeIntervalSince1970: 0),
                model: "gpt-5.4",
                command: "kwwk --thinking high -p -",
                workingDirectory: "/Users/f/project"
            ),
        ])

        let record = try #require(AIRunHistoryExport.records(for: history).first)
        let table = AIRunHistoryExport.table(for: history)
        let json = try AIRunHistoryExport.json(for: history)

        #expect(record.id == "run-1")
        #expect(record.title == "summarize repo")
        #expect(record.preview == "answer\nline")
        #expect(record.createdAt == "1970-01-01T00:00:00Z")
        #expect(record.model == "gpt-5.4")
        #expect(record.replayCommand == "cd /Users/f/project && printf %s 'summarize repo' | kwwk --thinking high -p -")
        #expect(table.contains("run-1\t1970-01-01T00:00:00Z\t0\tsummarize repo\tanswer line"))
        #expect(json.contains("\"replayCommand\" : \"cd \\/Users\\/f\\/project && printf %s 'summarize repo' | kwwk --thinking high -p -\""))
    }

    @Test
    func storeRoundTripsAIHistory() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ai-history.json")
        let history = AIRunHistory(records: [
            record("old", at: 1),
            record("new", at: 2),
        ])

        try AIRunHistoryStore.save(history, to: url)

        let loaded = AIRunHistoryStore.load(from: url)
        #expect(loaded.records.map(\.prompt) == ["new", "old"])
        #expect(AIRunHistoryStore.load(from: directory.appendingPathComponent("missing.json")).records.isEmpty)
    }

    @Test
    func storeAppendPreservesNewestRunsAndAppliesLimit() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ai-history.json")

        try AIRunHistoryStore.append(record("old", at: 1), limit: 2, to: url)
        try AIRunHistoryStore.append(record("new", at: 2), limit: 2, to: url)
        try AIRunHistoryStore.append(record("newest", at: 3), limit: 2, to: url)

        let loaded = AIRunHistoryStore.load(from: url)

        #expect(loaded.records.map(\.prompt) == ["newest", "new"])
    }

    @Test
    func storeDefaultURLUsesSharedLauncherDirectory() {
        let home = URL(fileURLWithPath: "/tmp/kwwk-home", isDirectory: true)

        #expect(AIRunHistoryStore.defaultURL(homeDirectory: home).path == "/tmp/kwwk-home/.kwwk/launcher/ai-history.json")
    }

    private func record(_ prompt: String, at time: TimeInterval) -> AIRunHistoryRecord {
        AIRunHistoryRecord(
            prompt: prompt,
            output: prompt,
            exitCode: 0,
            createdAt: Date(timeIntervalSinceReferenceDate: time),
            command: "kwwk"
        )
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
