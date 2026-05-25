import Foundation

public struct LauncherClipboardHistoryRecord: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var text: String
    public var copiedAt: Date

    public init(id: String? = nil, text: String, copiedAt: Date = Date()) {
        self.text = text
        self.copiedAt = copiedAt
        self.id = id ?? Self.stableID(for: text)
    }

    public var title: String {
        let firstLine = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? "Clipboard Text"
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            .truncatedForClipboard(maxLength: 72)
    }

    public var subtitle: String {
        text.singleLineClipboardPreview(maxLength: 96)
    }

    public var previewText: String {
        text
    }

    private static func stableID(for text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }
}

public struct LauncherClipboardHistory: Codable, Sendable, Hashable {
    public var records: [LauncherClipboardHistoryRecord]

    public init(records: [LauncherClipboardHistoryRecord] = []) {
        self.records = Self.normalized(records)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(records: try container.decodeIfPresent([LauncherClipboardHistoryRecord].self, forKey: .records) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
    }

    @discardableResult
    public mutating func add(
        _ text: String,
        copiedAt: Date = Date(),
        limit: Int = 80
    ) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let record = LauncherClipboardHistoryRecord(text: text, copiedAt: copiedAt)
        records.removeAll { $0.id == record.id || $0.text == text }
        records.insert(record, at: 0)
        records = Array(records.prefix(max(0, limit)))
        return true
    }

    public mutating func clear() {
        records.removeAll()
    }

    public func record(id: String) -> LauncherClipboardHistoryRecord? {
        records.first { $0.id == id }
    }

    private static func normalized(_ records: [LauncherClipboardHistoryRecord]) -> [LauncherClipboardHistoryRecord] {
        var seen = Set<String>()
        return records
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.copiedAt != rhs.copiedAt { return lhs.copiedAt > rhs.copiedAt }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .filter { seen.insert($0.id).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case records
    }
}

public enum LauncherClipboardHistoryCommandFactory {
    public static let commandPrefix = "clipboard:"
    public static let latestCommandId = "latest-clipboard"

    public static func commands(
        for history: LauncherClipboardHistory,
        limit: Int = 40
    ) -> [LauncherCommand] {
        let recordCommands = history.records
            .prefix(max(0, limit))
            .map { command(for: $0) }
        guard let latestRecord = history.records.first else { return recordCommands }
        return [latestCommand(for: latestRecord)] + recordCommands
    }

    public static func recordId(for commandId: LauncherCommand.ID) -> String? {
        guard commandId.hasPrefix(commandPrefix) else { return nil }
        return String(commandId.dropFirst(commandPrefix.count))
    }

    private static func command(for record: LauncherClipboardHistoryRecord) -> LauncherCommand {
        LauncherCommand(
            id: "\(commandPrefix)\(record.id)",
            title: record.title,
            subtitle: record.subtitle,
            systemImage: "doc.on.clipboard",
            category: .clipboard,
            keywords: keywordSet(values: [
                "clipboard",
                "history",
                "pasteboard",
                "copy",
                "paste",
                record.text,
            ]),
            action: .copyClipboardHistory(record)
        )
    }

    private static func latestCommand(for record: LauncherClipboardHistoryRecord) -> LauncherCommand {
        LauncherCommand(
            id: latestCommandId,
            title: "Latest Clipboard",
            subtitle: record.subtitle,
            systemImage: "doc.on.clipboard",
            category: .clipboard,
            keywords: keywordSet(values: [
                "latest",
                "latest clipboard",
                "last",
                "last clipboard",
                "recent",
                "newest",
                "clipboard",
                "history",
                "pasteboard",
                "copy",
                "paste",
                record.text,
            ]),
            action: .copyClipboardHistory(record)
        )
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
}

public struct LauncherClipboardHistoryExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var text: String
    public var preview: String
    public var copiedAt: String
    public var commandId: String
    public var launcherCommand: String

    public init(record: LauncherClipboardHistoryRecord) {
        id = record.id
        title = record.title
        text = record.text
        preview = record.subtitle
        copiedAt = LauncherClipboardHistoryExport.iso8601String(from: record.copiedAt)
        commandId = "\(LauncherClipboardHistoryCommandFactory.commandPrefix)\(record.id)"
        launcherCommand = [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(commandId),
            "--run",
        ].joined(separator: " ")
    }
}

public enum LauncherClipboardHistoryExport {
    fileprivate static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func records(for history: LauncherClipboardHistory) -> [LauncherClipboardHistoryExportRecord] {
        history.records.map(LauncherClipboardHistoryExportRecord.init(record:))
    }

    public static func table(for history: LauncherClipboardHistory) -> String {
        let rows = records(for: history)
        guard !rows.isEmpty else { return "" }
        return rows
            .map { row in
                [
                    row.id,
                    row.copiedAt,
                    row.title,
                    row.preview,
                    row.launcherCommand,
                ]
                .map(tableCell)
                .joined(separator: "\t")
            }
            .joined(separator: "\n")
    }

    public static func json(for history: LauncherClipboardHistory) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: history))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func tableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LauncherClipboardHistoryStore {
    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".kwwk", isDirectory: true)
            .appendingPathComponent("launcher", isDirectory: true)
            .appendingPathComponent("clipboard-history.json")
    }

    public static func load(from url: URL = defaultURL()) -> LauncherClipboardHistory {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LauncherClipboardHistory.self, from: data)
        else {
            return LauncherClipboardHistory()
        }
        return decoded
    }

    public static func save(_ history: LauncherClipboardHistory, to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        try data.write(to: url, options: .atomic)
    }
}

private extension String {
    func singleLineClipboardPreview(maxLength: Int) -> String {
        let normalized = split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.truncatedForClipboard(maxLength: maxLength)
    }

    func truncatedForClipboard(maxLength: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<end]) + "..."
    }
}
