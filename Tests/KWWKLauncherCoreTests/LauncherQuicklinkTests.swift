import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher quicklinks")
struct LauncherQuicklinkTests {
    @Test
    func rendersQueryPlaceholdersWithPercentEncoding() {
        let quicklink = LauncherQuicklink(
            id: "github-search",
            title: "GitHub Search",
            keywords: ["gh"],
            urlTemplate: "https://github.com/search?q={query}&type=code"
        )

        #expect(
            quicklink.renderedURLString(query: "gh swift package manager")
                == "https://github.com/search?q=swift%20package%20manager&type=code"
        )
    }

    @Test
    func leavesFixedURLsUntouched() {
        let quicklink = LauncherQuicklink(
            id: "docs",
            title: "Docs",
            urlTemplate: "https://example.com/docs"
        )

        #expect(quicklink.renderedURLString(query: "anything") == "https://example.com/docs")
    }

    @Test
    func loadsArrayAndDocumentJSONFormats() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let arrayURL = directory.appendingPathComponent("array.json")
        let documentURL = directory.appendingPathComponent("document.json")

        try """
        [
          {
            "id": "github-search",
            "title": "GitHub Search",
            "subtitle": "Search code",
            "keywords": ["gh"],
            "urlTemplate": "https://github.com/search?q={query}"
          }
        ]
        """.write(to: arrayURL, atomically: true, encoding: .utf8)

        try """
        {
          "quicklinks": [
            {
              "id": "linear",
              "title": "Linear Issue",
              "systemImage": "number",
              "urlTemplate": "https://linear.app/team/issue/{argument}"
            }
          ]
        }
        """.write(to: documentURL, atomically: true, encoding: .utf8)

        let arrayQuicklink = try #require(LauncherQuicklinkIndex.load(from: arrayURL).first)
        let documentQuicklink = try #require(LauncherQuicklinkIndex.load(from: documentURL).first)

        #expect(arrayQuicklink.id == "github-search")
        #expect(documentQuicklink.id == "linear")
    }

    @Test
    func dynamicURLCommandsBecomeSavedQuicklinks() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "https://example.com/docs").first)
        let quicklink = try #require(LauncherQuicklinkIndex.quicklink(fromDynamicCommand: command))

        #expect(quicklink.id == "saved-example-com-docs")
        #expect(quicklink.title == "Example Docs")
        #expect(quicklink.subtitle == "Saved URL")
        #expect(quicklink.urlTemplate == "https://example.com/docs")
        #expect(quicklink.keywords.contains("saved"))
        #expect(quicklink.keywords.contains("example.com"))
    }

    @Test
    func dynamicSearchCommandsBecomeSavedQuicklinks() throws {
        let command = try #require(LauncherWebCommandFactory.commands(for: "web swift package manager").first)
        let quicklink = try #require(LauncherQuicklinkIndex.quicklink(fromDynamicCommand: command))

        #expect(quicklink.id == "saved-search-swift-package-manager")
        #expect(quicklink.title == "Search Swift Package Manager")
        #expect(quicklink.subtitle == "Saved web search")
        #expect(quicklink.systemImage == "magnifyingglass")
        #expect(quicklink.urlTemplate == "https://duckduckgo.com/?q=swift%20package%20manager")
        #expect(quicklink.keywords.contains("web"))
        #expect(quicklink.keywords.contains("swift"))
    }

    @Test
    func upsertWritesAndReplacesQuicklinks() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("quicklinks.json")

        try LauncherQuicklinkIndex.upsert(
            LauncherQuicklink(
                id: "docs",
                title: "Docs",
                subtitle: "Old",
                urlTemplate: "https://example.com/old"
            ),
            to: url
        )
        try LauncherQuicklinkIndex.upsert(
            LauncherQuicklink(
                id: "docs",
                title: "Docs",
                subtitle: "New",
                keywords: ["reference"],
                urlTemplate: "https://example.com/new"
            ),
            to: url
        )

        let quicklinks = LauncherQuicklinkIndex.load(from: url)
        let quicklink = try #require(quicklinks.first)
        #expect(quicklinks.count == 1)
        #expect(quicklink.subtitle == "New")
        #expect(quicklink.urlTemplate == "https://example.com/new")
        #expect(quicklink.keywords == ["reference"])
    }

    @Test
    func quicklinkCommandsAreSearchableLauncherCommands() throws {
        let quicklink = LauncherQuicklink(
            id: "github-search",
            title: "GitHub Search",
            subtitle: "Search GitHub code",
            keywords: ["gh"],
            urlTemplate: "https://github.com/search?q={query}"
        )

        let command = try #require(LauncherQuicklinkIndex.commands(for: [quicklink]).first)

        #expect(command.id == "quicklink:github-search")
        #expect(command.category == .quicklink)
        #expect(command.keywords.contains("quicklink"))
        #expect(command.action == .openQuicklink(quicklink))
    }

    @Test
    func quicklinkExportIncludesReplayableLauncherCommands() throws {
        let quicklink = LauncherQuicklink(
            id: "github-search",
            title: "GitHub Search",
            subtitle: "Search GitHub code",
            keywords: ["gh"],
            urlTemplate: "https://github.com/search?q={query}"
        )

        let table = LauncherQuicklinkExport.table(for: [quicklink])
        let json = try LauncherQuicklinkExport.json(for: quicklink)

        #expect(table == """
        github-search\tGitHub Search\tSearch GitHub code\thttps://github.com/search?q={query}\tkwwk launcher --command quicklink:github-search --run -- '<query>'
        """)
        #expect(json.contains("\"commandId\" : \"quicklink:github-search\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command quicklink:github-search --run -- '<query>'\""))
        #expect(json.contains("\"launcherURL\" : \"kwwk:\\/\\/launcher?command=quicklink:github-search\""))
        #expect(json.contains("\"urlTemplate\" : \"https:\\/\\/github.com\\/search?q={query}\""))
        #expect(LauncherQuicklinkExport.launcherURL(
            for: quicklink,
            query: "gh swift package manager",
            workingDirectory: "/Users/f/project"
        ) == "kwwk://launcher?query=swift%20package%20manager&command=quicklink:github-search&run=1&cwd=/Users/f/project")
    }
}
