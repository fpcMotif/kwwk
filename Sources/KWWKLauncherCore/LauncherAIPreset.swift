import Foundation

public enum LauncherAIPresetInputSource: String, Codable, CaseIterable, Sendable, Hashable {
    case query
    case clipboard
    case queryOrClipboard

    public var displayName: String {
        switch self {
        case .query:
            return "Query"
        case .clipboard:
            return "Clipboard"
        case .queryOrClipboard:
            return "Query or clipboard"
        }
    }
}

public struct LauncherAIPreset: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var inputSource: LauncherAIPresetInputSource
    public var instruction: String

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String = "sparkles",
        keywords: [String],
        inputSource: LauncherAIPresetInputSource,
        instruction: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.inputSource = inputSource
        self.instruction = instruction
    }

    public func prompt(input: String) -> String {
        [
            instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "Input:",
            input.trimmingCharacters(in: .whitespacesAndNewlines),
        ].joined(separator: "\n")
    }

    public func input(query: String, clipboard: String) -> String {
        let queryInput = strippedTriggerPrefix(from: query)
        let clipboardInput = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)

        switch inputSource {
        case .query:
            return queryInput
        case .clipboard:
            return clipboardInput
        case .queryOrClipboard:
            return queryInput.isEmpty ? clipboardInput : queryInput
        }
    }

    public var previewText: String {
        [
            subtitle,
            "",
            "Input: \(inputSource.displayName)",
            "",
            instruction,
        ].joined(separator: "\n")
    }

    private func strippedTriggerPrefix(from query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalized = Self.normalized(trimmed)
        let triggers = ([title] + keywords)
            .map(Self.normalized)
            .sorted { $0.count > $1.count }

        for trigger in triggers where !trigger.isEmpty {
            if normalized == trigger { return "" }
            guard normalized.hasPrefix(trigger + " ") else { continue }
            let offset = trimmed.index(trimmed.startIndex, offsetBy: min(trigger.count, trimmed.count))
            return String(trimmed[offset...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}

public enum LauncherAIPresetCatalog {
    public static let defaults: [LauncherAIPreset] = [
        LauncherAIPreset(
            id: "summarize-clipboard",
            title: "Summarize Clipboard",
            subtitle: "Condense copied text into decisions and next actions",
            systemImage: "text.alignleft",
            keywords: ["summarize", "summary", "clipboard", "notes", "decisions"],
            inputSource: .clipboard,
            instruction: "Summarize this content for a developer. Capture the core points, decisions, risks, and concrete next actions."
        ),
        LauncherAIPreset(
            id: "explain-clipboard",
            title: "Explain Clipboard",
            subtitle: "Explain copied code, logs, or technical text",
            systemImage: "questionmark.bubble",
            keywords: ["explain", "clipboard", "code", "logs", "technical"],
            inputSource: .clipboard,
            instruction: "Explain this code or technical text. Identify its purpose, important flows, dependencies, and gotchas."
        ),
        LauncherAIPreset(
            id: "debug-error",
            title: "Debug Error",
            subtitle: "Diagnose a pasted failure or the current query",
            systemImage: "stethoscope",
            keywords: ["debug", "diagnose", "error", "failure", "stacktrace", "logs"],
            inputSource: .queryOrClipboard,
            instruction: "Diagnose this failure. Identify the likely root cause, the smallest useful evidence to gather, and a concrete fix plan."
        ),
        LauncherAIPreset(
            id: "commit-message",
            title: "Draft Commit Message",
            subtitle: "Write a conventional commit message from copied diff",
            systemImage: "arrow.trianglehead.branch",
            keywords: ["commit", "message", "conventional", "diff", "git"],
            inputSource: .clipboard,
            instruction: "Write a concise conventional commit message for this diff. Return a subject and short body only."
        ),
        LauncherAIPreset(
            id: "shell-command",
            title: "Generate Shell Command",
            subtitle: "Turn a request into a safe zsh command",
            systemImage: "terminal",
            keywords: ["shell command", "shell", "command", "zsh", "generate"],
            inputSource: .query,
            instruction: "Convert this request into a zsh command for macOS. Prefer safe, inspectable commands and call out any destructive step instead of executing it."
        ),
    ]

    public static func commands(for presets: [LauncherAIPreset] = defaults) -> [LauncherCommand] {
        presets.map { preset in
            LauncherCommand(
                id: "ai-preset:\(preset.id)",
                title: preset.title,
                subtitle: preset.subtitle,
                systemImage: preset.systemImage,
                category: .ai,
                keywords: preset.keywords + [preset.inputSource.displayName, "ai preset", "kwwk"],
                action: .runAIPreset(preset)
            )
        }
    }
}
