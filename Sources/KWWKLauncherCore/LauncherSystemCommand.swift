import Foundation

public enum LauncherSystemCommandKind: String, CaseIterable, Sendable, Hashable {
    case lockScreen = "lock-screen"
    case sleepDisplay = "sleep-display"
    case startScreenSaver = "start-screen-saver"
    case openSystemSettings = "open-system-settings"
    case quitAllApplications = "quit-all-applications"
}

public struct LauncherSystemCommand: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var kind: LauncherSystemCommandKind

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        keywords: [String],
        kind: LauncherSystemCommandKind
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.kind = kind
    }
}

public enum LauncherSystemCommandCatalog {
    public static let commandPrefix = "system:"

    public static func commands() -> [LauncherCommand] {
        systemCommands.map { command in
            LauncherCommand(
                id: "\(commandPrefix)\(command.id)",
                title: command.title,
                subtitle: command.subtitle,
                systemImage: command.systemImage,
                category: .system,
                keywords: command.keywords + ["system", "macos", "mac"],
                action: .runSystemCommand(command)
            )
        }
    }

    public static let systemCommands: [LauncherSystemCommand] = [
        LauncherSystemCommand(
            id: LauncherSystemCommandKind.lockScreen.rawValue,
            title: "Lock Screen",
            subtitle: "Lock this Mac",
            systemImage: "lock",
            keywords: ["lock", "screen", "security", "loginwindow"],
            kind: .lockScreen
        ),
        LauncherSystemCommand(
            id: LauncherSystemCommandKind.sleepDisplay.rawValue,
            title: "Sleep Display",
            subtitle: "Turn off the display",
            systemImage: "display",
            keywords: ["sleep", "display", "screen", "monitor", "off"],
            kind: .sleepDisplay
        ),
        LauncherSystemCommand(
            id: LauncherSystemCommandKind.startScreenSaver.rawValue,
            title: "Start Screen Saver",
            subtitle: "Launch the macOS screen saver",
            systemImage: "sparkles.tv",
            keywords: ["screen", "saver", "screensaver", "idle"],
            kind: .startScreenSaver
        ),
        LauncherSystemCommand(
            id: LauncherSystemCommandKind.openSystemSettings.rawValue,
            title: "Open System Settings",
            subtitle: "Open macOS System Settings",
            systemImage: "gearshape",
            keywords: ["settings", "preferences", "system settings", "system preferences"],
            kind: .openSystemSettings
        ),
        LauncherSystemCommand(
            id: LauncherSystemCommandKind.quitAllApplications.rawValue,
            title: "Quit All Applications",
            subtitle: "Ask running apps to quit",
            systemImage: "xmark.app",
            keywords: ["quit", "close", "applications", "apps", "clean up"],
            kind: .quitAllApplications
        ),
    ]
}
