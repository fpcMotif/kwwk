import Foundation

public enum LauncherWindowCommandKind: String, CaseIterable, Sendable, Hashable {
    case leftHalf = "left-half"
    case rightHalf = "right-half"
    case maximize = "maximize"
    case center = "center"
}

public struct LauncherWindowCommand: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var kind: LauncherWindowCommandKind

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        keywords: [String],
        kind: LauncherWindowCommandKind
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.kind = kind
    }
}

public enum LauncherWindowCommandCatalog {
    public static let commandPrefix = "window:"

    public static func commands() -> [LauncherCommand] {
        windowCommands.map { command in
            LauncherCommand(
                id: "\(commandPrefix)\(command.id)",
                title: command.title,
                subtitle: command.subtitle,
                systemImage: command.systemImage,
                category: .window,
                keywords: command.keywords + ["window", "windows", "move", "resize", "layout"],
                action: .runWindowCommand(command)
            )
        }
    }

    public static let windowCommands: [LauncherWindowCommand] = [
        LauncherWindowCommand(
            id: LauncherWindowCommandKind.leftHalf.rawValue,
            title: "Move Window Left Half",
            subtitle: "Resize the previous app window to the left half",
            systemImage: "rectangle.leadinghalf.filled",
            keywords: ["left", "half", "tile", "snap"],
            kind: .leftHalf
        ),
        LauncherWindowCommand(
            id: LauncherWindowCommandKind.rightHalf.rawValue,
            title: "Move Window Right Half",
            subtitle: "Resize the previous app window to the right half",
            systemImage: "rectangle.trailinghalf.filled",
            keywords: ["right", "half", "tile", "snap"],
            kind: .rightHalf
        ),
        LauncherWindowCommand(
            id: LauncherWindowCommandKind.maximize.rawValue,
            title: "Maximize Window",
            subtitle: "Fit the previous app window to the visible screen",
            systemImage: "arrow.up.left.and.arrow.down.right",
            keywords: ["maximize", "full", "fill", "screen"],
            kind: .maximize
        ),
        LauncherWindowCommand(
            id: LauncherWindowCommandKind.center.rawValue,
            title: "Center Window",
            subtitle: "Center the previous app window on screen",
            systemImage: "rectangle.center.inset.filled",
            keywords: ["center", "middle", "focus"],
            kind: .center
        ),
    ]
}
