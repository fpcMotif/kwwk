import Foundation

public struct AIRunHistoryRecord: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var prompt: String
    public var output: String
    public var errorOutput: String
    public var exitCode: Int32
    public var createdAt: Date
    public var model: String?
    public var command: String
    public var workingDirectory: String?

    public init(
        id: String = UUID().uuidString,
        prompt: String,
        output: String,
        errorOutput: String = "",
        exitCode: Int32,
        createdAt: Date = Date(),
        model: String? = nil,
        command: String,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.output = output
        self.errorOutput = errorOutput
        self.exitCode = exitCode
        self.createdAt = createdAt
        self.model = model
        self.command = command
        self.workingDirectory = workingDirectory
    }

    public var succeeded: Bool {
        exitCode == 0
    }

    public var displayTitle: String {
        let firstLine = prompt
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? prompt
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines).truncatedForLauncher(maxLength: 64)
    }

    public var previewText: String {
        output.isEmpty ? errorOutput : output
    }

    public var terminalReplayCommand: String {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return "" }

        let commandWithInput = usesStdinPrompt(trimmedCommand)
            ? "printf %s \(KWWKShellCommand.quote(prompt)) | \(trimmedCommand)"
            : trimmedCommand

        guard let workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty
        else {
            return commandWithInput
        }

        return "cd \(KWWKShellCommand.quote(workingDirectory)) && \(commandWithInput)"
    }

    private func usesStdinPrompt(_ command: String) -> Bool {
        command == "-p -" || command.contains(" -p -") || command.hasSuffix(" -p -")
    }
}

public struct AIRunHistory: Codable, Sendable, Hashable {
    public private(set) var records: [AIRunHistoryRecord]

    public init(records: [AIRunHistoryRecord] = []) {
        self.records = Self.normalized(records)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(records: try container.decodeIfPresent([AIRunHistoryRecord].self, forKey: .records) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
    }

    public func record(id: AIRunHistoryRecord.ID) -> AIRunHistoryRecord? {
        records.first { $0.id == id }
    }

    public mutating func add(_ record: AIRunHistoryRecord, limit: Int = LauncherPreferences.defaultHistoryLimit) {
        let limit = LauncherPreferences.normalizedHistoryLimit(limit)
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        records.sort { $0.createdAt > $1.createdAt }
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
    }

    private static func normalized(_ records: [AIRunHistoryRecord]) -> [AIRunHistoryRecord] {
        var seen = Set<AIRunHistoryRecord.ID>()
        return records
            .filter { !$0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
            }
            .filter { seen.insert($0.id).inserted }
    }

    private enum CodingKeys: String, CodingKey {
        case records
    }
}

public enum AIRunHistoryCommandFactory {
    public static let commandPrefix = "ai-history:"
    public static let latestCommandId = "latest-ai-history"

    public static func commands(for history: AIRunHistory) -> [LauncherCommand] {
        let historyCommands = history.records.map { command(for: $0) }
        guard let latestRecord = history.records.first else { return historyCommands }
        return [latestCommand(for: latestRecord)] + historyCommands
    }

    public static func recordId(for commandId: LauncherCommand.ID) -> AIRunHistoryRecord.ID? {
        guard commandId.hasPrefix(commandPrefix) else { return nil }
        return String(commandId.dropFirst(commandPrefix.count))
    }

    private static func command(for record: AIRunHistoryRecord) -> LauncherCommand {
        LauncherCommand(
            id: "\(commandPrefix)\(record.id)",
            title: record.displayTitle,
            subtitle: record.succeeded ? "AI history" : "Failed AI run",
            systemImage: record.succeeded ? "clock.arrow.circlepath" : "exclamationmark.bubble",
            category: .ai,
            keywords: keywordSet(values: [
                "ai",
                "history",
                "recent",
                "rerun",
                record.prompt,
                record.model ?? "",
            ]),
            action: .rerunAIHistory(record)
        )
    }

    private static func latestCommand(for record: AIRunHistoryRecord) -> LauncherCommand {
        LauncherCommand(
            id: latestCommandId,
            title: "Latest AI Run",
            subtitle: "\(record.succeeded ? "AI history" : "Failed AI run") - \(record.displayTitle)",
            systemImage: record.succeeded ? "clock.arrow.circlepath" : "exclamationmark.bubble",
            category: .ai,
            keywords: keywordSet(values: [
                "latest",
                "latest ai",
                "latest ai history",
                "latest ai run",
                "last",
                "last ai",
                "last ai answer",
                "newest",
                "newest ai run",
                "ai",
                "history",
                "recent",
                "rerun",
                record.prompt,
                record.model ?? "",
            ]),
            action: .rerunAIHistory(record)
        )
    }

    private static func keywordSet(values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

public enum AIRunHistoryStore {
    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".kwwk", isDirectory: true)
            .appendingPathComponent("launcher", isDirectory: true)
            .appendingPathComponent("ai-history.json")
    }

    public static func load(from url: URL = defaultURL()) -> AIRunHistory {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AIRunHistory.self, from: data)
        else {
            return AIRunHistory()
        }
        return decoded
    }

    public static func save(_ history: AIRunHistory, to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(history)
        try data.write(to: url, options: .atomic)
    }

    public static func append(
        _ record: AIRunHistoryRecord,
        limit: Int = LauncherPreferences.defaultHistoryLimit,
        to url: URL = defaultURL()
    ) throws {
        var history = load(from: url)
        history.add(record, limit: limit)
        try save(history, to: url)
    }
}

public struct AIRunHistoryExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var prompt: String
    public var preview: String
    public var output: String
    public var errorOutput: String
    public var exitCode: Int32
    public var succeeded: Bool
    public var createdAt: String
    public var model: String?
    public var command: String
    public var workingDirectory: String?
    public var replayCommand: String

    public init(record: AIRunHistoryRecord) {
        id = record.id
        title = record.displayTitle
        prompt = record.prompt
        preview = record.previewText
        output = record.output
        errorOutput = record.errorOutput
        exitCode = record.exitCode
        succeeded = record.succeeded
        createdAt = AIRunHistoryExport.iso8601String(from: record.createdAt)
        model = record.model
        command = record.command
        workingDirectory = record.workingDirectory
        replayCommand = record.terminalReplayCommand
    }
}

public enum AIRunHistoryExport {
    fileprivate static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func records(for history: AIRunHistory) -> [AIRunHistoryExportRecord] {
        history.records.map(AIRunHistoryExportRecord.init(record:))
    }

    public static func table(for history: AIRunHistory) -> String {
        let rows = records(for: history)
        guard !rows.isEmpty else { return "" }
        return rows
            .map {
                [
                    $0.id,
                    $0.createdAt,
                    String($0.exitCode),
                    $0.title,
                    $0.preview.truncatedForLauncher(maxLength: 96),
                ]
                .map(Self.tableCell)
                .joined(separator: "\t")
            }
            .joined(separator: "\n")
    }

    public static func json(for history: AIRunHistory) throws -> String {
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

private extension String {
    func truncatedForLauncher(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let end = index(startIndex, offsetBy: maxLength)
        return String(self[..<end]) + "..."
    }
}
