import Foundation
import KWWKLauncherCore
import Testing

@Suite("KWWK CLI invocation")
struct KWWKCLIInvocationTests {
    @Test
    func buildsHeadlessInvocationWithStdinPrompt() {
        let invocation = KWWKCLIInvocation.headless(
            prompt: "summarize Sources",
            thinking: .high,
            model: "gpt-5.4",
            context1m: true,
            workingDirectory: "/Users/f/project"
        )

        #expect(invocation.executable == "kwwk")
        #expect(invocation.arguments == ["--thinking", "high", "--model", "gpt-5.4", "--context-1m", "-p", "-"])
        #expect(invocation.stdin == "summarize Sources")
        #expect(invocation.workingDirectory == "/Users/f/project")
    }

    @Test
    func shellCommandQuotesUnsafeArguments() {
        let invocation = KWWKCLIInvocation(executable: "kwwk", arguments: ["-p", "hello world"])

        #expect(invocation.shellCommand == "kwwk -p 'hello world'")
    }

    @Test
    func terminalShellCommandChangesIntoWorkingDirectory() {
        let invocation = KWWKCLIInvocation.interactive(
            executable: "kwwk",
            workingDirectory: "/Users/f/My Project"
        )

        #expect(invocation.terminalShellCommand == "cd '/Users/f/My Project' && kwwk")
    }

    @Test
    func terminalShellCommandLeavesPlainCommandWithoutWorkingDirectory() {
        let invocation = KWWKCLIInvocation.login(executable: "kwwk")

        #expect(invocation.terminalShellCommand == "kwwk login")
    }

    @Test
    func buildsInteractiveDraftInvocationWithLauncherOptions() {
        let invocation = KWWKCLIInvocation.interactiveDraft(
            prompt: "fix the failing tests",
            executable: "/tmp/kwwk helper",
            thinking: .xhigh,
            model: "gpt-5.4",
            context1m: true,
            workingDirectory: "/Users/f/My Project"
        )

        #expect(invocation.arguments == [
            "--thinking", "xhigh",
            "--model", "gpt-5.4",
            "--context-1m",
            "--draft", "fix the failing tests",
        ])
        #expect(invocation.terminalShellCommand == "cd '/Users/f/My Project' && '/tmp/kwwk helper' --thinking xhigh --model gpt-5.4 --context-1m --draft 'fix the failing tests'")
    }

    @Test
    func headlessTerminalCommandPipesPromptAndKeepsLauncherOptions() {
        let command = KWWKCLIInvocation.headlessTerminalCommand(
            prompt: "summarize repo",
            executable: "/Applications/KWWKLauncher.app/Contents/MacOS/kwwk",
            thinking: .xhigh,
            model: "gpt-5.4",
            context1m: true,
            workingDirectory: "/Users/f/My Project"
        )

        #expect(command == [
            "cd '/Users/f/My Project' && printf %s 'summarize repo' |",
            "/Applications/KWWKLauncher.app/Contents/MacOS/kwwk",
            "--thinking xhigh --model gpt-5.4 --context-1m -p -",
        ].joined(separator: " "))
    }

    @Test
    func terminalCommandWrapsRawShellCommandInWorkingDirectory() {
        let command = KWWKShellCommand.terminalCommand(
            "git status --short",
            workingDirectory: "/Users/f/My Project"
        )

        #expect(command == "cd '/Users/f/My Project' && git status --short")
    }

    @Test
    func processClientUsesWorkingDirectoryAndEnvironment() async throws {
        let client = ProcessBackedKWWKCLIClient()
        let workingDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let result = try await client.run(KWWKCLIInvocation(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s:%s' \"$PWD\" \"$KWWK_TEST_VALUE\""],
            workingDirectory: workingDirectory.path,
            environment: ["KWWK_TEST_VALUE": "ok"]
        ))

        #expect(result.exitCode == 0)
        #expect(result.stdout == "\(workingDirectory.path):ok")
    }

    @Test
    func processClientCapturesStdoutAndStreamingChunks() async throws {
        let client = ProcessBackedKWWKCLIClient()
        let chunks = ChunkBox()
        let result = try await client.run(
            KWWKCLIInvocation(executable: "/bin/cat", arguments: [], stdin: "hello\n"),
            onStdout: { chunk in chunks.append(chunk) }
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "hello\n")
        #expect(chunks.joined() == "hello\n")
    }

    @Test
    func processClientTerminatesProcessWhenTaskIsCancelled() async throws {
        let client = ProcessBackedKWWKCLIClient()
        let startedAt = Date()
        let task = Task {
            try await client.run(KWWKCLIInvocation(executable: "/bin/sleep", arguments: ["5"]))
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(Date().timeIntervalSince(startedAt) < 2)
        }
    }
}

private final class ChunkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.withLock {
            values.append(value)
        }
    }

    func joined() -> String {
        lock.withLock {
            values.joined()
        }
    }
}
