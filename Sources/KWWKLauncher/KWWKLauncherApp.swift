#if os(macOS) && canImport(SwiftUI)
import AppKit
import Carbon.HIToolbox
import KWWKLauncherCore
import SwiftUI

@main
struct KWWKLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var menuModel = LauncherMenuModel()

    var body: some Scene {
        WindowGroup("KWWK", id: "launcher") {
            LauncherWindowView()
                .frame(minWidth: 720, idealWidth: 780, maxWidth: 920, minHeight: 480, idealHeight: 540, maxHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 780, height: 540)
        .commands {
            CommandMenu("KWWK") {
                Button("Show Launcher") {
                    NotificationCenter.default.post(name: .showLauncher, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Hide Launcher") {
                    NotificationCenter.default.post(name: .hideLauncher, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command])

                Divider()

                Button("Run Selected") {
                    NotificationCenter.default.post(name: .runSelectedLauncherCommand, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command])

                Button("Select Previous Result") {
                    NotificationCenter.default.post(name: .moveLauncherSelection, object: -1)
                }
                .keyboardShortcut("p", modifiers: [.control])

                Button("Select Next Result") {
                    NotificationCenter.default.post(name: .moveLauncherSelection, object: 1)
                }
                .keyboardShortcut("n", modifiers: [.control])

                Button("Show Actions") {
                    NotificationCenter.default.post(name: .showLauncherActions, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("Toggle Favorite") {
                    NotificationCenter.default.post(name: .toggleLauncherFavorite, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Copy Result") {
                    NotificationCenter.default.post(name: .copyLauncherOutput, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Open Result Draft in CLI") {
                    NotificationCenter.default.post(name: .openLauncherOutputDraft, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Save Result as Snippet") {
                    NotificationCenter.default.post(name: .saveLauncherOutputSnippet, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Capture Clipboard") {
                    NotificationCenter.default.post(name: .captureLauncherClipboard, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])

                Button("Ask Follow-up") {
                    NotificationCenter.default.post(name: .askLauncherFollowUp, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])

                Divider()

                Button("Stop Running Command") {
                    NotificationCenter.default.post(name: .cancelLauncherRun, object: nil)
                }
                .keyboardShortcut(".", modifiers: [.command])

                Button("Refresh Context") {
                    NotificationCenter.default.post(name: .refreshLauncherContext, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Clear Clipboard History") {
                    NotificationCenter.default.post(name: .clearLauncherClipboardHistory, object: nil)
                }

                Button("Reload Script Commands") {
                    NotificationCenter.default.post(name: .reloadLauncherScripts, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Reload Quicklinks") {
                    NotificationCenter.default.post(name: .reloadLauncherQuicklinks, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Reload AI Prompt Commands") {
                    NotificationCenter.default.post(name: .reloadLauncherPromptCommands, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .control])

                Button("Reload Workflows") {
                    NotificationCenter.default.post(name: .reloadLauncherWorkflows, object: nil)
                }

                Button("Reload AI History") {
                    NotificationCenter.default.post(name: .reloadLauncherAIHistory, object: nil)
                }

                Button("Reload Terminal Contexts") {
                    NotificationCenter.default.post(name: .reloadLauncherCLIContexts, object: nil)
                }

                Button("Clear Terminal Contexts") {
                    NotificationCenter.default.post(name: .clearLauncherCLIContexts, object: nil)
                }

                Button("Reload AI Profiles") {
                    NotificationCenter.default.post(name: .reloadLauncherAIProfiles, object: nil)
                }

                Button("Reload Command Aliases") {
                    NotificationCenter.default.post(name: .reloadLauncherCommandAliases, object: nil)
                }

                Button("Reload Snippets") {
                    NotificationCenter.default.post(name: .reloadLauncherSnippets, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .option, .control])
            }
        }

        Settings {
            SettingsView()
        }

        MenuBarExtra("KWWK", systemImage: "sparkles") {
            LauncherMenuBarContent(menuModel: menuModel)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct LauncherMenuBarContent: View {
    @ObservedObject var menuModel: LauncherMenuModel

    var body: some View {
        Group {
            Button {
                NotificationCenter.default.post(name: .showLauncher, object: nil)
            } label: {
                Label("Show Launcher", systemImage: "command")
            }
            .keyboardShortcut(" ", modifiers: [.control, .option, .shift])

            if !menuModel.favorites.isEmpty {
                Menu("Favorites") {
                    ForEach(menuModel.favorites) { item in
                        LauncherMenuCommandButton(item: item)
                    }
                }
            }

            if !menuModel.recents.isEmpty {
                Menu("Recent") {
                    ForEach(menuModel.recents) { item in
                        LauncherMenuCommandButton(item: item)
                    }
                }
            }

            if !menuModel.terminalContexts.isEmpty {
                Menu("Terminal Contexts") {
                    ForEach(menuModel.terminalContexts) { item in
                        LauncherMenuCommandButton(item: item)
                    }
                }
            }

            Divider()

            Button {
                menuModel.reload()
            } label: {
                Label("Reload Menu", systemImage: "arrow.clockwise")
            }

            Button {
                LauncherMenuActions.showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit KWWK", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .onAppear {
            menuModel.reload()
        }
    }
}

private struct LauncherMenuCommandButton: View {
    var item: LauncherMenuCommand

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .showLauncher, object: nil)
            NotificationCenter.default.post(name: .runLauncherCommandById, object: item.id)
        } label: {
            Label(item.displayTitle(), systemImage: item.systemImage)
        }
    }
}

private enum LauncherMenuActions {
    @MainActor
    static func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkey = GlobalHotkeyController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showLauncher),
            name: .showLauncher,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hideLauncher),
            name: .hideLauncher,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleLauncher),
            name: .toggleLauncher,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadGlobalHotkey),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        hotkey.reloadFromPreferences()
        LauncherLoginItemController.applyStoredPreference()
    }

    @objc func showLauncher() {
        LauncherTargetApplicationStore.rememberFrontmostApplication()
        NSApp.activate(ignoringOtherApps: true)
        if let window = launcherWindow {
            window.makeKeyAndOrderFront(nil)
            if !window.isVisible { window.center() }
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .focusLauncherInput, object: nil)
    }

    @objc func hideLauncher() {
        launcherWindow?.orderOut(nil)
    }

    @objc func toggleLauncher() {
        guard let window = launcherWindow, window.isVisible else {
            showLauncher()
            return
        }
        window.orderOut(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLauncher()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func reloadGlobalHotkey() {
        hotkey.reloadFromPreferences()
    }

    private var launcherWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "KWWKLauncherWindow" }
    }
}

final class GlobalHotkeyController {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var currentHotkey: LauncherGlobalHotkey?

    func reloadFromPreferences() {
        register(LauncherPreferences.normalizedGlobalHotkey(
            UserDefaults.standard.string(forKey: LauncherPreferenceKeys.globalHotkey)
        ))
    }

    private func register(_ hotkey: LauncherGlobalHotkey) {
        guard currentHotkey != hotkey else { return }
        unregisterHotkey()
        currentHotkey = hotkey
        guard hotkey != .disabled else { return }
        installEventHandlerIfNeeded()

        guard let keyCode = hotkey.carbonKeyCode,
              let modifiers = hotkey.carbonModifiers
        else { return }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("KWWK"), id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .toggleLauncher, object: nil)
            }
            return noErr
        }
        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    deinit {
        unregisterHotkey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

private extension LauncherGlobalHotkey {
    var carbonKeyCode: UInt32? {
        switch self {
        case .disabled:
            return nil
        case .controlOptionShiftSpace, .controlOptionSpace, .controlShiftSpace, .optionSpace:
            return UInt32(kVK_Space)
        }
    }

    var carbonModifiers: UInt32? {
        switch self {
        case .disabled:
            return nil
        case .controlOptionShiftSpace:
            return UInt32(controlKey | optionKey | shiftKey)
        case .controlOptionSpace:
            return UInt32(controlKey | optionKey)
        case .controlShiftSpace:
            return UInt32(controlKey | shiftKey)
        case .optionSpace:
            return UInt32(optionKey)
        }
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.prefix(4).reduce(0) { code, byte in
        (code << 8) + OSType(byte)
    }
}

extension Notification.Name {
    static let askLauncherFollowUp = Notification.Name("KWWKLauncherAskFollowUp")
    static let cancelLauncherRun = Notification.Name("KWWKLauncherCancelRun")
    static let captureLauncherClipboard = Notification.Name("KWWKLauncherCaptureClipboard")
    static let clearLauncherClipboardHistory = Notification.Name("KWWKLauncherClearClipboardHistory")
    static let clearLauncherCLIContexts = Notification.Name("KWWKLauncherClearCLIContexts")
    static let copyLauncherOutput = Notification.Name("KWWKLauncherCopyOutput")
    static let focusLauncherInput = Notification.Name("KWWKLauncherFocusInput")
    static let hideLauncher = Notification.Name("KWWKLauncherHide")
    static let moveLauncherSelection = Notification.Name("KWWKLauncherMoveSelection")
    static let openLauncherOutputDraft = Notification.Name("KWWKLauncherOpenOutputDraft")
    static let refreshLauncherContext = Notification.Name("KWWKLauncherRefreshContext")
    static let reloadLauncherAIHistory = Notification.Name("KWWKLauncherReloadAIHistory")
    static let reloadLauncherAIProfiles = Notification.Name("KWWKLauncherReloadAIProfiles")
    static let reloadLauncherCLIContexts = Notification.Name("KWWKLauncherReloadCLIContexts")
    static let reloadLauncherCommandAliases = Notification.Name("KWWKLauncherReloadCommandAliases")
    static let reloadLauncherPromptCommands = Notification.Name("KWWKLauncherReloadPromptCommands")
    static let reloadLauncherQuicklinks = Notification.Name("KWWKLauncherReloadQuicklinks")
    static let reloadLauncherScripts = Notification.Name("KWWKLauncherReloadScripts")
    static let reloadLauncherSnippets = Notification.Name("KWWKLauncherReloadSnippets")
    static let reloadLauncherWorkflows = Notification.Name("KWWKLauncherReloadWorkflows")
    static let runLauncherCommandById = Notification.Name("KWWKLauncherRunCommandById")
    static let saveLauncherOutputSnippet = Notification.Name("KWWKLauncherSaveOutputSnippet")
    static let runSelectedLauncherCommand = Notification.Name("KWWKLauncherRunSelectedCommand")
    static let showLauncher = Notification.Name("KWWKLauncherShow")
    static let showLauncherActions = Notification.Name("KWWKLauncherShowActions")
    static let toggleLauncher = Notification.Name("KWWKLauncherToggle")
    static let toggleLauncherFavorite = Notification.Name("KWWKLauncherToggleFavorite")
}
#else
@main
struct KWWKLauncherApp {
    static func main() {
        print("KWWKLauncher requires macOS.")
    }
}
#endif
