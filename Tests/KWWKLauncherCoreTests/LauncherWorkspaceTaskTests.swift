import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher workspace tasks")
struct LauncherWorkspaceTaskTests {
    @Test
    func emptyWorkspaceDoesNotCreateTaskCommands() {
        #expect(LauncherWorkspaceTaskCommandFactory.commands(for: nil).isEmpty)
        #expect(LauncherWorkspaceTaskCommandFactory.commands(for: "/definitely/not/a/kwwk/workspace").isEmpty)
    }

    @Test
    func packageJSONScriptsBecomeWorkspaceTasksUsingBunByDefault() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("package.json"), """
        {
          "scripts": {
            "dev": "vite --host 0.0.0.0",
            "test": "vitest --run"
          }
        }
        """)

        let commands = LauncherWorkspaceTaskCommandFactory.commands(for: root.path)

        #expect(commands.map(\.id) == [
            "workspace-task:package-json:dev",
            "workspace-task:package-json:test",
        ])
        let test = try #require(commands.first { $0.id == "workspace-task:package-json:test" })
        #expect(test.title == "Run test")
        #expect(test.subtitle == "bun run test - vitest --run")
        #expect(test.category == .workspace)
        #expect(test.action == .runShellCommand("bun run test"))
        #expect(test.keywords.contains("tests"))
    }

    @Test
    func packageManagerAndLockfilesChooseNonNpmRunners() throws {
        let pnpmRoot = try makeTempDirectory()
        let yarnRoot = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: pnpmRoot)
            try? FileManager.default.removeItem(at: yarnRoot)
        }
        try writeFile(pnpmRoot.appendingPathComponent("package.json"), """
        {
          "packageManager": "pnpm@10.0.0",
          "scripts": { "lint": "eslint ." }
        }
        """)
        try writeFile(yarnRoot.appendingPathComponent("package.json"), """
        {
          "scripts": { "build": "vite build" }
        }
        """)
        try writeFile(yarnRoot.appendingPathComponent("yarn.lock"), "")

        let pnpm = try #require(LauncherWorkspaceTaskCommandFactory.commands(for: pnpmRoot.path).first)
        let yarn = try #require(LauncherWorkspaceTaskCommandFactory.commands(for: yarnRoot.path).first)

        #expect(pnpm.action == .runShellCommand("pnpm run lint"))
        #expect(yarn.action == .runShellCommand("yarn run build"))
    }

    @Test
    func swiftPackageCreatesBuildAndTestTasks() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("Package.swift"), "// swift-tools-version: 6.1")

        let commands = LauncherWorkspaceTaskCommandFactory.commands(for: root.path)

        #expect(commands.map(\.id) == [
            "workspace-task:swift:build",
            "workspace-task:swift:test",
        ])
        #expect(commands.first?.action == .runShellCommand(
            "/usr/bin/nice -n ${KWWK_SWIFT_BUILD_NICE:-5} swift build --jobs ${KWWK_SWIFT_BUILD_JOBS:-2}"
        ))
        #expect(commands.last?.action == .runShellCommand(
            "/usr/bin/nice -n ${KWWK_SWIFT_BUILD_NICE:-5} swift test --jobs ${KWWK_SWIFT_BUILD_JOBS:-2}"
        ))
    }

    @Test
    func cargoPackageCreatesBuildTestAndRunTasks() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("Cargo.toml"), "[package]\nname = \"demo\"")

        let commands = LauncherWorkspaceTaskCommandFactory.commands(for: root.path)

        #expect(commands.map(\.id) == [
            "workspace-task:cargo:build",
            "workspace-task:cargo:test",
            "workspace-task:cargo:run",
        ])
        #expect(commands.map(\.action) == [
            .runShellCommand("cargo build"),
            .runShellCommand("cargo test"),
            .runShellCommand("cargo run"),
        ])
    }

    @Test
    func workspaceTasksRankAheadOfFallbackAskForProjectTaskQueries() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("package.json"), """
        { "scripts": { "test": "vitest --run" } }
        """)
        let query = "run project tests"
        let commands = LauncherWorkspaceTaskCommandFactory.commands(for: root.path)
            + LauncherDynamicCommandFactory.commands(for: query)

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "workspace-task:package-json:test")
    }

    @Test
    func workspaceTaskActionsUseShellCommandBridge() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeFile(root.appendingPathComponent("Package.swift"), "// swift-tools-version: 6.1")
        let command = try #require(LauncherWorkspaceTaskCommandFactory.commands(for: root.path).first)

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Run")
        #expect(actions.first { $0.id == "copy-command" }?.kind == .copyText(
            "/usr/bin/nice -n ${KWWK_SWIFT_BUILD_NICE:-5} swift build --jobs ${KWWK_SWIFT_BUILD_JOBS:-2}"
        ))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command workspace-task:swift:build --run -- '$ /usr/bin/nice -n ${KWWK_SWIFT_BUILD_NICE:-5} swift build --jobs ${KWWK_SWIFT_BUILD_JOBS:-2}'"
        ))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL, _ text: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
