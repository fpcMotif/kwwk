import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher clipboard history")
struct LauncherClipboardHistoryTests {
    @Test
    func historyDropsBlankEntriesDedupesAndKeepsNewest() {
        var history = LauncherClipboardHistory()

        let blankAdded = history.add("   ")
        let firstAdded = history.add("first", copiedAt: Date(timeIntervalSince1970: 10))
        let secondAdded = history.add("second", copiedAt: Date(timeIntervalSince1970: 20))
        let duplicateAdded = history.add("first", copiedAt: Date(timeIntervalSince1970: 30))

        #expect(!blankAdded)
        #expect(firstAdded)
        #expect(secondAdded)
        #expect(duplicateAdded)

        #expect(history.records.map(\.text) == ["first", "second"])
        #expect(history.records.first?.copiedAt == Date(timeIntervalSince1970: 30))
    }

    @Test
    func clipboardRecordsBecomeSearchableCommands() throws {
        let record = LauncherClipboardHistoryRecord(
            text: "Release notes\nShip the launcher",
            copiedAt: Date(timeIntervalSince1970: 10)
        )

        let command = try #require(LauncherClipboardHistoryCommandFactory.commands(
            for: LauncherClipboardHistory(records: [record])
        ).first { $0.id.hasPrefix(LauncherClipboardHistoryCommandFactory.commandPrefix) })

        #expect(command.id == "clipboard:\(record.id)")
        #expect(command.category == .clipboard)
        #expect(command.title == "Release notes")
        #expect(command.subtitle == "Release notes Ship the launcher")
        #expect(command.action == .copyClipboardHistory(record))
    }

    @Test
    func actionCatalogExposesClipboardActionsAndCLIReplay() throws {
        let record = LauncherClipboardHistoryRecord(text: "copy me")
        let command = try #require(LauncherClipboardHistoryCommandFactory.commands(
            for: LauncherClipboardHistory(records: [record])
        ).first { $0.id.hasPrefix(LauncherClipboardHistoryCommandFactory.commandPrefix) })

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Copy")
        #expect(actions.contains {
            $0.id == "copy-text" && $0.kind == .copyText("copy me")
        })
        #expect(actions.contains {
            $0.id == "save-snippet" && $0.kind == .saveSnippet(LauncherSnippetIndex.snippet(from: record))
        })
        #expect(
            LauncherActionCatalog.launcherCommand(for: command)
                == "kwwk launcher --command clipboard:\(record.id) --run"
        )
    }

    @Test
    func clipboardSnippetExportIncludesReusableLauncherCommand() throws {
        let record = LauncherClipboardHistoryRecord(id: "abc", text: "copy me")
        let snippet = LauncherSnippetIndex.snippet(from: record)
        let snippetURL = URL(fileURLWithPath: "/tmp/kwwk-snippets.json")
        let export = LauncherSavedArtifactExportRecord(snippet: snippet, path: snippetURL)
        let json = try LauncherSavedArtifactExport.json(for: export)

        #expect(LauncherSavedArtifactExport.table(for: export) == [
            "snippet",
            "clipboard-abc",
            "copy me",
            snippetURL.path,
            "snippet:clipboard-abc",
            "kwwk launcher --command snippet:clipboard-abc --run",
        ].joined(separator: "\t"))
        #expect(json.contains("\"kind\" : \"snippet\""))
        #expect(json.contains("\"commandId\" : \"snippet:clipboard-abc\""))
    }

    @Test
    func latestClipboardHasStableAutomationCommand() throws {
        let older = LauncherClipboardHistoryRecord(
            text: "older clipboard",
            copiedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = LauncherClipboardHistoryRecord(
            text: "newer clipboard\nsecond line",
            copiedAt: Date(timeIntervalSince1970: 20)
        )
        let history = LauncherClipboardHistory(records: [older, newer])

        let commands = LauncherClipboardHistoryCommandFactory.commands(for: history)
        let latest = try #require(commands.first { $0.id == LauncherClipboardHistoryCommandFactory.latestCommandId })

        #expect(commands.first?.id == LauncherClipboardHistoryCommandFactory.latestCommandId)
        #expect(latest.title == "Latest Clipboard")
        #expect(latest.subtitle == "newer clipboard second line")
        #expect(latest.action == .copyClipboardHistory(newer))
        #expect(latest.keywords.contains("latest clipboard"))
        #expect(LauncherActionCatalog.primaryTitle(for: latest) == "Copy")
        #expect(LauncherActionCatalog.launcherCommand(for: latest) == "kwwk launcher --command latest-clipboard --run")

        let filtered = LauncherCommandFilter.filter(
            LauncherDynamicCommandFactory.commands(for: "latest clipboard") + commands,
            query: "latest clipboard"
        )
        #expect(filtered.first?.id == LauncherClipboardHistoryCommandFactory.latestCommandId)
    }

    @Test
    func clipboardHistoryExportIncludesReplayableLauncherCommands() throws {
        let history = LauncherClipboardHistory(records: [
            LauncherClipboardHistoryRecord(
                id: "clip-1",
                text: "Release notes\nShip it",
                copiedAt: Date(timeIntervalSince1970: 0)
            ),
        ])

        let record = try #require(LauncherClipboardHistoryExport.records(for: history).first)
        let table = LauncherClipboardHistoryExport.table(for: history)
        let json = try LauncherClipboardHistoryExport.json(for: history)

        #expect(record.id == "clip-1")
        #expect(record.title == "Release notes")
        #expect(record.preview == "Release notes Ship it")
        #expect(record.copiedAt == "1970-01-01T00:00:00Z")
        #expect(record.commandId == "clipboard:clip-1")
        #expect(record.launcherCommand == "kwwk launcher --command clipboard:clip-1 --run")
        #expect(table == [
            "clip-1",
            "1970-01-01T00:00:00Z",
            "Release notes",
            "Release notes Ship it",
            "kwwk launcher --command clipboard:clip-1 --run",
        ].joined(separator: "\t"))
        #expect(json.contains("\"commandId\" : \"clipboard:clip-1\""))
        #expect(json.contains("\"text\" : \"Release notes\\nShip it\""))
    }

    @Test
    func savedClipboardSnippetExportIncludesReusableLauncherCommand() throws {
        let record = LauncherClipboardHistoryRecord(
            id: "clip-1",
            text: "copy me"
        )
        let snippet = LauncherSnippetIndex.snippet(from: record)
        let url = URL(fileURLWithPath: "/tmp/kwwk-snippets.json")
        let export = LauncherSavedArtifactExportRecord(snippet: snippet, path: url)

        #expect(LauncherSavedArtifactExport.table(for: export) == [
            "snippet",
            "clipboard-clip-1",
            "copy me",
            url.path,
            "snippet:clipboard-clip-1",
            "kwwk launcher --command snippet:clipboard-clip-1 --run",
        ].joined(separator: "\t"))
    }

    @Test
    func storeRoundTripsClipboardHistory() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("clipboard-history.json")
        let history = LauncherClipboardHistory(records: [
            LauncherClipboardHistoryRecord(text: "one", copiedAt: Date(timeIntervalSince1970: 1)),
            LauncherClipboardHistoryRecord(text: "two", copiedAt: Date(timeIntervalSince1970: 2)),
        ])

        try LauncherClipboardHistoryStore.save(history, to: url)

        let loaded = LauncherClipboardHistoryStore.load(from: url)
        #expect(loaded.records.map(\.text) == ["two", "one"])
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
