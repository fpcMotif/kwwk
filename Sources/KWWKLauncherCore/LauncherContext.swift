import Foundation

public enum LauncherContextPromptKind: String, CaseIterable, Sendable, Hashable {
    case workspace
    case finderSelection
    case desktop

    public var displayName: String {
        switch self {
        case .workspace:
            return "Workspace"
        case .finderSelection:
            return "Finder Selection"
        case .desktop:
            return "Current Context"
        }
    }
}

public struct LauncherContextSnapshot: Sendable, Hashable {
    public var workingDirectory: String?
    public var finderSelectionPaths: [String]
    public var frontmostApplicationName: String?

    public init(
        workingDirectory: String? = nil,
        finderSelectionPaths: [String] = [],
        frontmostApplicationName: String? = nil
    ) {
        self.workingDirectory = Self.normalizedPath(workingDirectory)
        self.finderSelectionPaths = Self.unique(finderSelectionPaths.compactMap(Self.normalizedPath))
        self.frontmostApplicationName = frontmostApplicationName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public func supports(_ kind: LauncherContextPromptKind) -> Bool {
        switch kind {
        case .workspace:
            return workingDirectory != nil
        case .finderSelection:
            return !finderSelectionPaths.isEmpty
        case .desktop:
            return hasAnyContext
        }
    }

    public var hasAnyContext: Bool {
        workingDirectory != nil || !finderSelectionPaths.isEmpty || frontmostApplicationName != nil
    }

    public var finderSelectionSummary: String {
        switch finderSelectionPaths.count {
        case 0:
            return "No Finder selection"
        case 1:
            return "1 item selected in Finder"
        default:
            return "\(finderSelectionPaths.count) items selected in Finder"
        }
    }

    private static func normalizedPath(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
            .standardizedFileURL
            .path
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

public enum LauncherContextPromptBuilder {
    public static func prompt(
        for kind: LauncherContextPromptKind,
        query: String,
        context: LauncherContextSnapshot
    ) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [instruction(for: kind)]

        if !trimmedQuery.isEmpty {
            lines.append(contentsOf: ["", "User request:", trimmedQuery])
        }

        let contextLines = contextSection(for: kind, context: context)
        if !contextLines.isEmpty {
            lines.append(contentsOf: ["", "Context:"])
            lines.append(contentsOf: contextLines)
        }

        return lines.joined(separator: "\n")
    }

    public static func preview(
        for kind: LauncherContextPromptKind,
        context: LauncherContextSnapshot
    ) -> String {
        prompt(for: kind, query: "", context: context)
    }

    private static func instruction(for kind: LauncherContextPromptKind) -> String {
        switch kind {
        case .workspace:
            return "Use the active workspace context to answer as a concise coding assistant. Prefer concrete commands, files, and next actions."
        case .finderSelection:
            return "Use the selected Finder items as context. Explain what they are, what actions are useful, and any safe CLI commands that apply."
        case .desktop:
            return "Use the available macOS context to help the user choose the next useful action. Be concrete and CLI-friendly."
        }
    }

    private static func contextSection(
        for kind: LauncherContextPromptKind,
        context: LauncherContextSnapshot
    ) -> [String] {
        switch kind {
        case .workspace:
            return workspaceLines(context)
        case .finderSelection:
            return finderLines(context)
        case .desktop:
            return desktopLines(context)
        }
    }

    private static func workspaceLines(_ context: LauncherContextSnapshot) -> [String] {
        guard let workingDirectory = context.workingDirectory else { return [] }
        return ["- Working directory: \(workingDirectory)"]
    }

    private static func finderLines(_ context: LauncherContextSnapshot) -> [String] {
        guard !context.finderSelectionPaths.isEmpty else { return [] }
        return ["- Finder selection: \(context.finderSelectionSummary)"]
            + context.finderSelectionPaths.map { "  - \($0)" }
    }

    private static func desktopLines(_ context: LauncherContextSnapshot) -> [String] {
        var lines: [String] = []
        if let frontmostApplicationName = context.frontmostApplicationName {
            lines.append("- Frontmost app: \(frontmostApplicationName)")
        }
        lines += workspaceLines(context)
        lines += finderLines(context)
        return lines
    }
}

public enum LauncherContextCommandFactory {
    public static func commands(for context: LauncherContextSnapshot) -> [LauncherCommand] {
        var commands: [LauncherCommand] = []

        if let workingDirectory = context.workingDirectory {
            commands.append(LauncherCommand(
                id: "context:workspace",
                title: "Ask About Workspace",
                subtitle: workingDirectory,
                systemImage: "folder.badge.questionmark",
                category: .ai,
                keywords: ["ask", "ai", "workspace", "project", "context", "cwd", workingDirectory],
                action: .askContext(.workspace)
            ))
        }

        if !context.finderSelectionPaths.isEmpty {
            commands.append(LauncherCommand(
                id: "context:finder-selection",
                title: "Ask About Finder Selection",
                subtitle: context.finderSelectionSummary,
                systemImage: "doc.badge.ellipsis",
                category: .ai,
                keywords: ["ask", "ai", "finder", "selection", "selected files", "context"] + context.finderSelectionPaths,
                action: .askContext(.finderSelection)
            ))
        }

        if context.hasAnyContext {
            commands.append(LauncherCommand(
                id: "context:desktop",
                title: "Ask About Current Context",
                subtitle: desktopSubtitle(for: context),
                systemImage: "sparkles.rectangle.stack",
                category: .ai,
                keywords: ["ask", "ai", "desktop", "current context", "macos", "raycast"],
                action: .askContext(.desktop)
            ))
        }

        return commands
    }

    private static func desktopSubtitle(for context: LauncherContextSnapshot) -> String {
        if let frontmostApplicationName = context.frontmostApplicationName {
            return "Frontmost app: \(frontmostApplicationName)"
        }
        if context.workingDirectory != nil {
            return "Workspace context"
        }
        return context.finderSelectionSummary
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
