#if os(macOS) && canImport(AppKit)
import AppKit
import Foundation

enum DesktopContextProvider {
    static func frontmostApplicationName() -> String? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        if application.bundleIdentifier == "ai.kwwk.launcher" {
            return nil
        }
        return application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func finderSelectionPaths() -> [String] {
        let script = """
        tell application "Finder"
          set output to ""
          repeat with itemRef in selection
            set output to output & POSIX path of (itemRef as alias) & linefeed
          end repeat
          return output
        end tell
        """

        guard let output = runAppleScript(script) else { return [] }
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func runAppleScript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
