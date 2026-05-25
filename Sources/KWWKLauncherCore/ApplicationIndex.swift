import Foundation

public struct IndexedApplication: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public var displayName: String
    public var bundleIdentifier: String?
    public var path: String
    public var keywords: [String]

    public init(displayName: String, bundleIdentifier: String?, path: String, keywords: [String] = []) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.path = path
        self.keywords = keywords
    }
}

public enum ApplicationIndex {
    public static func defaultRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
        ]
    }

    public static func scan(roots: [URL], maxDepth: Int = 2, limit: Int = 500) -> [IndexedApplication] {
        var results: [IndexedApplication] = []
        var seenPaths = Set<String>()

        for root in roots {
            scanDirectory(root, depth: 0, maxDepth: maxDepth, limit: limit, seenPaths: &seenPaths, results: &results)
            if results.count >= limit { break }
        }

        return results
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    public static func commands(for applications: [IndexedApplication]) -> [LauncherCommand] {
        applications.map { app in
            LauncherCommand(
                id: "app:\(app.path)",
                title: app.displayName,
                subtitle: app.bundleIdentifier ?? app.path,
                systemImage: "app",
                category: .app,
                keywords: app.keywords,
                action: .openApplication(app.path)
            )
        }
    }

    private static func scanDirectory(
        _ directory: URL,
        depth: Int,
        maxDepth: Int,
        limit: Int,
        seenPaths: inout Set<String>,
        results: inout [IndexedApplication]
    ) {
        guard results.count < limit else { return }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in children {
            guard results.count < limit else { return }
            if child.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
                let standardizedPath = child.standardizedFileURL.path
                guard seenPaths.insert(standardizedPath).inserted else { continue }
                if let app = readApplicationBundle(child) {
                    results.append(app)
                }
                continue
            }

            guard depth < maxDepth else { continue }
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            scanDirectory(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                limit: limit,
                seenPaths: &seenPaths,
                results: &results
            )
        }
    }

    private static func readApplicationBundle(_ url: URL) -> IndexedApplication? {
        let infoURL = url.appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any] ?? [:]
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let displayName = string(info["CFBundleDisplayName"])
            ?? string(info["CFBundleName"])
            ?? fallbackName
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let bundleIdentifier = string(info["CFBundleIdentifier"])
        let keywords = keywordSet(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            path: url.standardizedFileURL.path
        )
        return IndexedApplication(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            path: url.standardizedFileURL.path,
            keywords: keywords
        )
    }

    private static func keywordSet(displayName: String, bundleIdentifier: String?, path: String) -> [String] {
        var values = Set<String>()
        values.insert(displayName)
        values.insert("app")
        values.insert("application")
        values.insert(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent)
        if let bundleIdentifier {
            values.insert(bundleIdentifier)
            bundleIdentifier
                .split(separator: ".")
                .map(String.init)
                .forEach { values.insert($0) }
        }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}
