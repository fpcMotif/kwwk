import Foundation

public struct LauncherCommandUse: Codable, Sendable, Hashable {
    public var useCount: Int
    public var lastUsedAt: Date?
    public var isFavorite: Bool

    public init(useCount: Int = 0, lastUsedAt: Date? = nil, isFavorite: Bool = false) {
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.isFavorite = isFavorite
    }
}

public struct LauncherCommandUsage: Codable, Sendable, Hashable {
    public static let defaultsKey = "KWWKLauncher.CommandUsage.v1"

    public private(set) var records: [LauncherCommand.ID: LauncherCommandUse]

    public init(records: [LauncherCommand.ID: LauncherCommandUse] = [:]) {
        self.records = records
    }

    public func record(for commandId: LauncherCommand.ID) -> LauncherCommandUse? {
        records[commandId]
    }

    public func isFavorite(_ commandId: LauncherCommand.ID) -> Bool {
        records[commandId]?.isFavorite == true
    }

    public mutating func markUsed(_ commandId: LauncherCommand.ID, at date: Date = Date()) {
        var record = records[commandId] ?? LauncherCommandUse()
        record.useCount += 1
        record.lastUsedAt = date
        records[commandId] = record
    }

    @discardableResult
    public mutating func toggleFavorite(_ commandId: LauncherCommand.ID) -> Bool {
        var record = records[commandId] ?? LauncherCommandUse()
        record.isFavorite.toggle()
        records[commandId] = record
        return record.isFavorite
    }
}

public struct LauncherMenuCommand: Identifiable, Sendable, Hashable {
    public var id: LauncherCommand.ID
    public var title: String
    public var subtitle: String
    public var systemImage: String

    public init(command: LauncherCommand) {
        id = command.id
        title = command.title
        subtitle = command.subtitle
        systemImage = command.systemImage
    }

    public func displayTitle(maxLength: Int = 30) -> String {
        title.truncatedForMenu(maxLength: maxLength)
    }
}

public struct LauncherMenuCommandSections: Sendable, Hashable {
    public var favorites: [LauncherMenuCommand]
    public var recents: [LauncherMenuCommand]
    public var terminalContexts: [LauncherMenuCommand]

    public init(
        favorites: [LauncherMenuCommand],
        recents: [LauncherMenuCommand],
        terminalContexts: [LauncherMenuCommand] = []
    ) {
        self.favorites = favorites
        self.recents = recents
        self.terminalContexts = terminalContexts
    }
}

public enum LauncherMenuCommandFactory {
    public static func sections(
        from commands: [LauncherCommand],
        usage: LauncherCommandUsage,
        terminalContexts: [LauncherCLIContextRecord] = [],
        favoritesLimit: Int = 5,
        recentsLimit: Int = 5,
        terminalContextsLimit: Int = 5
    ) -> LauncherMenuCommandSections {
        var commandsById: [LauncherCommand.ID: LauncherCommand] = [:]
        for command in commands where commandsById[command.id] == nil {
            commandsById[command.id] = command
        }

        let favorites = usage.records.compactMap { commandId, record -> LauncherCommand? in
            guard record.isFavorite else { return nil }
            return commandsById[commandId]
        }
        .sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        .prefix(max(0, favoritesLimit))
        .map(LauncherMenuCommand.init(command:))

        let favoriteIds = Set(favorites.map(\.id))
        let recents = usage.records.compactMap { commandId, record -> (LauncherCommand, Date)? in
            guard let lastUsedAt = record.lastUsedAt,
                  !favoriteIds.contains(commandId),
                  let command = commandsById[commandId]
            else {
                return nil
            }
            return (command, lastUsedAt)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.title.localizedStandardCompare(rhs.0.title) == .orderedAscending
        }
        .prefix(max(0, recentsLimit))
        .map { LauncherMenuCommand(command: $0.0) }

        return LauncherMenuCommandSections(
            favorites: Array(favorites),
            recents: Array(recents),
            terminalContexts: terminalContextCommands(
                from: terminalContexts,
                limit: terminalContextsLimit
            )
        )
    }

    public static func terminalContextCommands(
        from records: [LauncherCLIContextRecord],
        limit: Int = 5
    ) -> [LauncherMenuCommand] {
        LauncherCLIContextIndex.commands(for: records)
            .prefix(max(0, limit))
            .map(LauncherMenuCommand.init(command:))
    }
}

private extension String {
    func truncatedForMenu(maxLength: Int) -> String {
        guard maxLength > 3, count > maxLength else { return self }
        let end = index(startIndex, offsetBy: maxLength - 3)
        return String(self[..<end]) + "..."
    }
}
