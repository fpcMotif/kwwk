import Foundation

public struct LauncherAIProfile: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var model: String
    public var thinking: KWWKThinkingLevel
    public var context1m: Bool

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        systemImage: String = "slider.horizontal.3",
        keywords: [String] = [],
        model: String = "",
        thinking: KWWKThinkingLevel = .medium,
        context1m: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.keywords = keywords
        self.model = model
        self.thinking = thinking
        self.context1m = context1m
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? "slider.horizontal.3"
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        thinking = KWWKThinkingLevel(rawValue: try container.decodeIfPresent(String.self, forKey: .thinking) ?? "")
            ?? .medium
        context1m = try container.decodeIfPresent(Bool.self, forKey: .context1m) ?? false
    }

    public var modelDisplayName: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "provider default" : trimmed
    }

    public var cliFlags: String {
        var flags = ["--thinking \(thinking.rawValue)"]
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            flags.append("--model \(KWWKShellCommand.quote(trimmedModel))")
        }
        if context1m {
            flags.append("--context-1m")
        }
        return flags.joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case systemImage
        case keywords
        case model
        case thinking
        case context1m
    }
}

public enum LauncherAIProfileCatalog {
    public static let commandPrefix = "ai-profile:"

    public static let defaults: [LauncherAIProfile] = [
        LauncherAIProfile(
            id: "fast",
            title: "Use Fast AI Profile",
            subtitle: "Provider default model, low thinking",
            systemImage: "bolt",
            keywords: ["fast", "quick", "low", "cheap", "default"],
            thinking: .low
        ),
        LauncherAIProfile(
            id: "codex-deep",
            title: "Use Codex Deep Profile",
            subtitle: "GPT-5.4 with xhigh thinking",
            systemImage: "brain.head.profile",
            keywords: ["codex", "openai", "deep", "reasoning", "xhigh", "coding"],
            model: "gpt-5.4",
            thinking: .xhigh
        ),
        LauncherAIProfile(
            id: "claude-long",
            title: "Use Claude Long Context Profile",
            subtitle: "Claude Sonnet 4.5 with 1M context",
            systemImage: "text.page.badge.magnifyingglass",
            keywords: ["claude", "anthropic", "long", "context", "1m", "sonnet"],
            model: "claude-sonnet-4-5-20250929",
            thinking: .high,
            context1m: true
        ),
    ]

    public static func defaultCommands() -> [LauncherCommand] {
        commands(for: defaults) + managementCommands()
    }

    public static func commands(
        for profiles: [LauncherAIProfile],
        reservedCommandIds: Set<LauncherCommand.ID> = []
    ) -> [LauncherCommand] {
        profiles
            .filter { !reservedCommandIds.contains("\(commandPrefix)\($0.id)") }
            .map(command(for:))
    }

    public static func command(for profile: LauncherAIProfile) -> LauncherCommand {
        LauncherCommand(
            id: "\(commandPrefix)\(profile.id)",
            title: profile.title,
            subtitle: profile.subtitle.isEmpty ? profile.summary : profile.subtitle,
            systemImage: profile.systemImage,
            category: .model,
            keywords: keywordSet(values: [
                profile.id,
                profile.title,
                profile.subtitle,
                "ai",
                "profile",
                "profiles",
                "model",
                "thinking",
                "context",
                profile.model,
                profile.thinking.rawValue,
                profile.cliFlags,
            ] + profile.keywords),
            action: .applyAIProfile(profile)
        )
    }

    public static func managementCommands() -> [LauncherCommand] {
        [
            LauncherCommand(
                id: "save-current-ai-profile",
                title: "Save Current AI Profile",
                subtitle: "~/.kwwk/launcher/profiles.json",
                systemImage: "square.and.arrow.down",
                category: .model,
                keywords: [
                    "save",
                    "current",
                    "ai",
                    "profile",
                    "profiles",
                    "model",
                    "thinking",
                    "context",
                    "preset",
                    "defaults",
                ],
                action: .saveCurrentAIProfile
            ),
            LauncherCommand(
                id: "reveal-ai-profiles",
                title: "Reveal AI Profiles File",
                subtitle: "~/.kwwk/launcher/profiles.json",
                systemImage: "slider.horizontal.3",
                category: .model,
                keywords: ["ai", "profile", "profiles", "config", "file", "model", "thinking"],
                action: .revealAIProfilesFile
            ),
            LauncherCommand(
                id: "reload-ai-profiles",
                title: "Reload AI Profiles",
                subtitle: "Rescan ~/.kwwk/launcher/profiles.json",
                systemImage: "arrow.clockwise",
                category: .model,
                keywords: ["reload", "refresh", "ai", "profile", "profiles", "model", "thinking"],
                action: .reloadAIProfiles
            ),
        ]
    }

    public static var defaultCommandIds: Set<LauncherCommand.ID> {
        Set(defaults.map { "\(commandPrefix)\($0.id)" })
    }

    public static func availableProfiles(customProfiles: [LauncherAIProfile]) -> [LauncherAIProfile] {
        var seen = Set<String>()
        return (defaults + customProfiles)
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { seen.insert($0.id).inserted }
    }

    public static func profile(
        matching id: String,
        customProfiles: [LauncherAIProfile]
    ) -> LauncherAIProfile? {
        let normalized = id.hasPrefix(commandPrefix)
            ? String(id.dropFirst(commandPrefix.count))
            : id
        return availableProfiles(customProfiles: customProfiles)
            .first { $0.id == normalized }
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
            .filter { seen.insert($0.lowercased()).inserted }
    }
}

public enum LauncherAIProfileIndex {
    public static func defaultURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".kwwk", isDirectory: true)
            .appendingPathComponent("launcher", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    public static func load(from url: URL = defaultURL(), limit: Int = 100) -> [LauncherAIProfile] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        let decoded = (try? decoder.decode([LauncherAIProfile].self, from: data))
            ?? (try? decoder.decode(LauncherAIProfileDocument.self, from: data))?.profiles
            ?? []

        var seen = Set<String>()
        return decoded
            .filter { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { seen.insert($0.id).inserted }
            .prefix(max(0, limit))
            .map { $0 }
    }

    public static func profile(
        fromModel model: String,
        thinking: KWWKThinkingLevel,
        context1m: Bool
    ) -> LauncherAIProfile {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = trimmedModel.isEmpty ? "Provider Default" : trimmedModel
        let idModel = trimmedModel.isEmpty ? "provider-default" : trimmedModel
        let contextWords = context1m ? ["1m", "context"] : []
        let slug = slug(for: ([idModel, thinking.rawValue] + contextWords).joined(separator: " "))

        return LauncherAIProfile(
            id: "saved-\(slug)",
            title: "Saved \(modelName) \(thinking.displayName) Profile",
            subtitle: context1m ? "Saved current launcher defaults with 1M context" : "Saved current launcher defaults",
            systemImage: context1m ? "text.page.badge.magnifyingglass" : "slider.horizontal.3",
            keywords: keywordSet(values: [
                "saved",
                "current",
                "ai",
                "profile",
                "model",
                idModel,
                thinking.rawValue,
                thinking.displayName,
            ] + contextWords),
            model: trimmedModel,
            thinking: thinking,
            context1m: context1m
        )
    }

    @discardableResult
    public static func upsert(
        _ profile: LauncherAIProfile,
        to url: URL = defaultURL()
    ) throws -> [LauncherAIProfile] {
        var profiles = load(from: url, limit: Int.max)
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        try save(profiles, to: url)
        return load(from: url, limit: Int.max)
    }

    public static func save(_ profiles: [LauncherAIProfile], to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = profiles.sorted {
            if $0.title != $1.title {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        try encoder.encode(sorted).write(to: url, options: .atomic)
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
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private static func slug(for value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .prefix(8)
            .joined(separator: "-")
        return collapsed.isEmpty ? "profile" : collapsed
    }
}

private struct LauncherAIProfileDocument: Codable {
    var profiles: [LauncherAIProfile]
}

public struct LauncherAIProfileExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: [String]
    public var model: String
    public var thinking: KWWKThinkingLevel
    public var context1m: Bool
    public var cliFlags: String
    public var headlessCommand: String

    public init(profile: LauncherAIProfile) {
        id = profile.id
        title = profile.title
        subtitle = profile.subtitle
        systemImage = profile.systemImage
        keywords = profile.keywords
        model = profile.model
        thinking = profile.thinking
        context1m = profile.context1m
        cliFlags = profile.cliFlags
        headlessCommand = "kwwk --profile \(KWWKShellCommand.quote(profile.id)) -p '<prompt>'"
    }
}

public enum LauncherAIProfileExport {
    public static func records(for profiles: [LauncherAIProfile]) -> [LauncherAIProfileExportRecord] {
        profiles
            .map(LauncherAIProfileExportRecord.init(profile:))
            .sorted { lhs, rhs in
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    public static func table(for profiles: [LauncherAIProfile]) -> String {
        let rows = records(for: profiles)
        guard !rows.isEmpty else { return "" }
        return rows
            .map { "\($0.id)\t\($0.title)\t\($0.model)\t\($0.thinking.rawValue)\t\($0.context1m ? "1" : "0")\t\($0.cliFlags)" }
            .joined(separator: "\n")
    }

    public static func json(for profiles: [LauncherAIProfile]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: profiles))
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

private extension LauncherAIProfile {
    var summary: String {
        [
            "model \(modelDisplayName)",
            "thinking \(thinking.rawValue)",
            context1m ? "1M context" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}
