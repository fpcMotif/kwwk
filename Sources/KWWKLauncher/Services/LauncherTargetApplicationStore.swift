#if os(macOS) && canImport(AppKit)
import AppKit
import Foundation

enum LauncherTargetApplicationStore {
    private static let processIdentifierKey = "KWWKLauncher.LastTargetProcessIdentifier"
    private static let nameKey = "KWWKLauncher.LastTargetApplicationName"

    static func rememberFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular
        else {
            return
        }

        UserDefaults.standard.set(Int(application.processIdentifier), forKey: processIdentifierKey)
        UserDefaults.standard.set(application.localizedName ?? "", forKey: nameKey)
    }

    static var lastProcessIdentifier: pid_t? {
        let value = UserDefaults.standard.integer(forKey: processIdentifierKey)
        return value > 0 ? pid_t(value) : nil
    }

    static var lastApplicationName: String? {
        let value = UserDefaults.standard.string(forKey: nameKey) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
