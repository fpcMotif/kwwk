import Foundation

public enum LauncherPreferenceKeys {
    public static let cliPathOverride = "KWWKLauncher.CLIPathOverride"
    public static let defaultModel = "KWWKLauncher.DefaultModel"
    public static let defaultThinking = "KWWKLauncher.DefaultThinking"
    public static let context1m = "KWWKLauncher.Context1M"
    public static let aiHistoryLimit = "KWWKLauncher.AIHistoryLimit"
    public static let trackClipboardHistory = "KWWKLauncher.TrackClipboardHistory"
    public static let globalHotkey = "KWWKLauncher.GlobalHotkey"
    public static let launchAtLogin = "KWWKLauncher.LaunchAtLogin"
}

public enum LauncherGlobalHotkey: String, CaseIterable, Codable, Sendable, Hashable {
    case disabled
    case controlOptionShiftSpace
    case controlOptionSpace
    case controlShiftSpace
    case optionSpace

    public static let `default` = Self.controlOptionShiftSpace

    public var displayName: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .controlOptionShiftSpace:
            return "Control Option Shift Space"
        case .controlOptionSpace:
            return "Control Option Space"
        case .controlShiftSpace:
            return "Control Shift Space"
        case .optionSpace:
            return "Option Space"
        }
    }
}

public struct LauncherPreferences: Sendable, Hashable {
    public static let defaultHistoryLimit = 30
    public static let minimumHistoryLimit = 1
    public static let maximumHistoryLimit = 200
    public static let defaultTrackClipboardHistory = false
    public static let defaultLaunchAtLogin = false

    public var cliPathOverride: String
    public var defaultModel: String
    public var defaultThinking: KWWKThinkingLevel
    public var context1m: Bool
    public var aiHistoryLimit: Int
    public var trackClipboardHistory: Bool
    public var globalHotkey: LauncherGlobalHotkey
    public var launchAtLogin: Bool

    public init(
        cliPathOverride: String = "",
        defaultModel: String = "",
        defaultThinking: KWWKThinkingLevel = .medium,
        context1m: Bool = false,
        aiHistoryLimit: Int = Self.defaultHistoryLimit,
        trackClipboardHistory: Bool = Self.defaultTrackClipboardHistory,
        globalHotkey: LauncherGlobalHotkey = .default,
        launchAtLogin: Bool = Self.defaultLaunchAtLogin
    ) {
        self.cliPathOverride = cliPathOverride
        self.defaultModel = defaultModel
        self.defaultThinking = defaultThinking
        self.context1m = context1m
        self.aiHistoryLimit = Self.normalizedHistoryLimit(aiHistoryLimit)
        self.trackClipboardHistory = trackClipboardHistory
        self.globalHotkey = globalHotkey
        self.launchAtLogin = launchAtLogin
    }

    public static func normalizedThinking(_ rawValue: String) -> KWWKThinkingLevel {
        KWWKThinkingLevel(rawValue: rawValue) ?? .medium
    }

    public static func normalizedHistoryLimit(_ value: Int) -> Int {
        min(max(value, minimumHistoryLimit), maximumHistoryLimit)
    }

    public static func normalizedGlobalHotkey(_ rawValue: String?) -> LauncherGlobalHotkey {
        LauncherGlobalHotkey(rawValue: rawValue ?? "") ?? .default
    }

    public static func normalizedPath(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func resolvedExecutable(
        envPath: String?,
        bundledPath: String?,
        bundledIsExecutable: Bool
    ) -> String {
        let preferred = Self.normalizedPath(cliPathOverride)
        if !preferred.isEmpty { return preferred }

        let env = Self.normalizedPath(envPath ?? "")
        if !env.isEmpty { return env }

        if let bundledPath, bundledIsExecutable {
            return bundledPath
        }

        return "kwwk"
    }
}
