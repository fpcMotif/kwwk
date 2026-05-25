import Foundation

public struct LauncherWorkspaceFile: Codable, Identifiable, Sendable, Hashable {
    public var id: String { path }
    public var path: String
    public var relativePath: String
    public var name: String
    public var fileExtension: String

    public init(path: String, relativePath: String) {
        let fileURL = URL(fileURLWithPath: path)
        self.path = fileURL.standardizedFileURL.path
        self.relativePath = relativePath
        self.name = fileURL.lastPathComponent
        self.fileExtension = fileURL.pathExtension.lowercased()
    }

    public var systemImage: String {
        switch fileExtension {
        case "swift", "ts", "tsx", "js", "jsx", "go", "rs", "py", "rb", "sh", "zsh", "c", "cpp", "h":
            return "curlybraces"
        case "md", "txt", "rst":
            return "doc.text"
        case "json", "toml", "yaml", "yml", "plist":
            return "doc.badge.gearshape"
        case "png", "jpg", "jpeg", "gif", "webp", "heic":
            return "photo"
        default:
            return "doc"
        }
    }

    public var previewText: String {
        [
            relativePath,
            "",
            path,
        ].joined(separator: "\n")
    }

    public var askPrompt: String {
        var lines = [
            "Use this workspace file as coding context. Explain what it is for, where it fits, and the most useful next actions.",
            "",
            "Workspace file: \(relativePath)",
            "File path: \(path)",
        ]

        if let context = LauncherLocalPathContextBuilder.promptContext(
            for: path,
            displayPath: relativePath,
            isDirectory: false
        ) {
            lines += ["", context]
        }

        return lines.joined(separator: "\n")
    }
}

public enum LauncherWorkspaceFileIndex {
    private static let excludedDirectoryNames = Set([
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "dist",
        "node_modules",
        "Packages",
    ])

    public static func scan(root: URL, maxDepth: Int = 6, limit: Int = 500) -> [LauncherWorkspaceFile] {
        guard limit > 0 else { return [] }
        let root = root.standardizedFileURL
        guard root.hasDirectoryPath || isDirectory(root) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [LauncherWorkspaceFile] = []
        for case let url as URL in enumerator {
            let standardized = url.standardizedFileURL
            let relativePath = relativePath(from: root, to: standardized)
            let depth = relativePath.split(separator: "/").count

            if isDirectory(standardized) {
                if shouldSkipDirectory(standardized) || depth >= maxDepth {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard depth <= maxDepth else { continue }
            guard isRegularFile(standardized) else { continue }

            files.append(LauncherWorkspaceFile(
                path: standardized.path,
                relativePath: relativePath
            ))
        }

        return files
            .sorted { lhs, rhs in
                lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    public static func commands(for files: [LauncherWorkspaceFile]) -> [LauncherCommand] {
        files.map { file in
            LauncherCommand(
                id: "workspace-file:\(file.path)",
                title: file.name,
                subtitle: file.relativePath,
                systemImage: file.systemImage,
                category: .workspace,
                keywords: keywordSet(values: [
                    file.name,
                    file.relativePath,
                    file.path,
                    file.fileExtension,
                    "file",
                    "workspace",
                    "project",
                    "open",
                ]),
                action: .openWorkspaceFile(file)
            )
        }
    }

    private static func shouldSkipDirectory(_ url: URL) -> Bool {
        excludedDirectoryNames.contains(url.lastPathComponent)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let filePath = url.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count))
    }

    private static func keywordSet(values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}
