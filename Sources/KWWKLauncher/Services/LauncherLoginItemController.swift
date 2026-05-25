#if os(macOS) && canImport(ServiceManagement)
import Foundation
import KWWKLauncherCore
import os
import ServiceManagement

@MainActor
enum LauncherLoginItemController {
    private static let logger = Logger(subsystem: "com.kwwk.launcher", category: "LoginItem")

    static func applyStoredPreference() {
        do {
            guard let enabled = UserDefaults.standard.object(forKey: LauncherPreferenceKeys.launchAtLogin) as? Bool else {
                return
            }
            try apply(enabled: enabled)
        } catch {
            logger.error("Failed to apply launch-at-login preference: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func apply(enabled: Bool) throws {
        let service = SMAppService.mainApp

        if enabled {
            switch service.status {
            case .enabled, .requiresApproval:
                return
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } else {
            switch service.status {
            case .notRegistered, .notFound:
                return
            case .enabled, .requiresApproval:
                try service.unregister()
            @unknown default:
                try service.unregister()
            }
        }
    }

    static func statusDescription(preferredEnabled: Bool) -> String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Needs approval in System Settings"
        case .notRegistered:
            return preferredEnabled ? "Not registered" : "Off"
        case .notFound:
            return "Unavailable for this app bundle"
        @unknown default:
            return "Unknown"
        }
    }
}
#endif
