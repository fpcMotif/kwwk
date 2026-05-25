import Foundation

public enum LauncherWebCommandFactory {
    public static let searchCommandPrefix = "web-search:"
    public static let urlCommandPrefix = "open-url:"

    public static func commands(for query: String) -> [LauncherCommand] {
        let text = LauncherCommandFilter.scopedQuery(from: query)
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        if let urlString = normalizedURLString(from: text) {
            return [openURLCommand(urlString: urlString)]
        }

        guard let searchText = searchText(from: text) else { return [] }
        return [searchCommand(searchText: searchText)]
    }

    public static func matchingCommand(for query: String) -> LauncherCommand? {
        commands(for: query).first
    }

    public static func replayQuery(for command: LauncherCommand) -> String? {
        if command.id.hasPrefix(searchCommandPrefix) {
            let query = String(command.id.dropFirst(searchCommandPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty ? nil : "web \(query)"
        }
        if command.id.hasPrefix(urlCommandPrefix) {
            let urlString = String(command.id.dropFirst(urlCommandPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return urlString.isEmpty ? nil : urlString
        }
        return nil
    }

    private static func searchCommand(searchText: String) -> LauncherCommand {
        let quicklink = LauncherQuicklink(
            id: "\(searchCommandPrefix)\(searchText)",
            title: "Search Web",
            subtitle: searchText,
            systemImage: "magnifyingglass",
            keywords: ["web", "search", "browser", "google", "duckduckgo", "ddg", searchText],
            urlTemplate: "https://duckduckgo.com/?q={query}"
        )

        return LauncherCommand(
            id: quicklink.id,
            title: "Search Web",
            subtitle: searchText.truncatedForWebCommand(maxLength: 96),
            systemImage: "magnifyingglass",
            category: .quicklink,
            keywords: quicklink.keywords,
            action: .openQuicklink(quicklink)
        )
    }

    private static func openURLCommand(urlString: String) -> LauncherCommand {
        let host = URL(string: urlString)?.host(percentEncoded: false) ?? urlString
        let quicklink = LauncherQuicklink(
            id: "\(urlCommandPrefix)\(urlString)",
            title: "Open URL",
            subtitle: urlString,
            systemImage: "safari",
            keywords: ["open", "url", "link", "browser", host, urlString],
            urlTemplate: urlString
        )

        return LauncherCommand(
            id: quicklink.id,
            title: host,
            subtitle: urlString.truncatedForWebCommand(maxLength: 96),
            systemImage: "safari",
            category: .quicklink,
            keywords: quicklink.keywords,
            action: .openQuicklink(quicklink)
        )
    }

    private static func searchText(from text: String) -> String? {
        let prefixes = [
            "search web",
            "web search",
            "duckduckgo",
            "google",
            "search",
            "ddg",
            "web",
        ]

        for prefix in prefixes {
            if let argument = argument(after: prefix, in: text), !argument.isEmpty {
                return argument
            }
        }
        return nil
    }

    private static func argument(after prefix: String, in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > prefix.count else { return nil }
        let end = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        guard trimmed[..<end].caseInsensitiveCompare(prefix) == .orderedSame,
              trimmed[end].isWhitespace
        else {
            return nil
        }
        return String(trimmed[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedURLString(from text: String) -> String? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let lowercased = text.lowercased()
        let candidate: String
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            candidate = text
        } else if lowercased.hasPrefix("www.") {
            candidate = "https://\(text)"
        } else {
            return nil
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false,
              URL(string: candidate) != nil
        else {
            return nil
        }
        return candidate
    }
}

private extension String {
    func truncatedForWebCommand(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let end = index(startIndex, offsetBy: maxLength)
        return String(self[..<end]) + "..."
    }
}
