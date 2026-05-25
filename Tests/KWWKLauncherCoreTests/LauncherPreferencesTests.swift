import KWWKLauncherCore
import Testing

@Suite("Launcher preferences")
struct LauncherPreferencesTests {
    @Test
    func normalizesThinkingFallback() {
        #expect(LauncherPreferences.normalizedThinking("high") == .high)
        #expect(LauncherPreferences.normalizedThinking("bogus") == .medium)
    }

    @Test
    func clampsHistoryLimit() {
        #expect(LauncherPreferences.normalizedHistoryLimit(-10) == LauncherPreferences.minimumHistoryLimit)
        #expect(LauncherPreferences.normalizedHistoryLimit(50) == 50)
        #expect(LauncherPreferences.normalizedHistoryLimit(500) == LauncherPreferences.maximumHistoryLimit)
    }

    @Test
    func clipboardTrackingDefaultsToOptIn() {
        #expect(LauncherPreferences().trackClipboardHistory == false)
        #expect(LauncherPreferences.defaultTrackClipboardHistory == false)
        #expect(LauncherPreferences(trackClipboardHistory: true).trackClipboardHistory)
    }

    @Test
    func globalHotkeyDefaultsAndCanBeDisabled() {
        #expect(LauncherPreferences().globalHotkey == .controlOptionShiftSpace)
        #expect(LauncherPreferences.normalizedGlobalHotkey(nil) == .controlOptionShiftSpace)
        #expect(LauncherPreferences.normalizedGlobalHotkey("bogus") == .controlOptionShiftSpace)
        #expect(LauncherPreferences.normalizedGlobalHotkey("disabled") == .disabled)
        #expect(LauncherPreferences(globalHotkey: .optionSpace).globalHotkey == .optionSpace)
    }

    @Test
    func launchAtLoginDefaultsToOff() {
        #expect(LauncherPreferences().launchAtLogin == false)
        #expect(LauncherPreferences.defaultLaunchAtLogin == false)
        #expect(LauncherPreferences(launchAtLogin: true).launchAtLogin)
    }

    @Test
    func resolvesExecutableByPreferenceThenEnvironmentThenBundleThenPath() {
        let preferred = LauncherPreferences(cliPathOverride: " /custom/kwwk ")
        #expect(preferred.resolvedExecutable(envPath: "/env/kwwk", bundledPath: "/bundle/kwwk", bundledIsExecutable: true) == "/custom/kwwk")

        let env = LauncherPreferences()
        #expect(env.resolvedExecutable(envPath: " /env/kwwk ", bundledPath: "/bundle/kwwk", bundledIsExecutable: true) == "/env/kwwk")
        #expect(env.resolvedExecutable(envPath: nil, bundledPath: "/bundle/kwwk", bundledIsExecutable: true) == "/bundle/kwwk")
        #expect(env.resolvedExecutable(envPath: nil, bundledPath: "/bundle/kwwk", bundledIsExecutable: false) == "kwwk")
    }
}
