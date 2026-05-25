#if os(macOS) && canImport(SwiftUI)
import KWWKLauncherCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(LauncherPreferenceKeys.cliPathOverride) private var cliPathOverride = ""
    @AppStorage(LauncherPreferenceKeys.defaultModel) private var defaultModel = ""
    @AppStorage(LauncherPreferenceKeys.defaultThinking) private var defaultThinking = KWWKThinkingLevel.medium.rawValue
    @AppStorage(LauncherPreferenceKeys.context1m) private var context1m = false
    @AppStorage(LauncherPreferenceKeys.aiHistoryLimit) private var aiHistoryLimit = LauncherPreferences.defaultHistoryLimit
    @AppStorage(LauncherPreferenceKeys.trackClipboardHistory) private var trackClipboardHistory = LauncherPreferences.defaultTrackClipboardHistory
    @AppStorage(LauncherPreferenceKeys.globalHotkey) private var globalHotkey = LauncherGlobalHotkey.default.rawValue
    @AppStorage(LauncherPreferenceKeys.launchAtLogin) private var launchAtLogin = LauncherPreferences.defaultLaunchAtLogin
    @State private var launchAtLoginStatus = ""

    var body: some View {
        Form {
            Section("AI") {
                Picker("Thinking", selection: $defaultThinking) {
                    ForEach(KWWKThinkingLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level.rawValue)
                    }
                }

                TextField("Default model", text: $defaultModel)
                    .textFieldStyle(.roundedBorder)

                Toggle("Use Anthropic 1M context", isOn: $context1m)
            }

            Section("CLI") {
                TextField("CLI path override", text: $cliPathOverride)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Launcher") {
                Picker("Global hotkey", selection: $globalHotkey) {
                    ForEach(LauncherGlobalHotkey.allCases, id: \.self) { hotkey in
                        Text(hotkey.displayName).tag(hotkey.rawValue)
                    }
                }

                Toggle("Launch at login", isOn: $launchAtLogin)

                if !launchAtLoginStatus.isEmpty {
                    Text(launchAtLoginStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Clipboard") {
                Toggle("Track clipboard history", isOn: $trackClipboardHistory)
            }

            Section("History") {
                Stepper(
                    "AI history: \(normalizedHistoryLimit)",
                    value: $aiHistoryLimit,
                    in: LauncherPreferences.minimumHistoryLimit...LauncherPreferences.maximumHistoryLimit
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .onChange(of: aiHistoryLimit) {
            aiHistoryLimit = normalizedHistoryLimit
        }
        .onChange(of: launchAtLogin) {
            applyLaunchAtLoginPreference()
        }
        .onAppear {
            refreshLaunchAtLoginStatus()
        }
    }

    private var normalizedHistoryLimit: Int {
        LauncherPreferences.normalizedHistoryLimit(aiHistoryLimit)
    }

    private func applyLaunchAtLoginPreference() {
        do {
            try LauncherLoginItemController.apply(enabled: launchAtLogin)
            refreshLaunchAtLoginStatus()
        } catch {
            launchAtLoginStatus = error.localizedDescription
        }
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = LauncherLoginItemController.statusDescription(preferredEnabled: launchAtLogin)
    }
}
#endif
