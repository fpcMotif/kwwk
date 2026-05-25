import Foundation

public struct LauncherCommandAlias: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var targetCommandId: LauncherCommand.ID
    public var systemImage: String
    public var keywords: [String]

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        targetCommandId: LauncherCommand.ID,
        systemImage: String = "arrow.triangle.branch",
        keywords: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.targetCommandId = targetCommandId
        self.systemImage = systemImage
        self.keywords = keywords
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        targetCommandId = try container.decode(String.self, forKey: .targetCommandId)
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? "arrow.triangle.branch"
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case targetCommandId
        case systemImage
        case keywords
    }
}

public enum LauncherCommandAliasIndex {
    public static let commandPrefix = "alias:"

    public static func alias(from command: LauncherCommand) -> LauncherCommandAlias? {
        guard isAliasable(command) else { return nil }

        return LauncherCommandAlias(
            id: "saved-\(slug(command.id))",
            title: command.title,
            subtitle: "Alias for \(command.title)",
            targetCommandId: command.id,
            systemImage: command.systemImage,
            keywords: keywordSet(values: [
                command.id,
                command.title,
                command.subtitle,
                command.category.rawValue,
            ] + command.keywords)
        )
    }

    public static func commands(
        for aliases: [LauncherCommandAlias],
        availableCommands: [LauncherCommand]
    ) -> [LauncherCommand] {
        var commandsById: [LauncherCommand.ID: LauncherCommand] = [:]
        for command in availableCommands where commandsById[command.id] == nil {
            commandsById[command.id] = command
        }

        return aliases.compactMap { alias in
            guard let target = commandsById[alias.targetCommandId] else { return nil }
            return LauncherCommand(
                id: "\(commandPrefix)\(alias.id)",
                title: alias.title,
                subtitle: alias.subtitle.isEmpty ? "Alias for \(target.title)" : alias.subtitle,
                systemImage: alias.systemImage,
                category: .alias,
                keywords: [
                    alias.id,
                    alias.title,
                    alias.subtitle,
                    alias.targetCommandId,
                    target.title,
                    target.subtitle,
                    "alias",
                    "shortcut",
                ] + alias.keywords,
                action: .runCommandAlias(alias)
            )
        }
    }

    public static func load(from url: URL = defaultURL()) -> [LauncherCommandAlias] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        return (try? decoder.decode([LauncherCommandAlias].self, from: data))
            ?? (try? decoder.decode(LauncherCommandAliasDocument.self, from: data))?.aliases
            ?? []
    }

    public static func save(_ aliases: [LauncherCommandAlias], to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(aliases)
        try data.write(to: url, options: .atomic)
    }

    public static func upsert(_ alias: LauncherCommandAlias, to url: URL = defaultURL()) throws {
        var aliases = load(from: url)
        aliases.removeAll { $0.id == alias.id }
        aliases.append(alias)
        aliases.sort { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        try save(aliases, to: url)
    }

    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".kwwk")
            .appendingPathComponent("launcher")
            .appendingPathComponent("aliases.json")
    }

    private static func isAliasable(_ command: LauncherCommand) -> Bool {
        switch command.action {
        case .askPrompt, .runShellCommand, .copyCalculatorResult, .copyUnitConversionResult, .openPath, .runRecentCommand, .runCommandAlias:
            return false
        case .openQuicklink:
            return command.id.hasPrefix("quicklink:")
        default:
            return !command.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func keywordSet(values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .flatMap { value -> [String] in
                if value.contains(",") {
                    return value.split(separator: ",").map(String.init)
                }
                return [value]
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func slug(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "command" : collapsed
    }
}

public struct LauncherCommandAliasExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var targetCommandId: String
    public var commandId: String
    public var launcherCommand: String
    public var launcherURL: String

    public init(alias: LauncherCommandAlias) {
        id = alias.id
        title = alias.title
        subtitle = alias.subtitle
        targetCommandId = alias.targetCommandId
        commandId = "\(LauncherCommandAliasIndex.commandPrefix)\(alias.id)"
        launcherCommand = [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(commandId),
            "--run",
        ].joined(separator: " ")
        launcherURL = LauncherCommandAliasExport.launcherURL(for: alias)
    }
}

public enum LauncherCommandAliasExport {
    public static func records(for aliases: [LauncherCommandAlias]) -> [LauncherCommandAliasExportRecord] {
        aliases
            .map(LauncherCommandAliasExportRecord.init(alias:))
            .sorted { lhs, rhs in
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    public static func table(for aliases: [LauncherCommandAlias]) -> String {
        let rows = records(for: aliases)
        guard !rows.isEmpty else { return "" }
        return rows
            .map {
                [
                    $0.id,
                    $0.title,
                    $0.subtitle,
                    $0.targetCommandId,
                    $0.launcherCommand,
                ]
                .map(tableCell)
                .joined(separator: "\t")
            }
            .joined(separator: "\n")
    }

    public static func json(for aliases: [LauncherCommandAlias]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: aliases))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public static func json(for alias: LauncherCommandAlias) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LauncherCommandAliasExportRecord(alias: alias))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func launcherURL(
        for alias: LauncherCommandAlias,
        workingDirectory: String? = nil
    ) -> String {
        let commandId = "\(LauncherCommandAliasIndex.commandPrefix)\(alias.id)"
        return LauncherDeepLinkRequest(
            commandId: commandId,
            runImmediately: true,
            workingDirectory: workingDirectory
        ).url.absoluteString
    }

    private static func tableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LauncherCommandAliasDocument: Codable {
    var aliases: [LauncherCommandAlias]
}
