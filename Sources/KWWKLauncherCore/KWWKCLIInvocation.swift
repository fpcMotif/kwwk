import Foundation

public enum KWWKThinkingLevel: String, CaseIterable, Codable, Sendable, Hashable {
    case off
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public struct KWWKCLIInvocation: Sendable, Hashable {
    public var executable: String
    public var arguments: [String]
    public var stdin: String?
    public var workingDirectory: String?
    public var environment: [String: String]

    public init(
        executable: String = "kwwk",
        arguments: [String],
        stdin: String? = nil,
        workingDirectory: String? = nil,
        environment: [String: String] = [:]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.stdin = stdin
        self.workingDirectory = workingDirectory
        self.environment = environment
    }

    public static func headless(
        prompt: String,
        executable: String = "kwwk",
        thinking: KWWKThinkingLevel = .medium,
        model: String? = nil,
        context1m: Bool = false,
        workingDirectory: String? = nil
    ) -> KWWKCLIInvocation {
        var args: [String] = ["--thinking", thinking.rawValue]
        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["--model", model]
        }
        if context1m { args.append("--context-1m") }
        args += ["-p", "-"]
        return KWWKCLIInvocation(
            executable: executable,
            arguments: args,
            stdin: prompt,
            workingDirectory: workingDirectory
        )
    }

    public static func interactive(
        executable: String = "kwwk",
        workingDirectory: String? = nil
    ) -> KWWKCLIInvocation {
        KWWKCLIInvocation(executable: executable, arguments: [], workingDirectory: workingDirectory)
    }

    public static func interactiveDraft(
        prompt: String,
        executable: String = "kwwk",
        thinking: KWWKThinkingLevel = .medium,
        model: String? = nil,
        context1m: Bool = false,
        workingDirectory: String? = nil
    ) -> KWWKCLIInvocation {
        var args: [String] = ["--thinking", thinking.rawValue]
        if let model, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["--model", model]
        }
        if context1m { args.append("--context-1m") }
        args += ["--draft", prompt]
        return KWWKCLIInvocation(
            executable: executable,
            arguments: args,
            workingDirectory: workingDirectory
        )
    }

    public static func login(
        executable: String = "kwwk",
        workingDirectory: String? = nil
    ) -> KWWKCLIInvocation {
        KWWKCLIInvocation(executable: executable, arguments: ["login"], workingDirectory: workingDirectory)
    }

    public static func headlessTerminalCommand(
        prompt: String,
        executable: String = "kwwk",
        thinking: KWWKThinkingLevel = .medium,
        model: String? = nil,
        context1m: Bool = false,
        workingDirectory: String? = nil
    ) -> String {
        let invocation = headless(
            prompt: prompt,
            executable: executable,
            thinking: thinking,
            model: model,
            context1m: context1m,
            workingDirectory: workingDirectory
        )
        let command = "printf %s \(KWWKShellCommand.quote(prompt)) | \(invocation.shellCommand)"
        guard let workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty
        else {
            return command
        }
        return "cd \(KWWKShellCommand.quote(workingDirectory)) && \(command)"
    }

    public static func interactiveDraftTerminalCommand(
        prompt: String,
        executable: String = "kwwk",
        thinking: KWWKThinkingLevel = .medium,
        model: String? = nil,
        context1m: Bool = false,
        workingDirectory: String? = nil
    ) -> String {
        interactiveDraft(
            prompt: prompt,
            executable: executable,
            thinking: thinking,
            model: model,
            context1m: context1m,
            workingDirectory: workingDirectory
        ).terminalShellCommand
    }

    public var shellCommand: String {
        ([executable] + arguments).map(KWWKShellCommand.quote).joined(separator: " ")
    }

    public var terminalShellCommand: String {
        guard let workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty
        else {
            return shellCommand
        }

        return "cd \(KWWKShellCommand.quote(workingDirectory)) && \(shellCommand)"
    }
}

public enum KWWKShellCommand {
    public static func quote(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-=/:.,")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func terminalCommand(_ command: String, workingDirectory: String?) -> String {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workingDirectory.isEmpty
        else {
            return trimmedCommand
        }

        return "cd \(quote(workingDirectory)) && \(trimmedCommand)"
    }
}

public struct KWWKCLIRunResult: Sendable, Equatable {
    public var invocation: KWWKCLIInvocation
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(invocation: KWWKCLIInvocation, exitCode: Int32, stdout: String, stderr: String) {
        self.invocation = invocation
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var succeeded: Bool { exitCode == 0 }
}

public enum KWWKCLIClientError: Error, LocalizedError, Equatable {
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        }
    }
}

public actor ProcessBackedKWWKCLIClient {
    public init() {}

    public func run(
        _ invocation: KWWKCLIInvocation,
        onStdout: (@Sendable (String) -> Void)? = nil,
        onStderr: (@Sendable (String) -> Void)? = nil
    ) async throws -> KWWKCLIRunResult {
        let processBox = RunningProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try Self.runBlocking(
                            invocation,
                            processBox: processBox,
                            onStdout: onStdout,
                            onStderr: onStderr
                        )
                        if processBox.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: result)
                        }
                    } catch {
                        if processBox.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } onCancel: {
            processBox.cancel()
        }
    }

    private static func runBlocking(
        _ invocation: KWWKCLIInvocation,
        processBox: RunningProcessBox,
        onStdout: (@Sendable (String) -> Void)?,
        onStderr: (@Sendable (String) -> Void)?
    ) throws -> KWWKCLIRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [invocation.executable] + invocation.arguments
        if let workingDirectory = invocation.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        }
        if !invocation.environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(invocation.environment) { _, new in new }
        }
        if processBox.attach(process) {
            throw CancellationError()
        }
        defer { processBox.detach(process) }

        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutCapture = PipeCapture()
        let stderrCapture = PipeCapture()
        process.standardOutput = stdout
        process.standardError = stderr

        let stdin = Pipe()
        if invocation.stdin != nil {
            process.standardInput = stdin
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stdoutCapture.append(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                onStdout?(text)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrCapture.append(data)
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                onStderr?(text)
            }
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw KWWKCLIClientError.launchFailed(error.localizedDescription)
        }
        if processBox.isCancelled {
            process.terminate()
        } else if let input = invocation.stdin {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            stdin.fileHandleForWriting.closeFile()
        }

        process.waitUntilExit()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutCapture.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrCapture.append(stderr.fileHandleForReading.readDataToEndOfFile())

        return KWWKCLIRunResult(
            invocation: invocation,
            exitCode: process.terminationStatus,
            stdout: stdoutCapture.text(),
            stderr: stderrCapture.text()
        )
    }
}

private final class PipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock {
            data.append(chunk)
        }
    }

    func text() -> String {
        lock.withLock {
            String(data: data, encoding: .utf8) ?? ""
        }
    }
}

private final class RunningProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock {
            cancelled
        }
    }

    func attach(_ process: Process) -> Bool {
        lock.withLock {
            self.process = process
            return cancelled
        }
    }

    func detach(_ process: Process) {
        lock.withLock {
            if self.process === process {
                self.process = nil
            }
        }
    }

    func cancel() {
        let runningProcess = lock.withLock {
            cancelled = true
            return process
        }
        runningProcess?.terminate()
    }
}
