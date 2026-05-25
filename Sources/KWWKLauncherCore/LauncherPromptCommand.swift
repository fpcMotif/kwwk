import Foundation

public struct LauncherPromptCommand: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var promptTemplate: String

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        systemImage: String = "sparkles",
        keywords: [String] = [],
        promptTemplate: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.promptTemplate = promptTemplate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? "sparkles"
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        promptTemplate = try container.decodeIfPresent(String.self, forKey: .promptTemplate)
            ?? container.decodeIfPresent(String.self, forKey: .template)
            ?? container.decode(String.self, forKey: .prompt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(systemImage, forKey: .systemImage)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(promptTemplate, forKey: .promptTemplate)
    }

    public func argument(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let triggers = ([title] + keywords)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        for trigger in triggers {
            if trimmed.caseInsensitiveCompare(trigger) == .orderedSame {
                return ""
            }

            guard trimmed.count > trigger.count else { continue }
            let triggerEnd = trimmed.index(trimmed.startIndex, offsetBy: trigger.count)
            guard trimmed[..<triggerEnd].caseInsensitiveCompare(trigger) == .orderedSame,
                  trimmed[triggerEnd].isWhitespace
            else {
                continue
            }

            return String(trimmed[triggerEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    public func renderedPrompt(
        query: String,
        clipboard: String = "",
        context: LauncherContextSnapshot = LauncherContextSnapshot()
    ) -> String {
        let argument = argument(from: query)
        return promptTemplate
            .replacingOccurrences(of: "{query}", with: argument)
            .replacingOccurrences(of: "{Query}", with: argument)
            .replacingOccurrences(of: "{argument}", with: argument)
            .replacingOccurrences(of: "{Argument}", with: argument)
            .replacingOccurrences(of: "{clipboard}", with: clipboard)
            .replacingOccurrences(of: "{Clipboard}", with: clipboard)
            .replacingOccurrences(of: "{workspace}", with: context.workingDirectory ?? "")
            .replacingOccurrences(of: "{Workspace}", with: context.workingDirectory ?? "")
            .replacingOccurrences(of: "{cwd}", with: context.workingDirectory ?? "")
            .replacingOccurrences(of: "{Cwd}", with: context.workingDirectory ?? "")
            .replacingOccurrences(of: "{finderSelection}", with: context.finderSelectionPaths.joined(separator: "\n"))
            .replacingOccurrences(of: "{FinderSelection}", with: context.finderSelectionPaths.joined(separator: "\n"))
            .replacingOccurrences(of: "{frontmostApp}", with: context.frontmostApplicationName ?? "")
            .replacingOccurrences(of: "{FrontmostApp}", with: context.frontmostApplicationName ?? "")
    }

    public func previewText(
        query: String,
        clipboard: String = "",
        context: LauncherContextSnapshot = LauncherContextSnapshot()
    ) -> String {
        [
            subtitle.nilIfEmpty,
            renderedPrompt(query: query, clipboard: clipboard, context: context),
            "Placeholders: {query}, {clipboard}, {workspace}, {finderSelection}, {frontmostApp}.",
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case systemImage
        case keywords
        case promptTemplate
        case template
        case prompt
    }
}

public enum LauncherPromptCommandIndex {
    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".kwwk", isDirectory: true)
            .appendingPathComponent("launcher", isDirectory: true)
            .appendingPathComponent("prompts.json")
    }

    public static func promptCommand(from record: AIRunHistoryRecord) -> LauncherPromptCommand {
        LauncherPromptCommand(
            id: "history-\(record.id)",
            title: record.displayTitle,
            subtitle: "Saved from AI history",
            systemImage: "sparkles",
            keywords: ["ai", "history", "saved", "prompt"],
            promptTemplate: record.prompt
        )
    }

    public static func promptCommand(from record: LauncherCLIContextRecord) -> LauncherPromptCommand {
        LauncherPromptCommand(
            id: "cli-context-\(record.id)",
            title: "Ask About \(record.title)",
            subtitle: "Saved terminal context prompt",
            systemImage: "terminal",
            keywords: keywordSet(values: [
                "ai",
                "prompt",
                "saved",
                "terminal context",
                "cli context",
                "captured output",
                "stdin",
                record.id,
                record.title,
                record.path,
                record.displayPath,
            ]),
            promptTemplate: record.askPrompt
        )
    }

    public static func promptCommand(fromPrompt prompt: String) -> LauncherPromptCommand? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let words = promptWords(trimmed)

        return LauncherPromptCommand(
            id: "saved-\(slug(for: words))",
            title: title(for: words),
            subtitle: "Saved prompt",
            systemImage: "sparkles",
            keywords: keywordSet(values: ["ai", "prompt", "saved"] + words),
            promptTemplate: trimmed
        )
    }

    public static func load(from url: URL = defaultURL(), limit: Int = 200) -> [LauncherPromptCommand] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        let decoded = (try? decoder.decode([LauncherPromptCommand].self, from: data))
            ?? (try? decoder.decode(LauncherPromptCommandDocument.self, from: data))?.prompts
            ?? []

        var seen = Set<String>()
        return decoded
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    @discardableResult
    public static func upsert(
        _ promptCommand: LauncherPromptCommand,
        to url: URL = defaultURL()
    ) throws -> [LauncherPromptCommand] {
        var promptCommands = load(from: url, limit: Int.max)
        promptCommands.removeAll { $0.id == promptCommand.id }
        promptCommands.append(promptCommand)
        try save(promptCommands, to: url)
        return load(from: url, limit: Int.max)
    }

    public static func save(_ promptCommands: [LauncherPromptCommand], to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = promptCommands.sorted {
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        try encoder.encode(sorted).write(to: url, options: .atomic)
    }

    public static func commands(for promptCommands: [LauncherPromptCommand]) -> [LauncherCommand] {
        promptCommands.map { template in
            LauncherCommand(
                id: "prompt:\(template.id)",
                title: template.title,
                subtitle: template.subtitle.isEmpty ? template.promptTemplate : template.subtitle,
                systemImage: template.systemImage,
                category: .ai,
                keywords: keywordSet(values: [
                    template.id,
                    template.title,
                    template.subtitle,
                    "ai prompt",
                    "prompt",
                    "template",
                    "custom",
                ] + template.keywords),
                action: .runPromptCommand(template)
            )
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

    private static func promptWords(_ prompt: String) -> [String] {
        prompt
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func title(for words: [String]) -> String {
        let title = words.prefix(4)
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
        return title.isEmpty ? "Saved Prompt" : title
    }

    private static func slug(for words: [String]) -> String {
        let scalars = words.joined(separator: " ").lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "prompt" : collapsed
    }
}

public struct LauncherPromptCommandExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var promptTemplate: String
    public var commandId: String
    public var launcherCommand: String
    public var launcherURL: String

    public init(promptCommand: LauncherPromptCommand) {
        id = promptCommand.id
        title = promptCommand.title
        subtitle = promptCommand.subtitle
        promptTemplate = promptCommand.promptTemplate
        commandId = "prompt:\(promptCommand.id)"
        launcherCommand = [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(commandId),
            "--run",
            "--",
            KWWKShellCommand.quote("<query>"),
        ].joined(separator: " ")
        launcherURL = LauncherPromptCommandExport.launcherURL(for: promptCommand)
    }
}

public enum LauncherPromptCommandExport {
    public static func records(for promptCommands: [LauncherPromptCommand]) -> [LauncherPromptCommandExportRecord] {
        promptCommands
            .map(LauncherPromptCommandExportRecord.init(promptCommand:))
            .sorted { lhs, rhs in
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    public static func table(for promptCommands: [LauncherPromptCommand]) -> String {
        let rows = records(for: promptCommands)
        guard !rows.isEmpty else { return "" }
        return rows
            .map {
                [
                    $0.id,
                    $0.title,
                    $0.subtitle,
                    $0.promptTemplate,
                    $0.launcherCommand,
                ]
                .map(tableCell)
                .joined(separator: "\t")
            }
            .joined(separator: "\n")
    }

    public static func json(for promptCommands: [LauncherPromptCommand]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: promptCommands))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public static func json(for promptCommand: LauncherPromptCommand) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LauncherPromptCommandExportRecord(promptCommand: promptCommand))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func launcherURL(
        for promptCommand: LauncherPromptCommand,
        query: String = "",
        workingDirectory: String? = nil
    ) -> String {
        let command = LauncherPromptCommandIndex.commands(for: [promptCommand])[0]
        return LauncherActionCatalog.launcherURL(
            for: command,
            query: query,
            workingDirectory: workingDirectory
        )
    }

    private static func tableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct LauncherPromptCommandDocument: Codable {
    var prompts: [LauncherPromptCommand]
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
