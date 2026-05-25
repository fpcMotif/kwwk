import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher CLI context")
struct LauncherCLIContextTests {
    @Test
    func defaultDirectoryCanBeOverriddenForAutomation() {
        let directory = LauncherCLIContextStore.defaultDirectory(environment: [
            LauncherCLIContextStore.environmentDirectoryKey: "/tmp/kwwk launcher context",
        ])

        #expect(directory.path == "/tmp/kwwk launcher context")
    }

    @Test
    func savesPipedTextAsNamedLocalContextFile() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = try LauncherCLIContextStore.saveStdinContext(
            "diff --git a/file b/file\n+ship it\n",
            name: "Git Diff!",
            id: "ABC 123",
            directory: root
        )

        #expect(url.lastPathComponent == "git-diff-abc-123.txt")
        #expect(try String(contentsOf: url, encoding: .utf8) == "diff --git a/file b/file\n+ship it\n")
    }

    @Test
    func capturedContextsBecomeAIFirstLauncherCommands() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try LauncherCLIContextStore.saveStdinContext(
            "FAIL src/App.swift:42\nexpected ok\n",
            name: "Test Output",
            id: "11111111-2222-3333-4444-555555555555",
            directory: root
        )

        let record = try #require(LauncherCLIContextIndex.scan(directory: root).first)
        let command = try #require(LauncherCLIContextIndex.commands(for: [record])
            .first { $0.id.hasPrefix(LauncherCLIContextIndex.commandPrefix) })
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(record.title == "Test Output")
        #expect(command.id == "cli-context:test-output-11111111-2222-3333-4444-555555555555")
        #expect(command.title == "Ask About Test Output")
        #expect(command.category == .cli)
        #expect(command.action == .askCLIContext(record))
        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Ask")
        #expect(LauncherActionCatalog.launcherCommand(for: command) == "kwwk launcher --command cli-context:test-output-11111111-2222-3333-4444-555555555555 --run")
        #expect(LauncherCommandPreview.text(for: command).contains("FAIL src/App.swift:42"))
        #expect(record.capturedText() == "FAIL src/App.swift:42\nexpected ok")
        #expect(actions.first { $0.id == "copy-context" }?.title == "Copy Captured Output")
        #expect(actions.first { $0.id == "copy-context" }?.kind == .copyText("FAIL src/App.swift:42\nexpected ok"))
        #expect(actions.first { $0.id == "copy-context-prompt" }?.kind == .copyText(record.askPrompt))
        #expect(actions.first { $0.id == "copy-path" }?.kind == .copyText(url.path))
        #expect(actions.first { $0.id == "reveal" }?.kind == .revealPath(url.path))
        let trashAction = try #require(actions.first { $0.id == "trash-context" })
        #expect(trashAction.kind == .trashPath(url.path))
        #expect(LauncherActionExportRecord(action: trashAction).kind == "trashPath")
        #expect(LauncherActionExportRecord(action: trashAction).value == url.path)
    }

    @Test
    func capturedContextsCanBecomeReusablePromptCommandsAndWorkflows() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try LauncherCLIContextStore.saveStdinContext(
            "FAIL Sources/App.swift:42\nexpected ok\n",
            name: "Test Output",
            id: "11111111-2222-3333-4444-555555555555",
            directory: root
        )

        let record = try #require(LauncherCLIContextIndex.scan(directory: root).first)
        let command = try #require(LauncherCLIContextIndex.commands(for: [record])
            .first { $0.id.hasPrefix(LauncherCLIContextIndex.commandPrefix) })
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)
        let promptCommand = LauncherPromptCommandIndex.promptCommand(from: record)
        let workflow = LauncherWorkflowIndex.workflow(from: record)
        let snippet = try #require(LauncherSnippetIndex.snippet(from: record))

        #expect(promptCommand.id == "cli-context-test-output-11111111-2222-3333-4444-555555555555")
        #expect(promptCommand.title == "Ask About Test Output")
        #expect(promptCommand.subtitle == "Saved terminal context prompt")
        #expect(promptCommand.systemImage == "terminal")
        #expect(promptCommand.keywords.contains("cli context"))
        #expect(promptCommand.promptTemplate.contains("FAIL Sources/App.swift:42"))
        #expect(snippet.id == "cli-context-test-output-11111111-2222-3333-4444-555555555555")
        #expect(snippet.title == "FAIL Sources/App.swift:42")
        #expect(snippet.subtitle == "Saved from terminal context")
        #expect(snippet.textTemplate == "FAIL Sources/App.swift:42\nexpected ok")

        #expect(workflow.id == "cli-context-test-output-11111111-2222-3333-4444-555555555555")
        #expect(workflow.title == "Ask About Test Output")
        #expect(workflow.subtitle == "Saved terminal context workflow")
        #expect(workflow.systemImage == "terminal")
        #expect(workflow.keywords.contains("captured output"))
        #expect(workflow.steps.map(\.kind) == [.prompt])
        #expect(workflow.steps.first?.template.contains("expected ok") == true)

        let savePrompt = actions.first { $0.id == "save-prompt-command" }
        let saveSnippet = actions.first { $0.id == "save-context-snippet" }
        let saveWorkflow = actions.first { $0.id == "save-workflow" }
        #expect(savePrompt?.title == "Save as Prompt Command")
        #expect(savePrompt?.kind == .savePromptTemplate(promptCommand))
        #expect(saveSnippet?.title == "Save Context as Snippet")
        #expect(saveSnippet?.kind == .saveSnippet(snippet))
        #expect(saveWorkflow?.title == "Save as Workflow")
        #expect(saveWorkflow?.kind == .saveWorkflow(workflow))
    }

    @Test
    func latestCapturedContextHasStableAutomationCommand() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let olderURL = try LauncherCLIContextStore.saveStdinContext(
            "older output\n",
            name: "Older Output",
            id: "11111111-2222-3333-4444-555555555555",
            directory: root
        )
        let newerURL = try LauncherCLIContextStore.saveStdinContext(
            "newer failure\n",
            name: "Newer Failure",
            id: "66666666-7777-8888-9999-aaaaaaaaaaaa",
            directory: root
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: olderURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newerURL.path
        )

        let records = LauncherCLIContextIndex.scan(directory: root)
        let newest = try #require(records.first)
        let latest = try #require(LauncherCLIContextIndex.commands(for: records)
            .first { $0.id == LauncherCLIContextIndex.latestCommandId })

        #expect(newest.path == newerURL.path)
        #expect(latest.title == "Ask About Latest Terminal Context")
        #expect(latest.subtitle.contains("Newer Failure"))
        #expect(latest.action == .askCLIContext(newest))
        #expect(LauncherActionCatalog.launcherCommand(for: latest) == "kwwk launcher --command latest-cli-context --run")
        #expect(LauncherCommandPreview.text(for: latest).contains("newer failure"))
        let commands = LauncherDynamicCommandFactory.commands(for: "latest terminal context")
            + LauncherCLIContextIndex.commands(for: records)
        #expect(LauncherCommandFilter.filter(
            commands,
            query: "latest terminal context"
        ).first?.id == LauncherCLIContextIndex.latestCommandId)
    }

    @Test
    func capturedContextExportsReplayableLauncherCommand() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try LauncherCLIContextStore.saveStdinContext(
            "swift test failed\n",
            name: "Focused Test",
            id: "11111111-2222-3333-4444-555555555555",
            directory: root
        )
        let record = try #require(LauncherCLIContextIndex.record(for: url))
        let commandId = "\(LauncherCLIContextIndex.commandPrefix)\(record.id)"
        let launcherCommand = "kwwk launcher --command \(commandId) --run"

        let table = LauncherCLIContextExport.table(for: record)
        let json = try LauncherCLIContextExport.json(for: record)

        #expect(table == [
            record.id,
            "Focused Test",
            url.path,
            launcherCommand,
        ].joined(separator: "\t"))
        #expect(json.contains("\"id\" : \"\(record.id)\""))
        #expect(json.contains("\"title\" : \"Focused Test\""))
        #expect(json.contains("\"path\" : \"\(url.path.replacingOccurrences(of: "/", with: "\\/"))\""))
        #expect(json.contains("\"commandId\" : \"\(commandId)\""))
        #expect(json.contains("\"launcherCommand\" : \"\(launcherCommand)\""))
    }

    @Test
    func capturedContextListExportKeepsNewestFirstWithReplayCommands() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let olderURL = try LauncherCLIContextStore.saveStdinContext(
            "older\n",
            name: "Older Build",
            id: "11111111-2222-3333-4444-555555555555",
            directory: root
        )
        let newerURL = try LauncherCLIContextStore.saveStdinContext(
            "newer failure\n",
            name: "Newer Build",
            id: "66666666-7777-8888-9999-aaaaaaaaaaaa",
            directory: root
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: olderURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newerURL.path
        )

        let records = LauncherCLIContextIndex.scan(directory: root)
        let table = LauncherCLIContextExport.table(for: records)
        let json = try LauncherCLIContextExport.json(for: records)

        #expect(LauncherCLIContextExport.records(for: records).map(\.title) == ["Newer Build", "Older Build"])
        let firstLine = try #require(table.split(separator: "\n").first).description
        #expect(firstLine == [
            "newer-build-66666666-7777-8888-9999-aaaaaaaaaaaa",
            "Newer Build",
            "14",
            newerURL.path,
            "kwwk launcher --command cli-context:newer-build-66666666-7777-8888-9999-aaaaaaaaaaaa --run",
        ].joined(separator: "\t"))
        #expect(json.contains("\"id\" : \"newer-build-66666666-7777-8888-9999-aaaaaaaaaaaa\""))
        #expect(json.contains("\"id\" : \"older-build-11111111-2222-3333-4444-555555555555\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command cli-context:newer-build-66666666-7777-8888-9999-aaaaaaaaaaaa --run\""))
    }

    @Test
    func savedContextArtifactExportIncludesReusableLauncherCommands() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try LauncherCLIContextStore.saveStdinContext(
            "swift test failed\n",
            name: "Focused Test",
            id: "11111111-2222-3333-4444-555555555555",
            directory: root
        )
        let record = try #require(LauncherCLIContextIndex.record(for: url))
        let promptCommand = LauncherPromptCommandIndex.promptCommand(from: record)
        let snippet = try #require(LauncherSnippetIndex.snippet(from: record))
        let workflow = LauncherWorkflowIndex.workflow(from: record)
        let promptURL = root.appendingPathComponent("prompts.json")
        let snippetURL = root.appendingPathComponent("snippets.json")
        let workflowURL = root.appendingPathComponent("workflows.json")

        let promptExport = LauncherSavedArtifactExportRecord(
            promptCommand: promptCommand,
            path: promptURL
        )
        let snippetExport = LauncherSavedArtifactExportRecord(
            snippet: snippet,
            path: snippetURL
        )
        let workflowExport = LauncherSavedArtifactExportRecord(
            workflow: workflow,
            path: workflowURL
        )
        let promptJSON = try LauncherSavedArtifactExport.json(for: promptExport)
        let snippetJSON = try LauncherSavedArtifactExport.json(for: snippetExport)
        let workflowJSON = try LauncherSavedArtifactExport.json(for: workflowExport)
        let promptCommandId = "prompt:\(promptCommand.id)"
        let snippetCommandId = "snippet:\(snippet.id)"
        let workflowCommandId = "workflow:\(workflow.id)"

        #expect(LauncherSavedArtifactExport.table(for: promptExport) == [
            "promptCommand",
            promptCommand.id,
            "Ask About Focused Test",
            promptURL.path,
            promptCommandId,
            "kwwk launcher --command \(promptCommandId) --run",
        ].joined(separator: "\t"))
        #expect(LauncherSavedArtifactExport.table(for: snippetExport) == [
            "snippet",
            snippet.id,
            "swift test failed",
            snippetURL.path,
            snippetCommandId,
            "kwwk launcher --command \(snippetCommandId) --run",
        ].joined(separator: "\t"))
        #expect(LauncherSavedArtifactExport.table(for: workflowExport) == [
            "workflow",
            workflow.id,
            "Ask About Focused Test",
            workflowURL.path,
            workflowCommandId,
            "kwwk launcher --command \(workflowCommandId) --run",
        ].joined(separator: "\t"))
        #expect(promptJSON.contains("\"kind\" : \"promptCommand\""))
        #expect(promptJSON.contains("\"path\" : \"\(promptURL.path.replacingOccurrences(of: "/", with: "\\/"))\""))
        #expect(snippetJSON.contains("\"kind\" : \"snippet\""))
        #expect(snippetJSON.contains("\"launcherCommand\" : \"kwwk launcher --command \(snippetCommandId) --run\""))
        #expect(workflowJSON.contains("\"kind\" : \"workflow\""))
        #expect(workflowJSON.contains("\"launcherCommand\" : \"kwwk launcher --command \(workflowCommandId) --run\""))
    }

    @Test
    func defaultCatalogExposesCLIContextManagementCommands() throws {
        let reveal = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reveal-cli-contexts" })
        let reload = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reload-cli-contexts" })
        let clear = try #require(LauncherCommandCatalog.defaults.first { $0.id == "clear-cli-contexts" })

        #expect(reveal.title == "Reveal Terminal Contexts Folder")
        #expect(reveal.category == .cli)
        #expect(reveal.action == .revealCLIContextsFolder)
        #expect(LauncherActionCatalog.primaryTitle(for: reveal) == "Reveal")
        #expect(LauncherActionCatalog.launcherCommand(for: reveal) == "kwwk launcher --command reveal-cli-contexts --run")
        #expect(reload.title == "Reload Terminal Contexts")
        #expect(reload.category == .cli)
        #expect(reload.action == .reloadCLIContexts)
        #expect(LauncherActionCatalog.primaryTitle(for: reload) == "Reload")
        #expect(clear.title == "Clear Terminal Contexts")
        #expect(clear.category == .cli)
        #expect(clear.action == .clearCLIContexts)
        #expect(LauncherActionCatalog.primaryTitle(for: clear) == "Clear")
        #expect(LauncherActionCatalog.launcherCommand(for: clear) == "kwwk launcher --command clear-cli-contexts --run")
        #expect(LauncherActionCatalog.actions(for: clear, isFavorite: false)
            .first { $0.id == "copy-location" }?.kind == .copyText("~/.kwwk/launcher/context"))

        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "@cli terminal context")
        #expect(results.map(\.id).contains("reveal-cli-contexts"))
        #expect(results.map(\.id).contains("reload-cli-contexts"))
        #expect(results.map(\.id).contains("clear-cli-contexts"))
    }

    @Test
    func emptyPipedContextIsRejected() {
        #expect(throws: LauncherCLIContextStoreError.emptyInput) {
            _ = try LauncherCLIContextStore.saveStdinContext(" \n\t")
        }
    }

    @Test
    func filenameStemIsBoundedAndShellFriendly() {
        let stem = LauncherCLIContextStore.filenameStem(from: "  Review: failing tests / stderr output!!!  ")

        #expect(stem == "review-failing-tests-stderr-output")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
