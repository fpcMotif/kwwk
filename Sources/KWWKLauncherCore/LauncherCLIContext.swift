import Foundation

public enum LauncherCLIContextStoreError: Error, LocalizedError, Equatable {
    case emptyInput

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "stdin context is empty"
        }
    }
}

public enum LauncherCLIContextStore {
    public static let environmentDirectoryKey = "KWWK_LAUNCHER_CONTEXT_DIR"

    public static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[environmentDirectoryKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kwwk", isDirectory: true)
            .appendingPathComponent("launcher", isDirectory: true)
            .appendingPathComponent("context", isDirectory: true)
    }

    public static func saveStdinContext(
        _ text: String,
        name: String? = nil,
        id: String = UUID().uuidString,
        directory: URL = defaultDirectory()
    ) throws -> URL {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LauncherCLIContextStoreError.emptyInput
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = filenameStem(from: name) ?? "stdin"
        let suffix = filenameStem(from: id) ?? UUID().uuidString.lowercased()
        let url = directory.appendingPathComponent("\(stem)-\(suffix).txt", isDirectory: false)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func filenameStem(from value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        var result = ""
        var previousWasDash = false
        for scalar in trimmed.lowercased().unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasDash = false
            } else if !previousWasDash {
                result.append("-")
                previousWasDash = true
            }
            if result.count >= 48 { break }
        }

        let cleaned = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return cleaned.isEmpty ? nil : cleaned
    }
}

public struct LauncherCLIContextRecord: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var path: String
    public var byteCount: Int
    public var modifiedAt: Date?

    public init(
        id: String,
        title: String,
        path: String,
        byteCount: Int = 0,
        modifiedAt: Date? = nil
    ) {
        self.id = LauncherCLIContextStore.filenameStem(from: id) ?? UUID().uuidString.lowercased()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Terminal Context" : title
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.byteCount = max(0, byteCount)
        self.modifiedAt = modifiedAt
    }

    public var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let homePrefix = home.hasSuffix("/") ? home : home + "/"
        if path.hasPrefix(homePrefix) {
            return "~/" + String(path.dropFirst(homePrefix.count))
        }
        return path
    }

    public var subtitle: String {
        "Terminal context - \(byteCount) bytes - \(displayPath)"
    }

    public var previewText: String {
        [
            title,
            "",
            subtitle,
            "",
            askPrompt,
        ].joined(separator: "\n")
    }

    public func capturedText(maxCharacters: Int = LauncherLocalPathContextBuilder.defaultMaxCharacters) -> String? {
        guard let text = try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let limit = max(0, maxCharacters)
        let excerpt = String(trimmed.prefix(limit))
        let suffix = trimmed.count > limit ? "\n\n[truncated to \(limit) characters]" : ""
        return excerpt + suffix
    }

    public var askPrompt: String {
        var lines = [
            "Use this captured terminal output as context. Explain what matters and suggest the most useful next actions.",
            "",
            "Title: \(title)",
            "Path: \(path)",
        ]
        if let context = LauncherLocalPathContextBuilder.promptContext(
            for: path,
            displayPath: displayPath,
            isDirectory: false
        ) {
            lines += ["", context]
        }
        return lines.joined(separator: "\n")
    }
}

public enum LauncherCLIContextIndex {
    public static let commandPrefix = "cli-context:"
    public static let latestCommandId = "latest-cli-context"

    public static func scan(
        directory: URL = LauncherCLIContextStore.defaultDirectory(),
        limit: Int = 40
    ) -> [LauncherCLIContextRecord] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .compactMap { record(from: $0) }
            .sorted { lhs, rhs in
                switch (lhs.modifiedAt, rhs.modifiedAt) {
                case let (left?, right?) where left != right:
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public static func commands(for records: [LauncherCLIContextRecord]) -> [LauncherCommand] {
        let contextCommands = records.map { command(for: $0) }
        guard let latestRecord = records.first else { return contextCommands }
        return [latestCommand(for: latestRecord)] + contextCommands
    }

    public static func record(for url: URL) -> LauncherCLIContextRecord? {
        record(from: url.standardizedFileURL)
    }

    private static func record(from url: URL) -> LauncherCLIContextRecord? {
        guard url.pathExtension.lowercased() == "txt",
              let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
              ]),
              values.isRegularFile == true
        else {
            return nil
        }

        let stem = url.deletingPathExtension().lastPathComponent
        let title = title(from: stem)
        return LauncherCLIContextRecord(
            id: stem,
            title: title,
            path: url.path,
            byteCount: values.fileSize ?? 0,
            modifiedAt: values.contentModificationDate
        )
    }

    private static func title(from stem: String) -> String {
        let withoutUUID = stem.replacingOccurrences(
            of: #"-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let words = withoutUUID
            .split(separator: "-")
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
        let title = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Terminal Context" : title
    }

    private static func command(for record: LauncherCLIContextRecord) -> LauncherCommand {
        LauncherCommand(
            id: "\(commandPrefix)\(record.id)",
            title: "Ask About \(record.title)",
            subtitle: record.subtitle,
            systemImage: "terminal",
            category: .cli,
            keywords: keywordSet(values: [
                record.id,
                record.title,
                record.path,
                record.displayPath,
                "terminal context",
                "stdin",
                "pipe",
                "cli context",
                "captured output",
                "ask",
                "ai",
            ]),
            action: .askCLIContext(record)
        )
    }

    private static func latestCommand(for record: LauncherCLIContextRecord) -> LauncherCommand {
        LauncherCommand(
            id: latestCommandId,
            title: "Ask About Latest Terminal Context",
            subtitle: "\(record.title) - \(record.subtitle)",
            systemImage: "clock.arrow.circlepath",
            category: .cli,
            keywords: keywordSet(values: [
                "latest",
                "latest terminal context",
                "last",
                "last terminal context",
                "recent",
                "newest",
                "newest terminal output",
                "terminal context",
                "cli context",
                "captured output",
                record.id,
                record.title,
                record.path,
                record.displayPath,
                "stdin",
                "pipe",
                "ask",
                "ai",
            ]),
            action: .askCLIContext(record)
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

public struct LauncherCLIContextExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var path: String
    public var displayPath: String
    public var byteCount: Int
    public var commandId: String
    public var launcherCommand: String

    public init(record: LauncherCLIContextRecord) {
        id = record.id
        title = record.title
        path = record.path
        displayPath = record.displayPath
        byteCount = record.byteCount
        commandId = "\(LauncherCLIContextIndex.commandPrefix)\(record.id)"
        launcherCommand = [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(commandId),
            "--run",
        ].joined(separator: " ")
    }
}

public enum LauncherCLIContextExport {
    public static func records(for records: [LauncherCLIContextRecord]) -> [LauncherCLIContextExportRecord] {
        records.map(LauncherCLIContextExportRecord.init(record:))
    }

    public static func table(for record: LauncherCLIContextRecord) -> String {
        let export = LauncherCLIContextExportRecord(record: record)
        return [
            export.id,
            export.title,
            export.path,
            export.launcherCommand,
        ].joined(separator: "\t")
    }

    public static func table(for records: [LauncherCLIContextRecord]) -> String {
        let exports = self.records(for: records)
        guard !exports.isEmpty else { return "" }
        return exports
            .map { export in
                [
                    export.id,
                    export.title,
                    String(export.byteCount),
                    export.path,
                    export.launcherCommand,
                ]
                .map(tableCell)
                .joined(separator: "\t")
            }
            .joined(separator: "\n")
    }

    public static func json(for record: LauncherCLIContextRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LauncherCLIContextExportRecord(record: record))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func json(for records: [LauncherCLIContextRecord]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self.records(for: records))
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

public struct LauncherSavedArtifactExportRecord: Codable, Sendable, Hashable {
    public var kind: String
    public var id: String
    public var title: String
    public var path: String
    public var commandId: String
    public var launcherCommand: String

    public init(promptCommand: LauncherPromptCommand, path: URL) {
        kind = "promptCommand"
        id = promptCommand.id
        title = promptCommand.title
        self.path = path.standardizedFileURL.path
        commandId = "prompt:\(promptCommand.id)"
        launcherCommand = Self.launcherCommand(commandId: commandId)
    }

    public init(workflow: LauncherWorkflow, path: URL) {
        kind = "workflow"
        id = workflow.id
        title = workflow.title
        self.path = path.standardizedFileURL.path
        commandId = "workflow:\(workflow.id)"
        launcherCommand = Self.launcherCommand(commandId: commandId)
    }

    public init(snippet: LauncherSnippet, path: URL) {
        kind = "snippet"
        id = snippet.id
        title = snippet.title
        self.path = path.standardizedFileURL.path
        commandId = "snippet:\(snippet.id)"
        launcherCommand = Self.launcherCommand(commandId: commandId)
    }

    private static func launcherCommand(commandId: String) -> String {
        [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(commandId),
            "--run",
        ].joined(separator: " ")
    }
}

public enum LauncherSavedArtifactExport {
    public static func table(for record: LauncherSavedArtifactExportRecord) -> String {
        [
            record.kind,
            record.id,
            record.title,
            record.path,
            record.commandId,
            record.launcherCommand,
        ]
        .map(tableCell)
        .joined(separator: "\t")
    }

    public static func json(for record: LauncherSavedArtifactExportRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func tableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
