import Foundation
import KWWKLauncherCore
import Testing

@Suite("Application index")
struct ApplicationIndexTests {
    @Test
    func scansApplicationBundlesFromRoots() throws {
        let root = try makeTempDirectory()
        let app = root.appendingPathComponent("Utilities", isDirectory: true)
            .appendingPathComponent("Fixture.app", isDirectory: true)
        try writeInfoPlist(
            in: app,
            values: [
                "CFBundleDisplayName": "Fixture Tool",
                "CFBundleIdentifier": "dev.kwwk.fixture-tool",
            ]
        )

        let results = ApplicationIndex.scan(roots: [root], maxDepth: 2)

        #expect(results.count == 1)
        #expect(results[0].displayName == "Fixture Tool")
        #expect(results[0].bundleIdentifier == "dev.kwwk.fixture-tool")
        #expect(results[0].path == app.standardizedFileURL.path)
        #expect(results[0].keywords.contains("fixture-tool"))
    }

    @Test
    func convertsApplicationsToLaunchCommands() {
        let app = IndexedApplication(
            displayName: "Fixture Tool",
            bundleIdentifier: "dev.kwwk.fixture-tool",
            path: "/Applications/Fixture.app",
            keywords: ["fixture", "tool"]
        )

        let command = ApplicationIndex.commands(for: [app])[0]

        #expect(command.id == "app:/Applications/Fixture.app")
        #expect(command.title == "Fixture Tool")
        #expect(command.category == .app)
        #expect(command.action == .openApplication("/Applications/Fixture.app"))
    }

    @Test
    func applicationCommandsParticipateInFiltering() {
        let command = ApplicationIndex.commands(for: [
            IndexedApplication(
                displayName: "Fixture Tool",
                bundleIdentifier: "dev.kwwk.fixture-tool",
                path: "/Applications/Fixture.app",
                keywords: ["fixture-tool"]
            ),
        ])

        let results = LauncherCommandFilter.filter(command, query: "fixture tool")

        #expect(results.first?.title == "Fixture Tool")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeInfoPlist(in appURL: URL, values: [String: String]) throws {
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: values,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
