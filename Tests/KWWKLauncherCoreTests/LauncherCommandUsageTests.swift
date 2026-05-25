import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher command usage")
struct LauncherCommandUsageTests {
    @Test
    func marksUseCountAndLastUsedAt() {
        var usage = LauncherCommandUsage()
        let date = Date(timeIntervalSinceReferenceDate: 42)

        usage.markUsed("open-cli", at: date)

        #expect(usage.record(for: "open-cli")?.useCount == 1)
        #expect(usage.record(for: "open-cli")?.lastUsedAt == date)
    }

    @Test
    func togglesFavoriteState() {
        var usage = LauncherCommandUsage()

        #expect(usage.toggleFavorite("login") == true)
        #expect(usage.isFavorite("login"))
        #expect(usage.toggleFavorite("login") == false)
        #expect(!usage.isFavorite("login"))
    }

    @Test
    func favoritesRankFirstForEmptyQuery() {
        var usage = LauncherCommandUsage()
        usage.toggleFavorite("login")

        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "", usage: usage)

        #expect(results.first?.id == "login")
    }

    @Test
    func recentsRankBeforeUnusedForEmptyQuery() {
        var usage = LauncherCommandUsage()
        usage.markUsed("open-cli", at: Date(timeIntervalSinceReferenceDate: 100))

        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "", usage: usage)

        #expect(results.first?.id == "open-cli")
    }

    @Test
    func recentCommandFactoryBuildsMostRecentAliases() throws {
        var usage = LauncherCommandUsage()
        usage.markUsed("login", at: Date(timeIntervalSinceReferenceDate: 100))
        usage.markUsed("open-cli", at: Date(timeIntervalSinceReferenceDate: 200))

        let recents = LauncherRecentCommandFactory.commands(
            from: LauncherCommandCatalog.defaults,
            usage: usage,
            limit: 1
        )

        let recent = try #require(recents.first)
        #expect(recents.count == 1)
        #expect(recent.id == "recent:open-cli")
        #expect(recent.title == "Open KWWK CLI")
        #expect(recent.category == .recent)
        #expect(recent.action == .runRecentCommand("open-cli"))
        #expect(recent.keywords.contains("recent"))
    }

    @Test
    func recentCommandFactoryIgnoresMissingAndNeverUsedCommands() {
        var usage = LauncherCommandUsage(records: [
            "login": LauncherCommandUse(useCount: 0, lastUsedAt: nil, isFavorite: true),
            "missing": LauncherCommandUse(useCount: 1, lastUsedAt: Date(), isFavorite: false),
        ])
        usage.markUsed("open-cli", at: Date(timeIntervalSinceReferenceDate: 200))

        let recents = LauncherRecentCommandFactory.commands(
            from: LauncherCommandCatalog.defaults,
            usage: usage
        )

        #expect(recents.map(\.id) == ["recent:open-cli"])
    }

    @Test
    func recentCommandFactoryMapsOriginalIds() {
        #expect(LauncherRecentCommandFactory.originalCommandId(for: "recent:open-cli") == "open-cli")
        #expect(LauncherRecentCommandFactory.originalCommandId(for: "open-cli") == nil)
    }

    @Test
    func usageBoostsMatchingCommandsWithoutBypassingTheQuery() {
        var usage = LauncherCommandUsage()
        usage.toggleFavorite("login")

        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "terminal", usage: usage)

        #expect(results.contains { $0.id == "open-cli" })
        #expect(!results.contains { $0.id == "login" })
    }

    @Test
    func menuSectionsExposeFavoritesAndRecentsWithoutDuplicates() {
        var usage = LauncherCommandUsage()
        usage.toggleFavorite("login")
        usage.markUsed("login", at: Date(timeIntervalSinceReferenceDate: 300))
        usage.markUsed("open-cli", at: Date(timeIntervalSinceReferenceDate: 200))
        usage.markUsed("ask-kwwk", at: Date(timeIntervalSinceReferenceDate: 100))

        let sections = LauncherMenuCommandFactory.sections(
            from: LauncherCommandCatalog.defaults,
            usage: usage,
            favoritesLimit: 3,
            recentsLimit: 2
        )

        #expect(sections.favorites.map(\.id) == ["login"])
        #expect(sections.recents.map(\.id) == ["open-cli", "ask-kwwk"])
    }

    @Test
    func residentCommandCatalogExposesTerminalContextsToMenuSections() {
        let record = LauncherCLIContextRecord(
            id: "build-log-11111111-2222-3333-4444-555555555555",
            title: "Build Log",
            path: "/tmp/build-log.txt",
            byteCount: 42,
            modifiedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let contextCommandId = "\(LauncherCLIContextIndex.commandPrefix)\(record.id)"
        let commands = LauncherResidentCommandCatalog.commands(
            aiHistory: AIRunHistory(),
            clipboardHistory: LauncherClipboardHistory(),
            aiProfiles: [],
            promptCommands: [],
            workflows: [],
            cliContexts: [record],
            quicklinks: [],
            snippets: [],
            scripts: [],
            applications: [],
            aliases: [
                LauncherCommandAlias(
                    id: "build-log-shortcut",
                    title: "Build Log Shortcut",
                    targetCommandId: contextCommandId
                ),
            ]
        )
        var usage = LauncherCommandUsage()
        usage.toggleFavorite(contextCommandId)
        usage.markUsed(LauncherCLIContextIndex.latestCommandId, at: Date(timeIntervalSinceReferenceDate: 300))

        let sections = LauncherMenuCommandFactory.sections(
            from: commands,
            usage: usage,
            terminalContexts: [record]
        )

        #expect(commands.map(\.id).contains(contextCommandId))
        #expect(commands.map(\.id).contains(LauncherCLIContextIndex.latestCommandId))
        #expect(commands.map(\.id).contains("alias:build-log-shortcut"))
        #expect(sections.favorites.map(\.id) == [contextCommandId])
        #expect(sections.recents.map(\.id) == [LauncherCLIContextIndex.latestCommandId])
        #expect(sections.terminalContexts.map(\.id) == [
            LauncherCLIContextIndex.latestCommandId,
            contextCommandId,
        ])
    }

    @Test
    func terminalContextMenuSectionIsAvailableWithoutUsage() {
        let newer = LauncherCLIContextRecord(
            id: "newer-build-11111111-2222-3333-4444-555555555555",
            title: "Newer Build",
            path: "/tmp/newer-build.txt",
            byteCount: 42,
            modifiedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        let older = LauncherCLIContextRecord(
            id: "older-build-66666666-7777-8888-9999-aaaaaaaaaaaa",
            title: "Older Build",
            path: "/tmp/older-build.txt",
            byteCount: 21,
            modifiedAt: Date(timeIntervalSinceReferenceDate: 100)
        )

        let sections = LauncherMenuCommandFactory.sections(
            from: LauncherCommandCatalog.defaults,
            usage: LauncherCommandUsage(),
            terminalContexts: [newer, older],
            terminalContextsLimit: 2
        )

        #expect(sections.favorites.isEmpty)
        #expect(sections.recents.isEmpty)
        #expect(sections.terminalContexts.map(\.id) == [
            LauncherCLIContextIndex.latestCommandId,
            "\(LauncherCLIContextIndex.commandPrefix)\(newer.id)",
        ])
    }

    @Test
    func menuTitlesAreCappedForMenuBarReadability() {
        let command = LauncherCommand(
            id: "long",
            title: "This Command Title Is Much Too Long For A Menu",
            subtitle: "Fixture",
            systemImage: "sparkles",
            category: .ai,
            keywords: [],
            action: .askAI
        )

        let item = LauncherMenuCommand(command: command)

        #expect(item.displayTitle().count == 30)
        #expect(item.displayTitle().hasSuffix("..."))
    }
}
