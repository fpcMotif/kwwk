import Foundation

public enum LauncherScriptArgumentMode: String, Codable, Sendable, Hashable {
    case none
    case argument
    case stdin
}

public struct LauncherScriptCommand: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var scriptPath: String
    public var workingDirectory: String?
    public var arguments: [String]
    public var argumentMode: LauncherScriptArgumentMode

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String = "terminal",
        keywords: [String] = [],
        scriptPath: String,
        workingDirectory: String? = nil,
        arguments: [String] = [],
        argumentMode: LauncherScriptArgumentMode = .none
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.scriptPath = scriptPath
        self.workingDirectory = workingDirectory
        self.arguments = arguments
        self.argumentMode = argumentMode
    }

    public func invocation(query: String = "", workingDirectoryOverride: String? = nil) -> KWWKCLIInvocation {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var invocationArguments = arguments
        var stdin: String?

        if !trimmedQuery.isEmpty {
            switch argumentMode {
            case .none:
                break
            case .argument:
                invocationArguments.append(trimmedQuery)
            case .stdin:
                stdin = trimmedQuery
            }
        }
        let launcherWorkingDirectory = normalizedWorkingDirectory(workingDirectoryOverride)
        let resolvedWorkingDirectory = workingDirectory
            ?? launcherWorkingDirectory
            ?? URL(fileURLWithPath: scriptPath)
                .deletingLastPathComponent()
                .path
        var environment = [
            "KWWK_LAUNCHER_QUERY": query,
            "KWWK_LAUNCHER_CWD": resolvedWorkingDirectory,
        ]
        if let launcherWorkingDirectory {
            environment["KWWK_LAUNCHER_WORKSPACE"] = launcherWorkingDirectory
        }

        return KWWKCLIInvocation(
            executable: scriptPath,
            arguments: invocationArguments,
            stdin: stdin,
            workingDirectory: resolvedWorkingDirectory,
            environment: environment
        )
    }

    public var previewText: String {
        let queryHandling: String
        switch argumentMode {
        case .none:
            queryHandling = "Query is available as KWWK_LAUNCHER_QUERY."
        case .argument:
            queryHandling = "Query is passed as the final argument."
        case .stdin:
            queryHandling = "Query is sent to stdin."
        }

        return [
            subtitle,
            "",
            scriptPath,
            arguments.isEmpty ? nil : "Arguments: \(arguments.joined(separator: " "))",
            queryHandling,
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}

public struct LauncherScriptCommandDraft: Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var commandText: String
    public var fileName: String
    public var scriptText: String

    public init(
        id: String,
        title: String,
        subtitle: String,
        commandText: String,
        fileName: String,
        scriptText: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.commandText = commandText
        self.fileName = fileName
        self.scriptText = scriptText
    }
}

private func normalizedWorkingDirectory(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
        .standardizedFileURL
        .path
}

public enum LauncherScriptCommandIndex {
    public static func defaultRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            homeDirectory
                .appendingPathComponent(".kwwk", isDirectory: true)
                .appendingPathComponent("launcher", isDirectory: true)
                .appendingPathComponent("commands", isDirectory: true),
        ]
    }

    public static func scan(roots: [URL], maxDepth: Int = 1, limit: Int = 200) -> [LauncherScriptCommand] {
        var results: [LauncherScriptCommand] = []
        var seenPaths = Set<String>()

        for root in roots {
            scanDirectory(root, depth: 0, maxDepth: maxDepth, limit: limit, seenPaths: &seenPaths, results: &results)
            if results.count >= limit { break }
        }

        return results
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    public static func commands(for scripts: [LauncherScriptCommand]) -> [LauncherCommand] {
        scripts.map { script in
            LauncherCommand(
                id: "script:\(script.id)",
                title: script.title,
                subtitle: script.subtitle,
                systemImage: script.systemImage,
                category: .script,
                keywords: script.keywords,
                action: .runScript(script)
            )
        }
    }

    public static func scriptDraft(fromShellCommand commandText: String) -> LauncherScriptCommandDraft? {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let words = shellCommandWords(trimmed)
        let slug = slug(for: words.isEmpty ? trimmed : words.joined(separator: "-"))
        let id = "saved-\(slug)"
        let title = title(for: words.isEmpty ? [trimmed] : words)
        let keywords = keywordSet(values: ["shell", "command", "saved"] + words)
        let scriptText = """
        #!/usr/bin/env zsh
        # @kwwk.id \(id)
        # @kwwk.title \(title)
        # @kwwk.subtitle Saved shell command
        # @kwwk.keywords \(keywords.joined(separator: ", "))
        # @kwwk.icon terminal
        set -euo pipefail

        \(trimmed)
        """

        return LauncherScriptCommandDraft(
            id: id,
            title: title,
            subtitle: "Saved shell command",
            commandText: trimmed,
            fileName: "\(id).zsh",
            scriptText: scriptText + "\n"
        )
    }

    @discardableResult
    public static func save(
        _ draft: LauncherScriptCommandDraft,
        to root: URL = defaultRoots()[0]
    ) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(draft.fileName)
        try draft.scriptText.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private static func scanDirectory(
        _ directory: URL,
        depth: Int,
        maxDepth: Int,
        limit: Int,
        seenPaths: inout Set<String>,
        results: inout [LauncherScriptCommand]
    ) {
        guard results.count < limit else { return }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in children {
            guard results.count < limit else { return }
            let standardized = child.standardizedFileURL

            if FileManager.default.isExecutableFile(atPath: standardized.path),
               let command = command(for: standardized),
               seenPaths.insert(standardized.path).inserted {
                results.append(command)
                continue
            }

            guard depth < maxDepth else { continue }
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            scanDirectory(
                standardized,
                depth: depth + 1,
                maxDepth: maxDepth,
                limit: limit,
                seenPaths: &seenPaths,
                results: &results
            )
        }
    }

    private static func command(for scriptURL: URL) -> LauncherScriptCommand? {
        guard let text = try? String(contentsOf: scriptURL, encoding: .utf8) else { return nil }
        let metadata = ScriptMetadata.parse(text)
        let fileName = scriptURL.deletingPathExtension().lastPathComponent
        let title = metadata.title ?? titleFromFileName(fileName)
        let subtitle = metadata.subtitle ?? "Run \(scriptURL.lastPathComponent)"
        let keywords = keywordSet(
            values: [fileName, title, subtitle, "script", "automation"] + metadata.keywords
        )

        return LauncherScriptCommand(
            id: metadata.id ?? scriptURL.path,
            title: title,
            subtitle: subtitle,
            systemImage: metadata.systemImage ?? "terminal",
            keywords: keywords,
            scriptPath: scriptURL.path,
            workingDirectory: metadata.workingDirectory,
            arguments: metadata.arguments,
            argumentMode: metadata.argumentMode
        )
    }

    private static func titleFromFileName(_ value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
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

    private static func shellCommandWords(_ value: String) -> [String] {
        value
            .split { character in
                character.isWhitespace || "|&;()[]{}'\"`$<>".contains(character)
            }
            .map(String.init)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .map { $0 }
    }

    private static func title(for words: [String]) -> String {
        let titleWords = words.prefix(4).map { word in
            word
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { part in part.prefix(1).uppercased() + part.dropFirst() }
                .joined(separator: " ")
        }
        return titleWords.joined(separator: " ")
    }

    private static func slug(for value: String) -> String {
        let characters = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let slug = String(characters)
            .split(separator: "-")
            .joined(separator: "-")
        return slug.isEmpty ? "command" : slug
    }
}

public struct LauncherScriptCommandExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var scriptPath: String
    public var workingDirectory: String?
    public var argumentMode: String
    public var arguments: [String]
    public var commandId: String
    public var launcherCommand: String
    public var launcherURL: String

    public init(script: LauncherScriptCommand) {
        id = script.id
        title = script.title
        subtitle = script.subtitle
        scriptPath = script.scriptPath
        workingDirectory = script.workingDirectory
        argumentMode = script.argumentMode.rawValue
        arguments = script.arguments
        commandId = "script:\(script.id)"
        launcherCommand = LauncherScriptCommandExport.launcherCommand(for: script)
        launcherURL = LauncherScriptCommandExport.launcherURL(for: script)
    }
}

public enum LauncherScriptCommandExport {
    public static func records(for scripts: [LauncherScriptCommand]) -> [LauncherScriptCommandExportRecord] {
        scripts
            .map(LauncherScriptCommandExportRecord.init(script:))
            .sorted { lhs, rhs in
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    public static func table(for scripts: [LauncherScriptCommand]) -> String {
        let rows = records(for: scripts)
        guard !rows.isEmpty else { return "" }
        return rows
            .map {
                [
                    $0.id,
                    $0.title,
                    $0.subtitle,
                    $0.argumentMode,
                    $0.scriptPath,
                    $0.launcherCommand,
                ]
                .map(tableCell)
                .joined(separator: "\t")
            }
            .joined(separator: "\n")
    }

    public static func json(for scripts: [LauncherScriptCommand]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: scripts))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public static func json(for script: LauncherScriptCommand) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(LauncherScriptCommandExportRecord(script: script))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func launcherCommand(for script: LauncherScriptCommand, query: String = "") -> String {
        var parts = [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote("script:\(script.id)"),
            "--run",
        ]
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryArgument: String?
        if !trimmedQuery.isEmpty {
            queryArgument = trimmedQuery
        } else {
            queryArgument = script.argumentMode == .none ? nil : "<query>"
        }
        if let queryArgument {
            parts += ["--", KWWKShellCommand.quote(queryArgument)]
        }
        return parts.joined(separator: " ")
    }

    public static func launcherURL(
        for script: LauncherScriptCommand,
        query: String = "",
        workingDirectory: String? = nil
    ) -> String {
        let command = LauncherScriptCommandIndex.commands(for: [script])[0]
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

private struct ScriptMetadata {
    var id: String?
    var title: String?
    var subtitle: String?
    var systemImage: String?
    var keywords: [String] = []
    var workingDirectory: String?
    var arguments: [String] = []
    var argumentMode: LauncherScriptArgumentMode = .none

    static func parse(_ text: String) -> ScriptMetadata {
        var metadata = ScriptMetadata()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(64) {
            guard let directive = directiveBody(String(line)) else { continue }
            let parsed = parseDirective(directive)

            switch parsed.key {
            case "kwwk.id":
                metadata.id = parsed.value.nilIfEmpty
            case "kwwk.title", "raycast.title":
                metadata.title = parsed.value.nilIfEmpty
            case "kwwk.subtitle", "raycast.subtitle":
                metadata.subtitle = parsed.value.nilIfEmpty
            case "kwwk.icon", "kwwk.systemimage", "kwwk.system-image":
                metadata.systemImage = parsed.value.nilIfEmpty
            case "kwwk.keywords", "kwwk.keyword", "raycast.packagename":
                metadata.keywords += splitKeywords(parsed.value)
            case "kwwk.cwd", "kwwk.workingdirectory", "kwwk.working-directory":
                metadata.workingDirectory = parsed.value.nilIfEmpty
            case "kwwk.arguments", "kwwk.args":
                metadata.arguments = splitShellWords(parsed.value)
            case "kwwk.argumentmode", "kwwk.argument-mode", "kwwk.query-mode":
                metadata.argumentMode = LauncherScriptArgumentMode(rawValue: parsed.value.normalizedDirectiveKey)
                    ?? metadata.argumentMode
            case "raycast.argument1":
                metadata.argumentMode = .argument
            default:
                break
            }
        }
        return metadata
    }

    private static func directiveBody(_ line: String) -> String? {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#!") { return nil }

        for prefix in ["#", "//", "--"] {
            guard trimmed.hasPrefix(prefix) else { continue }
            trimmed = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("@kwwk.") || trimmed.hasPrefix("@raycast.") || trimmed.hasPrefix("kwwk.") {
                return trimmed
            }
        }

        return nil
    }

    private static func parseDirective(_ directive: String) -> (key: String, value: String) {
        let withoutMarker = directive.hasPrefix("@") ? String(directive.dropFirst()) : directive
        let firstWhitespace = withoutMarker.firstIndex(where: \.isWhitespace)
        if let colon = withoutMarker.firstIndex(of: ":"),
           firstWhitespace == nil || colon < firstWhitespace! {
            let key = String(withoutMarker[..<colon])
            let value = String(withoutMarker[withoutMarker.index(after: colon)...])
            return (key.normalizedDirectiveKey, value.trimmingCharacters(in: .whitespaces))
        }

        let parts = withoutMarker.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        let key = parts.first.map(String.init) ?? withoutMarker
        let value = parts.dropFirst().first.map(String.init) ?? ""
        return (key.normalizedDirectiveKey, value.trimmingCharacters(in: .whitespaces))
    }

    private static func splitKeywords(_ value: String) -> [String] {
        value
            .split { $0 == "," || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitShellWords(_ value: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaping = false

        for character in value {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }

            if character == "\\" {
                escaping = true
                continue
            }

            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                continue
            }

            if character.isWhitespace {
                if !current.isEmpty {
                    words.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        if escaping {
            current.append("\\")
        }
        if !current.isEmpty {
            words.append(current)
        }
        return words
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedDirectiveKey: String {
        lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
