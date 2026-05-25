import Foundation
import KWWKLauncherCore
import Testing

@Suite("Launcher script commands")
struct LauncherScriptCommandTests {
    @Test
    func scansExecutableScriptsWithKWWKMetadata() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("summarize_repo")
        try writeExecutableScript(
            at: script,
            text: """
            #!/usr/bin/env bash
            # @kwwk.title Summarize Repo
            # @kwwk.subtitle Summarize the current checkout
            # @kwwk.keywords repo, summary, agent
            # @kwwk.icon sparkles
            # @kwwk.argument-mode stdin
            # @kwwk.arguments --format "plain text"
            printf done
            """
        )

        let scripts = LauncherScriptCommandIndex.scan(roots: [root])

        #expect(scripts.count == 1)
        #expect(scripts[0].title == "Summarize Repo")
        #expect(scripts[0].subtitle == "Summarize the current checkout")
        #expect(scripts[0].systemImage == "sparkles")
        #expect(scripts[0].keywords.contains("summary"))
        #expect(scripts[0].arguments == ["--format", "plain text"])
        #expect(scripts[0].argumentMode == .stdin)
    }

    @Test
    func convertsScriptsToLauncherCommands() {
        let script = LauncherScriptCommand(
            id: "summarize",
            title: "Summarize Repo",
            subtitle: "Run automation",
            keywords: ["summary"],
            scriptPath: "/tmp/summarize"
        )

        let command = LauncherScriptCommandIndex.commands(for: [script])[0]

        #expect(command.id == "script:summarize")
        #expect(command.category == .script)
        #expect(command.action == .runScript(script))
    }

    @Test
    func scriptExportIncludesPathModeAndReplayableLauncherCommand() throws {
        let script = LauncherScriptCommand(
            id: "summarize",
            title: "Summarize Repo",
            subtitle: "Run automation",
            keywords: ["summary"],
            scriptPath: "/tmp/summarize",
            workingDirectory: "/tmp",
            arguments: ["--format", "plain"],
            argumentMode: .stdin
        )
        let fixedScript = LauncherScriptCommand(
            id: "open-dashboard",
            title: "Open Dashboard",
            subtitle: "No input",
            scriptPath: "/tmp/open-dashboard"
        )

        let table = LauncherScriptCommandExport.table(for: [script])
        let json = try LauncherScriptCommandExport.json(for: script)

        #expect(table == """
        summarize\tSummarize Repo\tRun automation\tstdin\t/tmp/summarize\tkwwk launcher --command script:summarize --run -- '<query>'
        """)
        #expect(json.contains("\"argumentMode\" : \"stdin\""))
        #expect(json.contains("\"arguments\" : [\n    \"--format\",\n    \"plain\"\n  ]"))
        #expect(json.contains("\"commandId\" : \"script:summarize\""))
        #expect(json.contains("\"launcherCommand\" : \"kwwk launcher --command script:summarize --run -- '<query>'\""))
        #expect(json.contains("\"launcherURL\" : \"kwwk:\\/\\/launcher?command=script:summarize\""))
        #expect(LauncherScriptCommandExport.launcherCommand(for: script, query: "repo status") == """
        kwwk launcher --command script:summarize --run -- 'repo status'
        """)
        #expect(LauncherScriptCommandExport.launcherURL(
            for: script,
            query: "repo status",
            workingDirectory: "/Users/f/project"
        ) == "kwwk://launcher?query=repo%20status&command=script:summarize&run=1&cwd=/Users/f/project")
        #expect(LauncherScriptCommandExport.launcherCommand(for: fixedScript) == """
        kwwk launcher --command script:open-dashboard --run
        """)
        #expect(LauncherScriptCommandExport.launcherURL(for: fixedScript) == "kwwk://launcher?command=script:open-dashboard&run=1")
    }

    @Test
    func raycastArgumentMetadataPassesQueryAsArgument() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("open-ticket")
        try writeExecutableScript(
            at: script,
            text: """
            #!/usr/bin/env bash
            # @raycast.title Open Ticket
            # @raycast.subtitle Jump to a tracker issue
            # @raycast.packageName issue tracker
            # @raycast.argument1 { "type": "text", "placeholder": "Ticket" }
            printf "$1"
            """
        )

        let command = try #require(LauncherScriptCommandIndex.scan(roots: [root]).first)
        let invocation = command.invocation(query: "KWWK-42")

        #expect(command.title == "Open Ticket")
        #expect(command.keywords.contains("issue tracker"))
        #expect(command.argumentMode == .argument)
        #expect(invocation.arguments == ["KWWK-42"])
        #expect(invocation.environment["KWWK_LAUNCHER_QUERY"] == "KWWK-42")
    }

    @Test
    func stdinModeBuildsRunnableInvocation() {
        let script = LauncherScriptCommand(
            id: "stdin-script",
            title: "Stdin Script",
            subtitle: "Uses stdin",
            scriptPath: "/tmp/stdin-script",
            workingDirectory: "/tmp",
            arguments: ["--fast"],
            argumentMode: .stdin
        )

        let invocation = script.invocation(query: "summarize this")

        #expect(invocation.executable == "/tmp/stdin-script")
        #expect(invocation.arguments == ["--fast"])
        #expect(invocation.stdin == "summarize this")
        #expect(invocation.workingDirectory == "/tmp")
        #expect(invocation.environment["KWWK_LAUNCHER_QUERY"] == "summarize this")
        #expect(invocation.environment["KWWK_LAUNCHER_CWD"] == "/tmp")
    }

    @Test
    func scriptsInheritLauncherWorkingDirectoryWhenUnset() {
        let script = LauncherScriptCommand(
            id: "workspace-script",
            title: "Workspace Script",
            subtitle: "Uses active workspace",
            scriptPath: "/Users/f/.kwwk/launcher/commands/workspace-script"
        )

        let invocation = script.invocation(
            query: "status",
            workingDirectoryOverride: "/Users/f/project/./"
        )

        #expect(invocation.workingDirectory == "/Users/f/project")
        #expect(invocation.environment["KWWK_LAUNCHER_QUERY"] == "status")
        #expect(invocation.environment["KWWK_LAUNCHER_CWD"] == "/Users/f/project")
        #expect(invocation.environment["KWWK_LAUNCHER_WORKSPACE"] == "/Users/f/project")
    }

    @Test
    func explicitScriptWorkingDirectoryWinsOverLauncherWorkingDirectory() {
        let script = LauncherScriptCommand(
            id: "pinned-script",
            title: "Pinned Script",
            subtitle: "Uses its own cwd",
            scriptPath: "/Users/f/.kwwk/launcher/commands/pinned-script",
            workingDirectory: "/Users/f/pinned"
        )

        let invocation = script.invocation(
            query: "status",
            workingDirectoryOverride: "/Users/f/project"
        )

        #expect(invocation.workingDirectory == "/Users/f/pinned")
        #expect(invocation.environment["KWWK_LAUNCHER_CWD"] == "/Users/f/pinned")
        #expect(invocation.environment["KWWK_LAUNCHER_WORKSPACE"] == "/Users/f/project")
    }

    @Test
    func scriptsFallBackToScriptFolderWithoutLauncherWorkingDirectory() {
        let script = LauncherScriptCommand(
            id: "folder-script",
            title: "Folder Script",
            subtitle: "Uses script folder",
            scriptPath: "/Users/f/.kwwk/launcher/commands/folder-script"
        )

        let invocation = script.invocation(query: "status")

        #expect(invocation.workingDirectory == "/Users/f/.kwwk/launcher/commands")
        #expect(invocation.environment["KWWK_LAUNCHER_CWD"] == "/Users/f/.kwwk/launcher/commands")
        #expect(invocation.environment["KWWK_LAUNCHER_WORKSPACE"] == nil)
    }

    @Test
    func ignoresNonExecutableFiles() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("not-executable")
        try "# @kwwk.title Hidden\n".write(to: script, atomically: true, encoding: .utf8)

        let scripts = LauncherScriptCommandIndex.scan(roots: [root])

        #expect(scripts.isEmpty)
    }

    @Test
    func shellCommandsBecomeExecutableScriptDrafts() throws {
        let draft = try #require(LauncherScriptCommandIndex.scriptDraft(
            fromShellCommand: "git status --short"
        ))

        #expect(draft.id == "saved-git-status-short")
        #expect(draft.title == "Git Status Short")
        #expect(draft.subtitle == "Saved shell command")
        #expect(draft.fileName == "saved-git-status-short.zsh")
        #expect(draft.scriptText.contains("# @kwwk.id saved-git-status-short"))
        #expect(draft.scriptText.contains("# @kwwk.title Git Status Short"))
        #expect(draft.scriptText.contains("# @kwwk.keywords shell, command, saved, git, status, short"))
        #expect(draft.scriptText.contains("git status --short"))
        #expect(LauncherScriptCommandIndex.scriptDraft(fromShellCommand: "   ") == nil)
    }

    @Test
    func savesShellCommandDraftsAsScannableScripts() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = try #require(LauncherScriptCommandIndex.scriptDraft(
            fromShellCommand: "git status --short"
        ))

        let url = try LauncherScriptCommandIndex.save(draft, to: root)
        let scripts = LauncherScriptCommandIndex.scan(roots: [root])
        let script = try #require(scripts.first)

        #expect(url.lastPathComponent == "saved-git-status-short.zsh")
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
        #expect(script.id == "saved-git-status-short")
        #expect(script.title == "Git Status Short")
        #expect(script.subtitle == "Saved shell command")
        #expect(script.scriptPath == url.path)
        #expect(script.keywords.contains("saved"))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeExecutableScript(at url: URL, text: String) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
