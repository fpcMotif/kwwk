import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher command aliases")
struct LauncherCommandAliasTests {
    @Test
    func loadsArrayAndDocumentJSONFormats() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let arrayURL = directory.appendingPathComponent("aliases-array.json")
        try """
        [
          {
            "id": "term",
            "title": "Terminal",
            "targetCommandId": "open-cli"
          }
        ]
        """.write(to: arrayURL, atomically: true, encoding: .utf8)

        let documentURL = directory.appendingPathComponent("aliases-document.json")
        try """
        {
          "aliases": [
            {
              "id": "login-now",
              "title": "Login Now",
              "subtitle": "Auth shortcut",
              "targetCommandId": "login",
              "systemImage": "key",
              "keywords": ["auth"]
            }
          ]
        }
        """.write(to: documentURL, atomically: true, encoding: .utf8)

        #expect(LauncherCommandAliasIndex.load(from: arrayURL).map(\.id) == ["term"])
        let alias = try #require(LauncherCommandAliasIndex.load(from: documentURL).first)
        #expect(alias.id == "login-now")
        #expect(alias.subtitle == "Auth shortcut")
        #expect(alias.systemImage == "key")
        #expect(alias.keywords == ["auth"])
    }

    @Test
    func aliasesBecomeSearchableCommandsForExistingTargets() throws {
        let alias = LauncherCommandAlias(
            id: "term",
            title: "Terminal",
            targetCommandId: "open-cli",
            keywords: ["go"]
        )
        let missing = LauncherCommandAlias(
            id: "missing",
            title: "Missing",
            targetCommandId: "not-real"
        )

        let commands = LauncherCommandAliasIndex.commands(
            for: [alias, missing],
            availableCommands: LauncherCommandCatalog.defaults
        )
        let command = try #require(commands.first)

        #expect(commands.count == 1)
        #expect(command.id == "alias:term")
        #expect(command.category == .alias)
        #expect(command.subtitle == "Alias for Open KWWK CLI")
        #expect(command.keywords.contains("open-cli"))
        #expect(command.keywords.contains("go"))
        #expect(command.action == .runCommandAlias(alias))
    }

    @Test
    func duplicateAvailableCommandIdsDoNotCrashAliasIndexing() throws {
        let alias = LauncherCommandAlias(id: "term", title: "Terminal", targetCommandId: "open-cli")
        let openCLI = try #require(LauncherCommandCatalog.defaults.first { $0.id == "open-cli" })

        let commands = LauncherCommandAliasIndex.commands(
            for: [alias],
            availableCommands: [openCLI, openCLI] + LauncherCommandCatalog.defaults
        )

        #expect(commands.map(\.id) == ["alias:term"])
        #expect(commands.first?.subtitle == "Alias for Open KWWK CLI")
    }

    @Test
    func aliasScopeFiltersInsideAliasCategory() throws {
        let alias = LauncherCommandAlias(id: "term", title: "Terminal", targetCommandId: "open-cli")
        let command = try #require(LauncherCommandAliasIndex.commands(
            for: [alias],
            availableCommands: LauncherCommandCatalog.defaults
        ).first)

        let results = LauncherCommandFilter.filter(
            [command] + LauncherCommandCatalog.defaults,
            query: "@aliases term"
        )

        #expect(results.first?.id == "alias:term")
        #expect(results.allSatisfy { $0.category == .alias })
    }

    @Test
    func aliasActionsExposeTargetAndReplayableCommand() throws {
        let alias = LauncherCommandAlias(id: "term", title: "Terminal", targetCommandId: "open-cli")
        let command = try #require(LauncherCommandAliasIndex.commands(
            for: [alias],
            availableCommands: LauncherCommandCatalog.defaults
        ).first)
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run")
        #expect(actions.first { $0.id == "copy-target-command-id" }?.kind == .copyText("open-cli"))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command alias:term --run"
        ))
    }

    @Test
    func aliasExportIncludesTargetAndReplayableLauncherCommand() throws {
        let alias = LauncherCommandAlias(
            id: "term",
            title: "Terminal",
            subtitle: "Open CLI",
            targetCommandId: "open-cli",
            keywords: ["agent"]
        )

        let table = LauncherCommandAliasExport.table(for: [alias])
        let json = try LauncherCommandAliasExport.json(for: alias)

        #expect(table == """
        term\tTerminal\tOpen CLI\topen-cli\tkwwk launcher --command alias:term --run
        """)
        #expect(json.contains("\"commandId\" : \"alias:term\""))
        #expect(json.contains("\"targetCommandId\" : \"open-cli\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command alias:term --run\""))
        #expect(json.contains("\"launcherURL\" : \"kwwk:\\/\\/launcher?command=alias:term&run=1\""))
        #expect(LauncherCommandAliasExport.launcherURL(
            for: alias,
            workingDirectory: "/Users/f/project"
        ) == "kwwk://launcher?command=alias:term&run=1&cwd=/Users/f/project")
    }

    @Test
    func stableCommandsCanBecomeAliasRecords() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "open-cli" })
        let alias = try #require(LauncherCommandAliasIndex.alias(from: command))

        #expect(alias.id == "saved-open-cli")
        #expect(alias.title == "Open KWWK CLI")
        #expect(alias.subtitle == "Alias for Open KWWK CLI")
        #expect(alias.targetCommandId == "open-cli")
        #expect(alias.systemImage == "terminal")
        #expect(alias.keywords.contains("open-cli"))
        #expect(alias.keywords.contains("CLI"))
    }

    @Test
    func dynamicCommandsDoNotBecomeDanglingAliases() throws {
        let ask = try #require(LauncherDynamicCommandFactory.commands(for: "? summarize project").first)
        let shell = try #require(LauncherShellCommandFactory.commands(for: "$ git status").first)
        let calculator = try #require(LauncherCalculatorCommandFactory.commands(for: "=1+1").first)
        let web = try #require(LauncherWebCommandFactory.commands(for: "web swift").first)

        #expect(LauncherCommandAliasIndex.alias(from: ask) == nil)
        #expect(LauncherCommandAliasIndex.alias(from: shell) == nil)
        #expect(LauncherCommandAliasIndex.alias(from: calculator) == nil)
        #expect(LauncherCommandAliasIndex.alias(from: web) == nil)
    }

    @Test
    func upsertWritesAndReplacesAliases() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("aliases.json")

        try LauncherCommandAliasIndex.upsert(
            LauncherCommandAlias(id: "term", title: "Terminal", targetCommandId: "open-cli"),
            to: url
        )
        try LauncherCommandAliasIndex.upsert(
            LauncherCommandAlias(id: "term", title: "KWWK Terminal", targetCommandId: "open-cli", keywords: ["agent"]),
            to: url
        )

        let loaded = LauncherCommandAliasIndex.load(from: url)
        #expect(loaded.count == 1)
        #expect(loaded.first?.title == "KWWK Terminal")
        #expect(loaded.first?.keywords == ["agent"])
    }

    @Test
    func defaultCatalogExposesAliasFileManagementCommands() throws {
        let reveal = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reveal-command-aliases" })
        let reload = try #require(LauncherCommandCatalog.defaults.first { $0.id == "reload-command-aliases" })

        #expect(reveal.category == .alias)
        #expect(reload.category == .alias)
        #expect(LauncherActionCatalog.primaryTitle(for: reveal) == "Reveal")
        #expect(LauncherActionCatalog.primaryTitle(for: reload) == "Reload")
    }
}
