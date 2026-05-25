import Foundation

public struct LauncherPathCommandTarget: Sendable, Hashable {
    public var path: String
    public var displayPath: String
    public var isDirectory: Bool

    public init(path: String, displayPath: String, isDirectory: Bool) {
        self.path = URL(fileURLWithPath: path, isDirectory: isDirectory)
            .standardizedFileURL
            .path
        self.displayPath = displayPath
        self.isDirectory = isDirectory
    }

    public var name: String {
        let lastPathComponent = URL(fileURLWithPath: path, isDirectory: isDirectory).lastPathComponent
        return lastPathComponent.isEmpty ? path : lastPathComponent
    }

    public var kindName: String {
        isDirectory ? "Folder" : "File"
    }

    public var systemImage: String {
        if isDirectory { return "folder" }
        return LauncherWorkspaceFile(path: path, relativePath: displayPath).systemImage
    }

    public var previewText: String {
        [
            kindName,
            "",
            displayPath,
            "",
            path,
        ].joined(separator: "\n")
    }

    public var askPrompt: String {
        var lines = [
            "Use this local path as context. Explain what it points to and the most useful next actions.",
            "",
            "\(kindName): \(displayPath)",
            "Path: \(path)",
        ]

        if let context = LauncherLocalPathContextBuilder.promptContext(
            for: path,
            displayPath: displayPath,
            isDirectory: isDirectory
        ) {
            lines += ["", context]
        }

        return lines.joined(separator: "\n")
    }
}

public enum LauncherPathCommandFactory {
    public static let commandPrefix = "path:"

    public static func commands(for query: String, workingDirectory: String? = nil) -> [LauncherCommand] {
        guard let command = matchingCommand(for: query, workingDirectory: workingDirectory) else {
            return []
        }
        return [command]
    }

    public static func matchingCommand(for query: String, workingDirectory: String? = nil) -> LauncherCommand? {
        let text = LauncherCommandFilter.scopedQuery(from: query).text
        guard let resolved = resolvedPath(from: text, workingDirectory: workingDirectory) else {
            return nil
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory) else {
            return nil
        }

        let target = LauncherPathCommandTarget(
            path: resolved,
            displayPath: displayPath(for: resolved, workingDirectory: workingDirectory),
            isDirectory: isDirectory.boolValue
        )

        return LauncherCommand(
            id: "\(commandPrefix)\(target.path)",
            title: "Open \(target.name)",
            subtitle: target.displayPath,
            systemImage: target.systemImage,
            category: .workspace,
            keywords: keywordSet(values: [
                text,
                target.name,
                target.displayPath,
                target.path,
                "path",
                target.isDirectory ? "folder" : "file",
                "open",
                "finder",
                "workspace",
            ]),
            action: .openPath(target)
        )
    }

    public static func replayQuery(for command: LauncherCommand) -> String? {
        guard command.id.hasPrefix(commandPrefix),
              case .openPath(let target) = command.action
        else {
            return nil
        }
        return target.path
    }

    private static func resolvedPath(from text: String, workingDirectory: String?) -> String? {
        let candidate = strippedOuterQuotes(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard looksLikeExplicitPath(candidate) else { return nil }

        let pathText: String
        if candidate.lowercased().hasPrefix("file://") {
            guard let url = URL(string: candidate), url.isFileURL else { return nil }
            pathText = url.path
        } else {
            pathText = candidate
        }

        let expanded = pathText.expandingUserHomeDirectory
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            let base = baseDirectoryURL(workingDirectory: workingDirectory)
            url = URL(fileURLWithPath: expanded, relativeTo: base)
        }
        return url.standardizedFileURL.path
    }

    private static func looksLikeExplicitPath(_ text: String) -> Bool {
        text == "."
            || text == ".."
            || text == "~"
            || text.hasPrefix("/")
            || text.hasPrefix("~/")
            || text.hasPrefix("./")
            || text.hasPrefix("../")
            || text.lowercased().hasPrefix("file://")
    }

    private static func baseDirectoryURL(workingDirectory: String?) -> URL {
        let rawBase = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = rawBase?.isEmpty == false ? rawBase! : FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: base.expandingUserHomeDirectory, isDirectory: true).standardizedFileURL
    }

    private static func displayPath(for path: String, workingDirectory: String?) -> String {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let base = baseDirectoryURL(workingDirectory: workingDirectory).path
        if standardizedPath == base {
            return "."
        }
        let basePrefix = base.hasSuffix("/") ? base : base + "/"
        if standardizedPath.hasPrefix(basePrefix) {
            return "./" + String(standardizedPath.dropFirst(basePrefix.count))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if standardizedPath == home {
            return "~"
        }
        let homePrefix = home.hasSuffix("/") ? home : home + "/"
        if standardizedPath.hasPrefix(homePrefix) {
            return "~/" + String(standardizedPath.dropFirst(homePrefix.count))
        }

        return standardizedPath
    }

    private static func strippedOuterQuotes(_ text: String) -> String {
        guard text.count >= 2 else { return text }
        let first = text.first
        let last = text.last
        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return text
        }
        return String(text.dropFirst().dropLast())
    }

    private static func keywordSet(values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

public enum LauncherPathAskPromptBuilder {
    public static func prompt(pathArgument: String, request: String = "", workingDirectory: String? = nil) -> String? {
        prompt(pathArguments: [pathArgument], request: request, workingDirectory: workingDirectory)
    }

    public static func prompt(
        pathArguments: [String],
        request: String = "",
        workingDirectory: String? = nil
    ) -> String? {
        let targets = pathArguments.compactMap { pathArgument -> LauncherPathCommandTarget? in
            guard let command = LauncherPathCommandFactory.commands(
                for: pathArgument,
                workingDirectory: workingDirectory
            ).first,
                  case .openPath(let target) = command.action
            else {
                return nil
            }
            return target
        }
        guard targets.count == pathArguments.count, !targets.isEmpty else {
            return nil
        }

        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard targets.count > 1 else {
            let target = targets[0]
            guard !trimmedRequest.isEmpty else {
                return target.askPrompt
            }

            return [
                "Use the local path context below to answer the user's request.",
                "",
                "User request:",
                trimmedRequest,
                "",
                target.askPrompt,
            ].joined(separator: "\n")
        }

        guard !trimmedRequest.isEmpty else {
            return ([
                "Use these local path contexts. Explain what they point to and the most useful next actions.",
            ] + targets.map(\.askPrompt)).joined(separator: "\n\n---\n\n")
        }

        let promptHeader = [
            "Use the local path contexts below to answer the user's request.",
            "",
            "User request:",
            trimmedRequest,
        ].joined(separator: "\n")
        return ([promptHeader] + targets.map(\.askPrompt)).joined(separator: "\n\n---\n\n")
    }
}

private extension String {
    var expandingUserHomeDirectory: String {
        guard self == "~" || hasPrefix("~/") else { return self }
        return (self as NSString).expandingTildeInPath
    }
}
