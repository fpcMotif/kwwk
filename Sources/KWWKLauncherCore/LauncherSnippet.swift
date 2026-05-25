import Foundation

public struct LauncherSnippet: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var textTemplate: String

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        systemImage: String = "text.quote",
        keywords: [String] = [],
        textTemplate: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.textTemplate = textTemplate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? "text.quote"
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        textTemplate = try container.decodeIfPresent(String.self, forKey: .textTemplate)
            ?? container.decodeIfPresent(String.self, forKey: .template)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decode(String.self, forKey: .snippet)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(systemImage, forKey: .systemImage)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(textTemplate, forKey: .textTemplate)
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

    public func renderedText(
        query: String,
        clipboard: String = "",
        context: LauncherContextSnapshot = LauncherContextSnapshot()
    ) -> String {
        let argument = argument(from: query)
        return textTemplate
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
            renderedText(query: query, clipboard: clipboard, context: context),
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
        case textTemplate
        case template
        case text
        case snippet
    }
}

public enum LauncherSnippetIndex {
    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".kwwk", isDirectory: true)
            .appendingPathComponent("launcher", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    public static func snippet(from record: LauncherClipboardHistoryRecord) -> LauncherSnippet {
        LauncherSnippet(
            id: "clipboard-\(record.id)",
            title: record.title,
            subtitle: "Saved from clipboard history",
            systemImage: "text.quote",
            keywords: ["clipboard", "history", "saved", "snippet"],
            textTemplate: record.text
        )
    }

    public static func snippet(fromAIHistoryOutput record: AIRunHistoryRecord) -> LauncherSnippet? {
        let text = record.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return LauncherSnippet(
            id: "ai-output-\(record.id)",
            title: snippetTitle(from: text, fallback: record.displayTitle),
            subtitle: record.succeeded ? "Saved from AI answer" : "Saved from AI error",
            systemImage: "text.quote",
            keywords: record.succeeded
                ? ["ai", "answer", "history", "saved", "snippet"]
                : ["ai", "error", "history", "saved", "snippet"],
            textTemplate: text
        )
    }

    public static func snippet(
        from record: LauncherCLIContextRecord,
        maxCharacters: Int = LauncherLocalPathContextBuilder.defaultMaxCharacters
    ) -> LauncherSnippet? {
        guard let snippetText = record.capturedText(maxCharacters: maxCharacters) else { return nil }

        return LauncherSnippet(
            id: "cli-context-\(record.id)",
            title: snippetTitle(from: snippetText, fallback: record.title),
            subtitle: "Saved from terminal context",
            systemImage: "terminal",
            keywords: keywordSet(values: [
                "terminal context",
                "cli context",
                "captured output",
                "stdin",
                "saved",
                "snippet",
                record.id,
                record.title,
                record.path,
                record.displayPath,
            ]),
            textTemplate: snippetText
        )
    }

    public static func snippet(
        fromLauncherOutput output: String,
        sourceTitle: String? = nil,
        sourceId: String? = nil
    ) -> LauncherSnippet? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let normalizedSourceTitle = sourceTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let normalizedSourceId = sourceId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let idSeed = [
            normalizedSourceId,
            String(text.prefix(96)),
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return LauncherSnippet(
            id: "launcher-output-\(slug(for: idSeed))",
            title: snippetTitle(from: text, fallback: normalizedSourceTitle ?? "Launcher Result"),
            subtitle: normalizedSourceTitle.map { "Saved from \($0)" } ?? "Saved from launcher result",
            systemImage: "text.quote",
            keywords: keywordSet(values: [
                "launcher",
                "result",
                "output",
                "saved",
                "snippet",
                normalizedSourceTitle ?? "",
                normalizedSourceId ?? "",
            ]),
            textTemplate: text
        )
    }

    public static func snippet(from result: LauncherCalculatorResult) -> LauncherSnippet {
        LauncherSnippet(
            id: "calculator-\(slug(for: result.expression))",
            title: snippetTitle(from: result.displayText, fallback: "Calculator Result"),
            subtitle: "Saved calculator result",
            systemImage: "function",
            keywords: keywordSet(values: [
                "calculator",
                "calc",
                "math",
                "result",
                "saved",
                "snippet",
                result.expression,
                result.formattedValue,
            ]),
            textTemplate: result.displayText
        )
    }

    public static func snippet(from result: LauncherUnitConversionResult) -> LauncherSnippet {
        LauncherSnippet(
            id: "conversion-\(slug(for: result.expression))",
            title: snippetTitle(from: result.displayText, fallback: "Conversion Result"),
            subtitle: "Saved unit conversion",
            systemImage: "arrow.left.arrow.right",
            keywords: keywordSet(values: [
                "conversion",
                "convert",
                "unit",
                "units",
                "result",
                "saved",
                "snippet",
                result.expression,
                result.inputUnit,
                result.outputUnit,
                result.formattedInput,
                result.formattedOutput,
            ]),
            textTemplate: result.displayText
        )
    }

    public static func load(from url: URL = defaultURL(), limit: Int = 200) -> [LauncherSnippet] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        let decoded = (try? decoder.decode([LauncherSnippet].self, from: data))
            ?? (try? decoder.decode(LauncherSnippetDocument.self, from: data))?.snippets
            ?? []

        var seen = Set<String>()
        return decoded
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.textTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    @discardableResult
    public static func upsert(
        _ snippet: LauncherSnippet,
        to url: URL = defaultURL()
    ) throws -> [LauncherSnippet] {
        var snippets = load(from: url, limit: Int.max)
        snippets.removeAll { $0.id == snippet.id }
        snippets.append(snippet)
        try save(snippets, to: url)
        return load(from: url, limit: Int.max)
    }

    public static func save(_ snippets: [LauncherSnippet], to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = snippets.sorted {
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        try encoder.encode(sorted).write(to: url, options: .atomic)
    }

    public static func commands(for snippets: [LauncherSnippet]) -> [LauncherCommand] {
        snippets.map { snippet in
            LauncherCommand(
                id: "snippet:\(snippet.id)",
                title: snippet.title,
                subtitle: snippet.subtitle.isEmpty ? snippet.textTemplate : snippet.subtitle,
                systemImage: snippet.systemImage,
                category: .snippet,
                keywords: keywordSet(values: [
                    snippet.id,
                    snippet.title,
                    snippet.subtitle,
                    "snippet",
                    "snippets",
                    "text",
                    "template",
                    "custom",
                ] + snippet.keywords),
                action: .copySnippet(snippet)
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

    private static func snippetTitle(from text: String, fallback: String) -> String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? fallback
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 72 else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 72)
        return String(trimmed[..<end]) + "..."
    }

    private static func slug(for value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "result" : collapsed
    }
}

public struct LauncherSnippetExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var textTemplate: String
    public var commandId: String
    public var launcherCommand: String
    public var launcherURL: String

    public init(snippet: LauncherSnippet) {
        id = snippet.id
        title = snippet.title
        subtitle = snippet.subtitle
        textTemplate = snippet.textTemplate
        commandId = "snippet:\(snippet.id)"
        launcherCommand = [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(commandId),
            "--run",
            "--",
            KWWKShellCommand.quote("<query>"),
        ].joined(separator: " ")
        launcherURL = LauncherSnippetExport.launcherURL(for: snippet)
    }
}

public enum LauncherSnippetExport {
    public static func records(for snippets: [LauncherSnippet]) -> [LauncherSnippetExportRecord] {
        snippets
            .map(LauncherSnippetExportRecord.init(snippet:))
            .sorted { lhs, rhs in
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    public static func table(for snippets: [LauncherSnippet]) -> String {
        let rows = records(for: snippets)
        guard !rows.isEmpty else { return "" }
        return rows
            .map {
                [
                    $0.id,
                    $0.title,
                    $0.subtitle,
                    $0.textTemplate,
                    $0.launcherCommand,
                ]
                .map(tableCell)
                .joined(separator: "\t")
            }
            .joined(separator: "\n")
    }

    public static func json(for snippets: [LauncherSnippet]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: snippets))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public static func json(for snippet: LauncherSnippet) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LauncherSnippetExportRecord(snippet: snippet))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func launcherURL(
        for snippet: LauncherSnippet,
        query: String = "",
        workingDirectory: String? = nil
    ) -> String {
        let command = LauncherSnippetIndex.commands(for: [snippet])[0]
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

private struct LauncherSnippetDocument: Codable {
    var snippets: [LauncherSnippet]
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
