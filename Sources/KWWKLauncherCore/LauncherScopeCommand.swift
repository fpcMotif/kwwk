import Foundation

public struct LauncherScopeCommand: Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var query: String
    public var keywords: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        query: String,
        keywords: [String]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.query = query
        self.keywords = keywords
    }

    public var shortTitle: String {
        let prefix = "Search "
        guard title.hasPrefix(prefix) else { return title }
        return String(title.dropFirst(prefix.count))
    }

    public var command: LauncherCommand {
        LauncherCommand(
            id: "scope:\(id)",
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            category: .scope,
            keywords: keywords,
            action: .setSearchQuery(query)
        )
    }
}

public enum LauncherScopeCommandCatalog {
    public static let shortcutIds: [String] = [
        "ai",
        "cli",
        "apps",
        "scripts",
        "workspace",
        "workflows",
        "quicklinks",
        "snippets",
        "models",
    ]

    public static let defaults: [LauncherScopeCommand] = [
        LauncherScopeCommand(
            id: "ai",
            title: "Search AI",
            subtitle: "Prefill @ai to filter prompts, presets, and AI history",
            systemImage: "sparkles",
            query: "@ai ",
            keywords: ["scope", "scopes", "category", "ai", "ask", "prompt", "presets", "@ai"]
        ),
        LauncherScopeCommand(
            id: "cli",
            title: "Search CLI",
            subtitle: "Prefill @cli to filter terminal and shell commands",
            systemImage: "terminal",
            query: "@cli ",
            keywords: ["scope", "scopes", "category", "cli", "terminal", "shell", "@cli"]
        ),
        LauncherScopeCommand(
            id: "apps",
            title: "Search Apps",
            subtitle: "Prefill @apps to filter installed applications",
            systemImage: "app.badge",
            query: "@apps ",
            keywords: ["scope", "scopes", "category", "apps", "app", "applications", "@apps"]
        ),
        LauncherScopeCommand(
            id: "scripts",
            title: "Search Scripts",
            subtitle: "Prefill @scripts to filter local script commands",
            systemImage: "folder.badge.gearshape",
            query: "@scripts ",
            keywords: ["scope", "scopes", "category", "scripts", "script", "extensions", "@scripts"]
        ),
        LauncherScopeCommand(
            id: "quicklinks",
            title: "Search Quicklinks",
            subtitle: "Prefill @quicklinks to filter saved links and web commands",
            systemImage: "link",
            query: "@quicklinks ",
            keywords: ["scope", "scopes", "category", "quicklinks", "quicklink", "links", "web", "@quicklinks"]
        ),
        LauncherScopeCommand(
            id: "snippets",
            title: "Search Snippets",
            subtitle: "Prefill @snippets to filter text snippets",
            systemImage: "text.quote",
            query: "@snippets ",
            keywords: ["scope", "scopes", "category", "snippets", "snippet", "text", "@snippets"]
        ),
        LauncherScopeCommand(
            id: "clipboard",
            title: "Search Clipboard",
            subtitle: "Prefill @clipboard to filter clipboard history",
            systemImage: "doc.on.clipboard",
            query: "@clipboard ",
            keywords: ["scope", "scopes", "category", "clipboard", "pasteboard", "clips", "@clipboard"]
        ),
        LauncherScopeCommand(
            id: "calculator",
            title: "Search Calculator",
            subtitle: "Prefill @calculator to filter calculator and conversion results",
            systemImage: "function",
            query: "@calculator ",
            keywords: ["scope", "scopes", "category", "calculator", "calc", "math", "convert", "@calculator"]
        ),
        LauncherScopeCommand(
            id: "aliases",
            title: "Search Aliases",
            subtitle: "Prefill @aliases to filter command aliases",
            systemImage: "arrow.triangle.branch",
            query: "@aliases ",
            keywords: ["scope", "scopes", "category", "aliases", "alias", "shortcuts", "@aliases"]
        ),
        LauncherScopeCommand(
            id: "models",
            title: "Search Models",
            subtitle: "Prefill @models to filter models, profiles, and AI settings",
            systemImage: "cpu",
            query: "@models ",
            keywords: ["scope", "scopes", "category", "models", "model", "profiles", "providers", "llm", "@models"]
        ),
        LauncherScopeCommand(
            id: "system",
            title: "Search System",
            subtitle: "Prefill @system to filter macOS system commands",
            systemImage: "gearshape",
            query: "@system ",
            keywords: ["scope", "scopes", "category", "system", "macos", "settings", "@system"]
        ),
        LauncherScopeCommand(
            id: "window",
            title: "Search Window",
            subtitle: "Prefill @window to filter window management commands",
            systemImage: "rectangle.on.rectangle",
            query: "@window ",
            keywords: ["scope", "scopes", "category", "window", "windows", "layout", "resize", "move", "@window"]
        ),
        LauncherScopeCommand(
            id: "workflows",
            title: "Search Workflows",
            subtitle: "Prefill @workflows to filter multi-step automations",
            systemImage: "point.3.connected.trianglepath.dotted",
            query: "@workflows ",
            keywords: ["scope", "scopes", "category", "workflows", "workflow", "automation", "automations", "@workflows"]
        ),
        LauncherScopeCommand(
            id: "workspace",
            title: "Search Workspace",
            subtitle: "Prefill @workspace to filter workspace files and tasks",
            systemImage: "folder",
            query: "@workspace ",
            keywords: ["scope", "scopes", "category", "workspace", "project", "files", "tasks", "@workspace"]
        ),
        LauncherScopeCommand(
            id: "recent",
            title: "Search Recent",
            subtitle: "Prefill @recent to filter recently used commands",
            systemImage: "clock.arrow.circlepath",
            query: "@recent ",
            keywords: ["scope", "scopes", "category", "recent", "recents", "history", "@recent"]
        ),
        LauncherScopeCommand(
            id: "scopes",
            title: "Search Scopes",
            subtitle: "Prefill @scopes to filter scope switchers",
            systemImage: "line.3.horizontal.decrease.circle",
            query: "@scopes ",
            keywords: ["scope", "scopes", "category", "categories", "filter", "@scopes"]
        ),
    ]

    public static func commands() -> [LauncherCommand] {
        defaults.map(\.command)
    }

    public static func shortcuts() -> [LauncherScopeCommand] {
        let commandsById = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        return shortcutIds.compactMap { commandsById[$0] }
    }

    public static func activeShortcutId(for query: String) -> String? {
        let rawScope = rawScopePrefix(in: query)
        guard !rawScope.isEmpty else { return nil }
        return defaults.first { scope in
            normalizedScopeName(scope.id) == rawScope
                || normalizedScopeName(scope.query) == rawScope
        }?.id
    }

    public static func query(replacingScopeIn query: String, with scope: LauncherScopeCommand?) -> String {
        let rest = queryWithoutLeadingScope(query)
        guard let scope else { return rest }
        return rest.isEmpty ? scope.query : "\(scope.query)\(rest)"
    }

    private static func queryWithoutLeadingScope(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@") else { return trimmed }
        guard let scopeEnd = trimmed.firstIndex(where: \.isWhitespace) else { return "" }
        return String(trimmed[scopeEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rawScopePrefix(in query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@") else { return "" }
        let scopeEnd = trimmed.firstIndex(where: \.isWhitespace) ?? trimmed.endIndex
        let scope = String(trimmed[trimmed.index(after: trimmed.startIndex)..<scopeEnd])
        return normalizedScopeName(scope)
    }

    private static func normalizedScopeName(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespacesAndNewlines))
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}
