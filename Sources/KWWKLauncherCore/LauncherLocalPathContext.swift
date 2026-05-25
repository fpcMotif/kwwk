import Foundation

public enum LauncherLocalPathContextBuilder {
    public static let defaultMaxBytes = 64 * 1024
    public static let defaultMaxCharacters = 12_000
    public static let defaultDirectoryLimit = 40

    public static func promptContext(
        for path: String,
        displayPath: String,
        isDirectory: Bool? = nil,
        maxBytes: Int = defaultMaxBytes,
        maxCharacters: Int = defaultMaxCharacters,
        directoryLimit: Int = defaultDirectoryLimit
    ) -> String? {
        let url = URL(fileURLWithPath: path)
            .standardizedFileURL
        let resolvedIsDirectory: Bool
        if let isDirectory {
            resolvedIsDirectory = isDirectory
        } else {
            var directoryFlag = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directoryFlag) else {
                return nil
            }
            resolvedIsDirectory = directoryFlag.boolValue
        }

        if resolvedIsDirectory {
            return directoryContext(for: url, displayPath: displayPath, limit: directoryLimit)
        }
        return fileContext(for: url, displayPath: displayPath, maxBytes: maxBytes, maxCharacters: maxCharacters)
    }

    private static func fileContext(
        for url: URL,
        displayPath: String,
        maxBytes: Int,
        maxCharacters: Int
    ) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true
        else {
            return nil
        }

        let size = max(0, values.fileSize ?? 0)
        guard size <= maxBytes else {
            return [
                "File content omitted: \(displayPath) is \(size) bytes, above the \(maxBytes)-byte launcher prompt limit.",
            ].joined(separator: "\n")
        }

        guard let data = try? Data(contentsOf: url) else {
            return "File content unavailable: \(displayPath) could not be read."
        }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\u{0000}") else {
            return "File content omitted: \(displayPath) does not look like UTF-8 text."
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "File content: \(displayPath) is empty."
        }

        let excerpt = String(trimmed.prefix(maxCharacters))
        let suffix = trimmed.count > maxCharacters ? "\n\n[truncated to \(maxCharacters) characters]" : ""
        return [
            "File content excerpt (\(displayPath)):",
            "```",
            excerpt + suffix,
            "```",
        ].joined(separator: "\n")
    }

    private static func directoryContext(for url: URL, displayPath: String, limit: Int) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "Directory listing unavailable: \(displayPath) could not be read."
        }

        let sorted = entries.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let rendered = sorted.prefix(max(0, limit)).map { entry in
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return "\(entry.lastPathComponent)\(isDirectory ? "/" : "")"
        }
        guard !rendered.isEmpty else {
            return "Directory listing: \(displayPath) is empty."
        }

        let omitted = sorted.count > rendered.count ? "\n... \(sorted.count - rendered.count) more entries" : ""
        return [
            "Directory listing (\(displayPath)):",
            rendered.joined(separator: "\n") + omitted,
        ].joined(separator: "\n")
    }
}
