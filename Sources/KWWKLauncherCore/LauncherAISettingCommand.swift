import Foundation

public enum LauncherAISettingCommandCatalog {
    public static let thinkingCommandPrefix = "thinking:"
    public static let context1MEnableCommandId = "context-1m:enable"
    public static let context1MDisableCommandId = "context-1m:disable"

    public static func commands() -> [LauncherCommand] {
        thinkingCommands() + contextCommands()
    }

    public static func thinkingCommands(levels: [KWWKThinkingLevel] = KWWKThinkingLevel.allCases) -> [LauncherCommand] {
        levels.map { level in
            LauncherCommand(
                id: "\(thinkingCommandPrefix)\(level.rawValue)",
                title: "Set Thinking \(level.displayName)",
                subtitle: "--thinking \(level.rawValue)",
                systemImage: "slider.horizontal.3",
                category: .model,
                keywords: keywordSet(values: [
                    "ai",
                    "thinking",
                    "reasoning",
                    "effort",
                    "model",
                    "default",
                    level.rawValue,
                    level.displayName,
                    "--thinking \(level.rawValue)",
                ]),
                action: .setThinkingLevel(level)
            )
        }
    }

    public static func contextCommands() -> [LauncherCommand] {
        [
            LauncherCommand(
                id: context1MEnableCommandId,
                title: "Enable 1M Context",
                subtitle: "Add --context-1m to AI runs",
                systemImage: "text.page.badge.magnifyingglass",
                category: .model,
                keywords: ["ai", "context", "1m", "one million", "long context", "anthropic", "--context-1m"],
                action: .enableContext1M
            ),
            LauncherCommand(
                id: context1MDisableCommandId,
                title: "Disable 1M Context",
                subtitle: "Use normal provider context",
                systemImage: "text.page.slash",
                category: .model,
                keywords: ["ai", "context", "1m", "disable", "off", "normal", "default", "provider"],
                action: .disableContext1M
            ),
        ]
    }

    public static func thinkingLevel(for commandId: LauncherCommand.ID) -> KWWKThinkingLevel? {
        guard commandId.hasPrefix(thinkingCommandPrefix) else { return nil }
        return KWWKThinkingLevel(rawValue: String(commandId.dropFirst(thinkingCommandPrefix.count)))
    }

    private static func keywordSet(values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}

public extension KWWKThinkingLevel {
    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .minimal:
            return "Minimal"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .xhigh:
            return "XHigh"
        }
    }
}
