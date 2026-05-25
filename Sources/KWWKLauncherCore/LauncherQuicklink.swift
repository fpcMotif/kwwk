import Foundation

public struct LauncherQuicklink: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var urlTemplate: String

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        systemImage: String = "link",
        keywords: [String] = [],
        urlTemplate: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.urlTemplate = urlTemplate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? "link"
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        urlTemplate = try container.decode(String.self, forKey: .urlTemplate)
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

    public func renderedURLString(query: String) -> String {
        let argument = argument(from: query)
        let encoded = Self.percentEncode(argument)
        return urlTemplate
            .replacingOccurrences(of: "{query}", with: encoded)
            .replacingOccurrences(of: "{Query}", with: encoded)
            .replacingOccurrences(of: "{argument}", with: encoded)
            .replacingOccurrences(of: "{Argument}", with: encoded)
    }

    public func url(query: String) -> URL? {
        URL(string: renderedURLString(query: query))
    }

    public func previewText(query: String) -> String {
        [
            subtitle.nilIfEmpty,
            renderedURLString(query: query),
            usesArgument ? "Query fills {query} or {argument}." : "Opens a fixed URL.",
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    private var usesArgument: Bool {
        urlTemplate.contains("{query}")
            || urlTemplate.contains("{Query}")
            || urlTemplate.contains("{argument}")
            || urlTemplate.contains("{Argument}")
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum LauncherQuicklinkIndex {
    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".kwwk", isDirectory: true)
            .appendingPathComponent("launcher", isDirectory: true)
            .appendingPathComponent("quicklinks.json")
    }

    public static func quicklink(fromDynamicCommand command: LauncherCommand) -> LauncherQuicklink? {
        guard case .openQuicklink(let quicklink) = command.action else {
            return nil
        }

        if command.id.hasPrefix(LauncherWebCommandFactory.searchCommandPrefix) {
            return searchQuicklink(from: command, quicklink: quicklink)
        }

        guard command.id.hasPrefix(LauncherWebCommandFactory.urlCommandPrefix) else {
            return nil
        }
        return urlQuicklink(from: command, quicklink: quicklink)
    }

    private static func urlQuicklink(
        from command: LauncherCommand,
        quicklink: LauncherQuicklink
    ) -> LauncherQuicklink? {
        let urlString = quicklink.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
        let slug = slug(for: [url.host(percentEncoded: false), url.path].compactMap { $0 })
        let title = title(for: url, fallback: command.title)
        let host = url.host(percentEncoded: false) ?? ""

        return LauncherQuicklink(
            id: "saved-\(slug)",
            title: title,
            subtitle: "Saved URL",
            systemImage: quicklink.systemImage,
            keywords: keywordSet(values: [
                "saved",
                "quicklink",
                "url",
                "link",
                host,
                urlString,
            ] + quicklink.keywords),
            urlTemplate: urlString
        )
    }

    private static func searchQuicklink(
        from command: LauncherCommand,
        quicklink: LauncherQuicklink
    ) -> LauncherQuicklink? {
        let searchText = String(command.id.dropFirst(LauncherWebCommandFactory.searchCommandPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else { return nil }

        let words = words(from: searchText)
        let renderedURL = quicklink.renderedURLString(query: "web \(searchText)")
        return LauncherQuicklink(
            id: "saved-search-\(slug(for: [searchText]))",
            title: "Search \(title(for: words))",
            subtitle: "Saved web search",
            systemImage: quicklink.systemImage,
            keywords: keywordSet(values: [
                "saved",
                "quicklink",
                "search",
                "web",
                "duckduckgo",
                searchText,
            ] + words + quicklink.keywords),
            urlTemplate: renderedURL
        )
    }

    public static func load(from url: URL = defaultURL(), limit: Int = 200) -> [LauncherQuicklink] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        let decoded = (try? decoder.decode([LauncherQuicklink].self, from: data))
            ?? (try? decoder.decode(LauncherQuicklinkDocument.self, from: data))?.quicklinks
            ?? []

        var seen = Set<String>()
        return decoded
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    @discardableResult
    public static func upsert(
        _ quicklink: LauncherQuicklink,
        to url: URL = defaultURL()
    ) throws -> [LauncherQuicklink] {
        var quicklinks = load(from: url, limit: Int.max)
        quicklinks.removeAll { $0.id == quicklink.id }
        quicklinks.append(quicklink)
        try save(quicklinks, to: url)
        return load(from: url, limit: Int.max)
    }

    public static func save(_ quicklinks: [LauncherQuicklink], to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = quicklinks.sorted {
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        try encoder.encode(sorted).write(to: url, options: .atomic)
    }

    public static func commands(for quicklinks: [LauncherQuicklink]) -> [LauncherCommand] {
        quicklinks.map { quicklink in
            LauncherCommand(
                id: "quicklink:\(quicklink.id)",
                title: quicklink.title,
                subtitle: quicklink.subtitle.isEmpty ? quicklink.urlTemplate : quicklink.subtitle,
                systemImage: quicklink.systemImage,
                category: .quicklink,
                keywords: keywordSet(values: [
                    quicklink.id,
                    quicklink.title,
                    quicklink.subtitle,
                    quicklink.urlTemplate,
                    "quicklink",
                    "url",
                    "link",
                ] + quicklink.keywords),
                action: .openQuicklink(quicklink)
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

    private static func title(for url: URL, fallback: String) -> String {
        let hostWords = hostWords(from: url.host(percentEncoded: false) ?? "")
        let pathWords = url.pathComponents
            .filter { $0 != "/" }
            .flatMap(words(from:))
        let words = Array((hostWords + pathWords).prefix(4))
        guard !words.isEmpty else { return fallback.trimmingCharacters(in: .whitespacesAndNewlines) }
        return title(for: words)
    }

    private static func title(for words: [String]) -> String {
        let title = words.prefix(4).map(capitalizedWord).joined(separator: " ")
        return title.isEmpty ? "Web" : title
    }

    private static func hostWords(from host: String) -> [String] {
        host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { !["www", "com", "org", "net", "io", "dev", "app"].contains($0) }
            .flatMap(words(from:))
    }

    private static func words(from value: String) -> [String] {
        value
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func capitalizedWord(_ value: String) -> String {
        value.prefix(1).uppercased() + String(value.dropFirst())
    }

    private static func slug(for values: [String]) -> String {
        let scalars = values.joined(separator: " ").lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.isEmpty ? "quicklink" : collapsed
    }
}

public struct LauncherQuicklinkExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var urlTemplate: String
    public var commandId: String
    public var launcherCommand: String
    public var launcherURL: String

    public init(quicklink: LauncherQuicklink) {
        id = quicklink.id
        title = quicklink.title
        subtitle = quicklink.subtitle
        urlTemplate = quicklink.urlTemplate
        commandId = "quicklink:\(quicklink.id)"
        launcherCommand = [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(commandId),
            "--run",
            "--",
            KWWKShellCommand.quote("<query>"),
        ].joined(separator: " ")
        launcherURL = LauncherQuicklinkExport.launcherURL(for: quicklink)
    }
}

public enum LauncherQuicklinkExport {
    public static func records(for quicklinks: [LauncherQuicklink]) -> [LauncherQuicklinkExportRecord] {
        quicklinks
            .map(LauncherQuicklinkExportRecord.init(quicklink:))
            .sorted { lhs, rhs in
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    public static func table(for quicklinks: [LauncherQuicklink]) -> String {
        let rows = records(for: quicklinks)
        guard !rows.isEmpty else { return "" }
        return rows
            .map {
                [
                    $0.id,
                    $0.title,
                    $0.subtitle,
                    $0.urlTemplate,
                    $0.launcherCommand,
                ]
                .map(tableCell)
                .joined(separator: "\t")
            }
            .joined(separator: "\n")
    }

    public static func json(for quicklinks: [LauncherQuicklink]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: quicklinks))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public static func json(for quicklink: LauncherQuicklink) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LauncherQuicklinkExportRecord(quicklink: quicklink))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func launcherURL(
        for quicklink: LauncherQuicklink,
        query: String = "",
        workingDirectory: String? = nil
    ) -> String {
        let command = LauncherQuicklinkIndex.commands(for: [quicklink])[0]
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

private struct LauncherQuicklinkDocument: Codable {
    var quicklinks: [LauncherQuicklink]
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
