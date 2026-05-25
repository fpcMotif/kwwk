import Foundation

public enum LauncherWorkspaceTaskCommandFactory {
    public static let commandPrefix = "workspace-task:"
    private static let swiftBuildJobs = "${KWWK_SWIFT_BUILD_JOBS:-2}"
    private static let swiftBuildNice = "${KWWK_SWIFT_BUILD_NICE:-5}"

    public static func commands(for workingDirectory: String?) -> [LauncherCommand] {
        guard let context = LauncherWorkspaceContext(path: workingDirectory),
              isDirectory(context.path)
        else {
            return []
        }

        let root = URL(fileURLWithPath: context.path, isDirectory: true)
        return packageScriptCommands(root: root)
            + swiftPackageCommands(root: root)
            + cargoCommands(root: root)
    }

    private static func packageScriptCommands(root: URL) -> [LauncherCommand] {
        let packageURL = root.appendingPathComponent("package.json")
        guard let document = packageJSONDocument(at: packageURL),
              let scripts = document["scripts"] as? [String: Any],
              !scripts.isEmpty
        else {
            return []
        }

        let manager = JavaScriptPackageManager.detect(root: root, packageDocument: document)
        return scripts.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .compactMap { name -> LauncherCommand? in
                guard let body = scripts[name] as? String,
                      !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return nil
                }

                let commandText = "\(manager.commandName) run \(KWWKShellCommand.quote(name))"
                return taskCommand(
                    id: "package-json:\(name)",
                    title: "Run \(name)",
                    subtitle: "\(commandText) - \(body.truncatedForWorkspaceTask(maxLength: 72))",
                    systemImage: "curlybraces",
                    commandText: commandText,
                    keywords: [
                        "package",
                        "package.json",
                        "javascript",
                        "typescript",
                        "node",
                        manager.commandName,
                        manager.displayName,
                        name,
                        body,
                        commandText,
                    ] + testKeywords(for: name)
                )
            }
    }

    private static func swiftPackageCommands(root: URL) -> [LauncherCommand] {
        guard fileExists(root.appendingPathComponent("Package.swift")) else { return [] }

        let buildCommand = "/usr/bin/nice -n \(swiftBuildNice) swift build --jobs \(swiftBuildJobs)"
        let testCommand = "/usr/bin/nice -n \(swiftBuildNice) swift test --jobs \(swiftBuildJobs)"
        return [
            taskCommand(
                id: "swift:build",
                title: "Swift Build",
                subtitle: buildCommand,
                systemImage: "swift",
                commandText: buildCommand,
                keywords: ["swift", "swiftpm", "package", "build", "compile", "project"]
            ),
            taskCommand(
                id: "swift:test",
                title: "Swift Test",
                subtitle: testCommand,
                systemImage: "checkmark.circle",
                commandText: testCommand,
                keywords: ["swift", "swiftpm", "package", "test", "tests", "project", "verify"]
            ),
        ]
    }

    private static func cargoCommands(root: URL) -> [LauncherCommand] {
        guard fileExists(root.appendingPathComponent("Cargo.toml")) else { return [] }

        return [
            taskCommand(
                id: "cargo:build",
                title: "Cargo Build",
                subtitle: "cargo build",
                systemImage: "shippingbox",
                commandText: "cargo build",
                keywords: ["rust", "cargo", "build", "compile", "project"]
            ),
            taskCommand(
                id: "cargo:test",
                title: "Cargo Test",
                subtitle: "cargo test",
                systemImage: "checkmark.circle",
                commandText: "cargo test",
                keywords: ["rust", "cargo", "test", "tests", "project", "verify"]
            ),
            taskCommand(
                id: "cargo:run",
                title: "Cargo Run",
                subtitle: "cargo run",
                systemImage: "play",
                commandText: "cargo run",
                keywords: ["rust", "cargo", "run", "project", "execute"]
            ),
        ]
    }

    private static func taskCommand(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        commandText: String,
        keywords: [String]
    ) -> LauncherCommand {
        LauncherCommand(
            id: "\(commandPrefix)\(id)",
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            category: .workspace,
            keywords: keywordSet(values: ["workspace", "project", "task", commandText] + keywords),
            action: .runShellCommand(commandText)
        )
    }

    private static func packageJSONDocument(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let document = object as? [String: Any]
        else {
            return nil
        }
        return document
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func testKeywords(for name: String) -> [String] {
        name.localizedCaseInsensitiveContains("test") ? ["test", "tests", "verify"] : []
    }

    private static func keywordSet(values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

private enum JavaScriptPackageManager {
    case bun
    case pnpm
    case yarn

    var commandName: String {
        switch self {
        case .bun:
            return "bun"
        case .pnpm:
            return "pnpm"
        case .yarn:
            return "yarn"
        }
    }

    var displayName: String {
        switch self {
        case .bun:
            return "Bun"
        case .pnpm:
            return "pnpm"
        case .yarn:
            return "Yarn"
        }
    }

    static func detect(root: URL, packageDocument: [String: Any]) -> JavaScriptPackageManager {
        if let packageManager = packageDocument["packageManager"] as? String {
            let lowercased = packageManager.lowercased()
            if lowercased.hasPrefix("pnpm@") { return .pnpm }
            if lowercased.hasPrefix("yarn@") { return .yarn }
            if lowercased.hasPrefix("bun@") { return .bun }
        }

        if FileManager.default.fileExists(atPath: root.appendingPathComponent("pnpm-lock.yaml").path) {
            return .pnpm
        }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("yarn.lock").path) {
            return .yarn
        }
        return .bun
    }
}

private extension String {
    func truncatedForWorkspaceTask(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let end = index(startIndex, offsetBy: maxLength)
        return String(self[..<end]) + "..."
    }
}
