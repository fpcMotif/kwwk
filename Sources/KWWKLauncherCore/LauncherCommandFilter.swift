import Foundation

public enum LauncherCommandFilter {
    public static func filter(
        _ commands: [LauncherCommand],
        query: String,
        usage: LauncherCommandUsage = LauncherCommandUsage()
    ) -> [LauncherCommand] {
        let scopedQuery = scopedQuery(from: query)
        let normalized = normalize(scopedQuery.text)
        let hasQuery = !normalized.isEmpty

        return commands.enumerated().compactMap { index, command -> ScoredCommand? in
            if let category = scopedQuery.category, command.category != category {
                return nil
            }
            let score = score(command, query: normalized, rawQuery: scopedQuery.text)
            guard !hasQuery || score > 0 else { return nil }
            let record = usage.record(for: command.id)
            return ScoredCommand(
                command: command,
                textScore: score,
                usageBoost: usageBoost(record),
                record: record,
                index: index,
                hasQuery: hasQuery
            )
        }
        .sorted { lhs, rhs in
            lhs.sortsBefore(rhs)
        }
        .map(\.command)
    }

    public static func looksLikePrompt(_ query: String) -> Bool {
        let trimmed = scopedQuery(from: query).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("?") { return true }
        return trimmed.split(whereSeparator: \.isWhitespace).count >= 3
    }

    public static func promptText(from query: String) -> String {
        let trimmed = scopedQuery(from: query).text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("?") {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    public static func scopedQuery(from query: String) -> (category: LauncherCommandCategory?, text: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@") else { return (nil, trimmed) }

        let scopeEnd = trimmed.firstIndex(where: \.isWhitespace) ?? trimmed.endIndex
        let rawScope = String(trimmed[trimmed.index(after: trimmed.startIndex)..<scopeEnd])
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        guard let category = category(forScope: rawScope) else { return (nil, trimmed) }

        let rest = scopeEnd == trimmed.endIndex ? "" : String(trimmed[scopeEnd...])
        return (category, rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func score(_ command: LauncherCommand, query: String, rawQuery: String) -> Int {
        guard !query.isEmpty else { return 0 }
        if case .askPrompt(let prompt) = command.action,
           !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 662
        }
        if case .runShellCommand(let commandText) = command.action,
           let queryCommand = LauncherShellCommandFactory.commandText(from: rawQuery),
           !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if commandText == queryCommand { return 900 }
            if commandText.contains(queryCommand) { return 760 }
        }
        if case .copyCalculatorResult(let result) = command.action,
           let queryResult = LauncherCalculator.result(for: rawQuery),
           result == queryResult {
            return 890
        }
        if case .copyUnitConversionResult(let result) = command.action,
           let queryResult = LauncherUnitConverter.result(for: rawQuery),
           result == queryResult {
            return 887
        }
        if case .openPath = command.action,
           let queryCommand = LauncherPathCommandFactory.matchingCommand(for: rawQuery),
           command.id == queryCommand.id {
            return 886
        }
        if case .openQuicklink = command.action,
           let queryCommand = LauncherWebCommandFactory.matchingCommand(for: rawQuery),
           command.id == queryCommand.id {
            return 880
        }
        if command.id.hasPrefix(LauncherWorkspaceTaskCommandFactory.commandPrefix) {
            let haystack = ([command.title, command.subtitle, command.category.rawValue] + command.keywords)
                .map(normalize)
                .joined(separator: " ")
            let tokens = query.split(separator: " ").map(String.init)
            if !tokens.isEmpty && tokens.allSatisfy({ haystack.contains($0) }) {
                return 675 + min(tokens.count, 40)
            }
        }

        let title = normalize(command.title)
        let subtitle = normalize(command.subtitle)
        let category = normalize(command.category.rawValue)
        let keywords = command.keywords.map(normalize)
        let queryTokens = query.split(separator: " ").map(String.init)

        if queryTokens.first == "profile" || queryTokens.first == "profiles" {
            let rest = Array(queryTokens.dropFirst())
            let haystack = ([title, subtitle, category] + keywords).joined(separator: " ")
            switch command.action {
            case .applyAIProfile:
                guard !rest.isEmpty else { return 730 }
                return rest.allSatisfy { haystack.contains($0) }
                    ? 735 + min(rest.count, 40)
                    : 0
            case .saveCurrentAIProfile, .revealAIProfilesFile, .reloadAIProfiles:
                guard !rest.isEmpty else { return 620 }
                return rest.allSatisfy { haystack.contains($0) }
                    ? 625 + min(rest.count, 40)
                    : 0
            default:
                break
            }
        }

        if case .applyAIProfile = command.action {
            let haystack = ([title, subtitle, category] + keywords).joined(separator: " ")
            if !queryTokens.isEmpty && queryTokens.allSatisfy({ haystack.contains($0) }) {
                return 730 + min(queryTokens.count, 40)
            }
        }
        if case .setDefaultModel = command.action,
           title.contains(query) || keywords.contains(query) {
            return 760
        }
        if case .setThinkingLevel = command.action {
            let haystack = ([title, subtitle, category] + keywords).joined(separator: " ")
            if !queryTokens.isEmpty && queryTokens.allSatisfy({ haystack.contains($0) }) {
                return 755 + min(queryTokens.count, 40)
            }
        }
        if title == query { return 1000 }
        if title.hasPrefix(query) { return 800 }
        if query.hasPrefix(title + " ") { return 780 }
        if keywords.contains(query) { return 700 }
        if let keywordPrefix = keywords
            .filter({ query.hasPrefix($0 + " ") })
            .max(by: { $0.count < $1.count }) {
            return 650 + min(keywordPrefix.count, 40)
        }
        if title.contains(query) { return 500 }
        if keywords.contains(where: { $0.contains(query) }) { return 420 }
        if subtitle.contains(query) { return 240 }
        if category.contains(query) { return 180 }

        guard !queryTokens.isEmpty else { return 0 }
        let haystack = ([title, subtitle, category] + keywords).joined(separator: " ")
        let matched = queryTokens.filter { haystack.contains($0) }.count
        return matched == queryTokens.count ? 120 + matched : 0
    }

    private static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptAware = trimmed.hasPrefix("?") ? String(trimmed.dropFirst()) : trimmed
        return promptAware
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func category(forScope scope: String) -> LauncherCommandCategory? {
        switch scope {
        case "alias", "aliases", "shortcut", "shortcuts":
            return .alias
        case "ai", "ask", "prompt", "prompts":
            return .ai
        case "app", "apps", "application", "applications":
            return .app
        case "calculator", "calculators", "calc", "math":
            return .calculator
        case "clipboard", "clipboards", "clip", "clips", "pasteboard", "pasteboards":
            return .clipboard
        case "cli", "terminal", "shell":
            return .cli
        case "model", "models", "provider", "providers", "llm", "llms":
            return .model
        case "quicklink", "quicklinks", "link", "links":
            return .quicklink
        case "recent", "recents", "history":
            return .recent
        case "script", "scripts", "extension", "extensions":
            return .script
        case "scope", "scopes", "category", "categories", "filter", "filters":
            return .scope
        case "snippet", "snippets", "text", "texts":
            return .snippet
        case "system", "systems", "macos", "mac", "settings", "setting":
            return .system
        case "window", "windows", "layout", "layouts", "resize", "move":
            return .window
        case "workflow", "workflows", "flow", "flows", "automation", "automations":
            return .workflow
        case "workspace", "workspaces", "file", "files", "project":
            return .workspace
        default:
            return nil
        }
    }

    private static func usageBoost(_ record: LauncherCommandUse?) -> Int {
        guard let record else { return 0 }
        return (record.isFavorite ? 10_000 : 0)
            + (record.lastUsedAt == nil ? 0 : 500)
            + min(record.useCount, 100) * 20
    }
}

public struct LauncherCommandSection: Identifiable, Sendable, Hashable {
    public var category: LauncherCommandCategory
    public var commands: [LauncherCommand]

    public var id: String {
        category.rawValue
    }

    public var title: String {
        category.rawValue
    }

    public var count: Int {
        commands.count
    }

    public init(category: LauncherCommandCategory, commands: [LauncherCommand]) {
        self.category = category
        self.commands = commands
    }
}

public enum LauncherCommandSectionFactory {
    public static func sections(from commands: [LauncherCommand]) -> [LauncherCommandSection] {
        var categoryOrder: [LauncherCommandCategory] = []
        var commandsByCategory: [LauncherCommandCategory: [LauncherCommand]] = [:]

        for command in commands {
            if commandsByCategory[command.category] == nil {
                categoryOrder.append(command.category)
            }
            commandsByCategory[command.category, default: []].append(command)
        }

        return categoryOrder.compactMap { category in
            guard let commands = commandsByCategory[category], !commands.isEmpty else { return nil }
            return LauncherCommandSection(category: category, commands: commands)
        }
    }

    public static func visibleCommands(from commands: [LauncherCommand]) -> [LauncherCommand] {
        sections(from: commands).flatMap(\.commands)
    }
}

private struct ScoredCommand {
    var command: LauncherCommand
    var textScore: Int
    var usageBoost: Int
    var record: LauncherCommandUse?
    var index: Int
    var hasQuery: Bool

    var totalScore: Int {
        textScore + usageBoost
    }

    func sortsBefore(_ other: ScoredCommand) -> Bool {
        if totalScore != other.totalScore { return totalScore > other.totalScore }
        if isFavorite != other.isFavorite { return isFavorite }
        if lastUsedAt != other.lastUsedAt {
            return (lastUsedAt ?? .distantPast) > (other.lastUsedAt ?? .distantPast)
        }
        if useCount != other.useCount { return useCount > other.useCount }
        if !hasQuery { return index < other.index }
        return command.title.localizedStandardCompare(other.command.title) == .orderedAscending
    }

    private var isFavorite: Bool {
        record?.isFavorite == true
    }

    private var useCount: Int {
        record?.useCount ?? 0
    }

    private var lastUsedAt: Date? {
        record?.lastUsedAt
    }
}
