import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher deep links")
struct LauncherDeepLinkTests {
    @Test
    func buildsSearchURLWithQuery() {
        let request = LauncherDeepLinkRequest(query: "open terminal", workingDirectory: "/Users/f/project")

        #expect(request.url.absoluteString == "kwwk://launcher?query=open%20terminal&cwd=/Users/f/project")
    }

    @Test
    func buildsCommandURLWithInputQuery() {
        let request = LauncherDeepLinkRequest(
            query: "KWWK-42",
            commandId: "script:open-ticket",
            runImmediately: true,
            workingDirectory: "/Users/f/project"
        )

        #expect(request.url.absoluteString == "kwwk://launcher?query=KWWK-42&command=script:open-ticket&run=1&cwd=/Users/f/project")
    }

    @Test
    func buildsCommandActionURLWithInputQuery() {
        let request = LauncherDeepLinkRequest(
            query: "KWWK-42",
            commandId: "script:open-ticket",
            actionId: "copy-launcher-command",
            runImmediately: true,
            workingDirectory: "/Users/f/project"
        )

        #expect(request.url.absoluteString == "kwwk://launcher?query=KWWK-42&command=script:open-ticket&action=copy-launcher-command&run=1&cwd=/Users/f/project")
    }

    @Test
    func buildsAskURLWithRunFlag() {
        let request = LauncherDeepLinkRequest(mode: .ask, query: "summarize repo", runImmediately: true)

        #expect(request.url.absoluteString == "kwwk://launcher/ask?prompt=summarize%20repo&run=1")
    }

    @Test
    func buildsResidentControlURLs() {
        let hide = LauncherDeepLinkRequest(mode: .hide)
        let toggle = LauncherDeepLinkRequest(mode: .toggle)

        #expect(hide.url.absoluteString == "kwwk://launcher/hide")
        #expect(toggle.url.absoluteString == "kwwk://launcher/toggle")
    }

    @Test
    func buildsAskURLWithPathContext() {
        let request = LauncherDeepLinkRequest(
            mode: .ask,
            query: "summarize it",
            pathContext: "./README.md",
            runImmediately: true,
            workingDirectory: "/Users/f/project"
        )

        #expect(request.url.absoluteString == "kwwk://launcher/ask?prompt=summarize%20it&path=./README.md&run=1&cwd=/Users/f/project")
    }

    @Test
    func buildsAskURLWithMultiplePathContexts() {
        let request = LauncherDeepLinkRequest(
            mode: .ask,
            query: "compare them",
            pathContexts: ["./README.md", "./Package.swift"],
            runImmediately: true,
            workingDirectory: "/Users/f/project"
        )

        #expect(request.url.absoluteString == "kwwk://launcher/ask?prompt=compare%20them&path=./README.md&path=./Package.swift&run=1&cwd=/Users/f/project")
    }

    @Test
    func parsesAskURLAndDefaultsToRun() throws {
        let url = try #require(URL(string: "kwwk://launcher/ask?prompt=summarize%20repo"))

        let request = try #require(LauncherDeepLinkRequest(url: url))

        #expect(request.mode == .ask)
        #expect(request.query == "summarize repo")
        #expect(request.runImmediately)
    }

    @Test
    func parsesResidentControlURLs() throws {
        let hideURL = try #require(URL(string: "kwwk://launcher/hide"))
        let toggleURL = try #require(URL(string: "kwwk://launcher/toggle"))

        let hide = try #require(LauncherDeepLinkRequest(url: hideURL))
        let toggle = try #require(LauncherDeepLinkRequest(url: toggleURL))

        #expect(hide.mode == .hide)
        #expect(!hide.runImmediately)
        #expect(toggle.mode == .toggle)
        #expect(!toggle.runImmediately)
    }

    @Test
    func residentControlURLsNeverRunCommands() {
        let request = LauncherDeepLinkRequest(mode: .toggle, query: "open-cli", runImmediately: true)

        #expect(request.mode == .toggle)
        #expect(request.query == "open-cli")
        #expect(!request.runImmediately)
    }

    @Test
    func parsesSearchURLWithExplicitRunFlag() throws {
        let url = try #require(URL(string: "kwwk://launcher?query=KWWK%20Login&run=true"))

        let request = try #require(LauncherDeepLinkRequest(url: url))

        #expect(request.mode == .search)
        #expect(request.query == "KWWK Login")
        #expect(request.runImmediately)
    }

    @Test
    func parsesWorkingDirectoryContext() throws {
        let url = try #require(URL(string: "kwwk://launcher/ask?prompt=review&cwd=/Users/f/project"))

        let request = try #require(LauncherDeepLinkRequest(url: url))

        #expect(request.workingDirectory == "/Users/f/project")
    }

    @Test
    func parsesPathContext() throws {
        let url = try #require(URL(string: "kwwk://launcher/ask?prompt=review&path=./README.md&run=1"))

        let request = try #require(LauncherDeepLinkRequest(url: url))

        #expect(request.mode == .ask)
        #expect(request.query == "review")
        #expect(request.pathContext == "./README.md")
        #expect(request.pathContexts == ["./README.md"])
        #expect(request.runImmediately)
    }

    @Test
    func parsesRepeatedPathContexts() throws {
        let url = try #require(URL(string: "kwwk://launcher/ask?prompt=compare&path=./README.md&path=./Package.swift&run=1"))

        let request = try #require(LauncherDeepLinkRequest(url: url))

        #expect(request.mode == .ask)
        #expect(request.query == "compare")
        #expect(request.pathContext == "./README.md")
        #expect(request.pathContexts == ["./README.md", "./Package.swift"])
        #expect(request.runImmediately)
    }

    @Test
    func parsesCommandId() throws {
        let url = try #require(URL(string: "kwwk://launcher?query=KWWK-42&command=script:open-ticket&run=1"))

        let request = try #require(LauncherDeepLinkRequest(url: url))

        #expect(request.query == "KWWK-42")
        #expect(request.commandId == "script:open-ticket")
        #expect(request.runImmediately)
    }

    @Test
    func parsesActionId() throws {
        let url = try #require(URL(string: "kwwk://launcher?command=open-cli&action=copy-launcher-command&run=1"))

        let request = try #require(LauncherDeepLinkRequest(url: url))

        #expect(request.commandId == "open-cli")
        #expect(request.actionId == "copy-launcher-command")
        #expect(request.runImmediately)
    }

    @Test
    func ignoresUnsupportedURLs() throws {
        let wrongScheme = try #require(URL(string: "https://launcher?query=x"))
        let wrongHost = try #require(URL(string: "kwwk://agent?query=x"))

        #expect(LauncherDeepLinkRequest(url: wrongScheme) == nil)
        #expect(LauncherDeepLinkRequest(url: wrongHost) == nil)
    }

    @Test
    func neverRunsEmptyRequestsImmediately() throws {
        let request = LauncherDeepLinkRequest(mode: .ask, query: "  ", runImmediately: true)

        #expect(request.query.isEmpty)
        #expect(!request.runImmediately)
    }

    @Test
    func commandOnlyRequestsCanRunImmediately() {
        let request = LauncherDeepLinkRequest(commandId: "open-cli", runImmediately: true)

        #expect(request.query.isEmpty)
        #expect(request.commandId == "open-cli")
        #expect(request.runImmediately)
    }

    @Test
    func pathOnlyAskRequestsCanRunImmediately() {
        let request = LauncherDeepLinkRequest(mode: .ask, pathContext: "./README.md", runImmediately: true)

        #expect(request.query.isEmpty)
        #expect(request.pathContext == "./README.md")
        #expect(request.pathContexts == ["./README.md"])
        #expect(request.runImmediately)
    }
}
