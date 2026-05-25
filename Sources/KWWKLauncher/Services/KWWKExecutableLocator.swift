#if os(macOS) && canImport(SwiftUI)
import Foundation
import KWWKLauncherCore

enum KWWKExecutableLocator {
    static func resolve(preferences: LauncherPreferences) -> String {
        let bundled = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("kwwk")
            .path
        return preferences.resolvedExecutable(
            envPath: ProcessInfo.processInfo.environment["KWWK_CLI_PATH"],
            bundledPath: bundled,
            bundledIsExecutable: bundled.map(FileManager.default.isExecutableFile(atPath:)) ?? false
        )
    }
}
#endif
