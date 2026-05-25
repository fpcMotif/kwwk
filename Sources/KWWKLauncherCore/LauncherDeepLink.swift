import Foundation

public enum LauncherDeepLinkMode: String, Codable, Sendable, Hashable {
    case search
    case ask
    case hide
    case toggle
}

public struct LauncherDeepLinkRequest: Sendable, Hashable {
    public static let scheme = "kwwk"
    public static let host = "launcher"

    public var mode: LauncherDeepLinkMode
    public var query: String
    public var commandId: String?
    public var actionId: String?
    public var pathContext: String?
    public var pathContexts: [String]
    public var runImmediately: Bool
    public var workingDirectory: String?

    public init(
        mode: LauncherDeepLinkMode = .search,
        query: String = "",
        commandId: String? = nil,
        actionId: String? = nil,
        pathContext: String? = nil,
        pathContexts: [String] = [],
        runImmediately: Bool = false,
        workingDirectory: String? = nil
    ) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPathContexts = Self.normalizedPathContexts(
            [pathContext].compactMap { $0 } + pathContexts
        )
        self.mode = mode
        self.query = trimmedQuery
        self.commandId = Self.normalizedCommandId(commandId)
        self.actionId = Self.normalizedActionId(actionId)
        self.pathContext = normalizedPathContexts.first
        self.pathContexts = normalizedPathContexts
        self.runImmediately = mode.canRunImmediately
            && runImmediately
            && (!trimmedQuery.isEmpty || self.commandId != nil || !self.pathContexts.isEmpty)
        self.workingDirectory = Self.normalizedWorkingDirectory(workingDirectory)
    }

    public init?(url: URL) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme,
              components.host == Self.host
        else {
            return nil
        }

        let pathMode = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map(String.init)
        let mode = pathMode.flatMap(LauncherDeepLinkMode.init(rawValue:)) ?? .search
        let items = components.queryItems ?? []
        let query = items.value(named: "query")
            ?? items.value(named: "prompt")
            ?? ""
        let commandId = items.value(named: "command")
        let actionId = items.value(named: "action")
        let pathContexts = items.values(named: "path")
        let workingDirectory = items.value(named: "cwd")
        let explicitRun = items.value(named: "run").map(Self.parseBool)
        let runImmediately = explicitRun ?? (mode == .ask)

        components.percentEncodedQuery = nil
        self.init(
            mode: mode,
            query: query,
            commandId: commandId,
            actionId: actionId,
            pathContexts: pathContexts,
            runImmediately: runImmediately,
            workingDirectory: workingDirectory
        )
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = mode == .search ? "" : "/\(mode.rawValue)"

        var items: [URLQueryItem] = []
        if !query.isEmpty {
            items.append(URLQueryItem(name: mode == .ask ? "prompt" : "query", value: query))
        }
        if let commandId {
            items.append(URLQueryItem(name: "command", value: commandId))
        }
        if let actionId {
            items.append(URLQueryItem(name: "action", value: actionId))
        }
        for pathContext in pathContexts {
            items.append(URLQueryItem(name: "path", value: pathContext))
        }
        if runImmediately {
            items.append(URLQueryItem(name: "run", value: "1"))
        }
        if let workingDirectory {
            items.append(URLQueryItem(name: "cwd", value: workingDirectory))
        }
        components.queryItems = items.isEmpty ? nil : items

        return components.url!
    }

    private static func parseBool(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "run":
            return true
        default:
            return false
        }
    }

    private static func normalizedWorkingDirectory(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedCommandId(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedActionId(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedPathContexts(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

private extension LauncherDeepLinkMode {
    var canRunImmediately: Bool {
        switch self {
        case .search, .ask:
            return true
        case .hide, .toggle:
            return false
        }
    }
}

private extension Array where Element == URLQueryItem {
    func value(named name: String) -> String? {
        first { $0.name == name }?.value
    }

    func values(named name: String) -> [String] {
        compactMap { $0.name == name ? $0.value : nil }
    }
}
