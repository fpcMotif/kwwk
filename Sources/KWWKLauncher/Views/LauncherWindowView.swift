#if os(macOS) && canImport(SwiftUI)
import KWWKLauncherCore
import SwiftUI

struct LauncherWindowView: View {
    @StateObject private var viewModel = LauncherViewModel()
    @FocusState private var inputFocused: Bool

    var body: some View {
        content
            .background(.regularMaterial)
            .background(WindowConfigurator())
            .onExitCommand {
                NSApp.keyWindow?.orderOut(nil)
            }
            .onAppear {
                appear()
            }
            .onChange(of: viewModel.query) {
                viewModel.queryDidChange()
            }
            .onChange(of: viewModel.modelOverride) {
                viewModel.persistPromptDefaults()
            }
            .onChange(of: viewModel.thinking) {
                viewModel.persistPromptDefaults()
            }
            .onChange(of: viewModel.context1m) {
                viewModel.persistPromptDefaults()
            }
            .modifier(LauncherNotificationHandlers(viewModel: viewModel, inputFocused: $inputFocused))
            .sheet(isPresented: $viewModel.isActionPanelPresented) {
                ActionPanelView(viewModel: viewModel)
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            searchBar
            scopeStrip

            Divider()

            NavigationSplitView {
                CommandListView(viewModel: viewModel)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 380)
            } detail: {
                ResponsePane(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationSplitViewStyle(.balanced)

            Divider()
            controlStrip
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)

            TextField("Ask or run a command", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .medium))
                .focused($inputFocused)
                .accessibilityIdentifier("launcher.searchField")
                .onSubmit {
                    viewModel.runPrimaryAction()
                }

            if viewModel.status.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button {
                    viewModel.cancelRunningCommand()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(".", modifiers: [.command])
                .accessibilityLabel("Stop")
                .accessibilityIdentifier("launcher.stopButton")
                .help("Stop")
            } else {
                Button {
                    viewModel.runPrimaryAction()
                } label: {
                    Image(systemName: "return")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Run")
                .accessibilityIdentifier("launcher.runButton")
                .help("Run")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var scopeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ScopeShortcutButton(
                    title: "All",
                    systemImage: "line.3.horizontal.decrease.circle",
                    isSelected: viewModel.activeScopeShortcutId == nil
                ) {
                    viewModel.applyScopeShortcut(nil)
                    inputFocused = true
                }

                ForEach(viewModel.scopeShortcuts, id: \.id) { scope in
                    ScopeShortcutButton(
                        title: scope.shortTitle,
                        systemImage: scope.systemImage,
                        isSelected: viewModel.activeScopeShortcutId == scope.id
                    ) {
                        viewModel.applyScopeShortcut(scope)
                        inputFocused = true
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
        .background(.bar)
        .accessibilityIdentifier("launcher.scopeStrip")
    }

    private var controlStrip: some View {
        HStack(spacing: 10) {
            Picker("", selection: $viewModel.thinking) {
                ForEach(KWWKThinkingLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .labelsHidden()
            .frame(width: 132)
            .accessibilityLabel("Thinking")
            .accessibilityIdentifier("launcher.thinkingPicker")

            TextField("model", text: $viewModel.modelOverride)
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
                .accessibilityLabel("Default model")
                .accessibilityIdentifier("launcher.modelField")

            Toggle("1M", isOn: $viewModel.context1m)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Use Anthropic 1M context")
                .accessibilityIdentifier("launcher.context1mToggle")

            Spacer()

            Text(viewModel.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func appear() {
        inputFocused = true
        viewModel.refreshDesktopContext()
        viewModel.refreshWorkspaceFiles()
        viewModel.refreshScripts()
        viewModel.refreshAIHistory()
        viewModel.refreshPromptCommands()
        viewModel.refreshWorkflows()
        viewModel.refreshAIProfiles()
        viewModel.refreshQuicklinks()
        viewModel.refreshSnippets()
        viewModel.refreshClipboardHistory()
        viewModel.refreshCommandAliases()
        viewModel.startClipboardMonitoring()
        viewModel.refreshApplications()
        viewModel.normalizeSelection()
    }
}

private struct ScopeShortcutButton: View {
    var title: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(isSelected ? .accentColor : nil)
        .accessibilityLabel(title)
        .accessibilityIdentifier("launcher.scope.\(title.lowercased())")
        .help(title)
    }
}

private struct LauncherNotificationHandlers: ViewModifier {
    @ObservedObject var viewModel: LauncherViewModel
    var inputFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .modifier(LauncherFocusNotificationHandlers(viewModel: viewModel, inputFocused: inputFocused))
            .modifier(LauncherCommandNotificationHandlers(viewModel: viewModel))
            .modifier(LauncherReloadNotificationHandlers(viewModel: viewModel, inputFocused: inputFocused))
    }
}

private struct LauncherFocusNotificationHandlers: ViewModifier {
    @ObservedObject var viewModel: LauncherViewModel
    var inputFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .focusLauncherInput)) { _ in
                inputFocused.wrappedValue = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .showLauncher)) { _ in
                viewModel.refreshDesktopContext()
                viewModel.refreshWorkspaceFiles()
                viewModel.refreshAIHistory()
                viewModel.refreshPromptCommands()
                viewModel.refreshWorkflows()
                viewModel.refreshAIProfiles()
                viewModel.refreshQuicklinks()
                viewModel.refreshSnippets()
                viewModel.refreshClipboardHistory()
                viewModel.refreshCommandAliases()
                inputFocused.wrappedValue = true
            }
    }
}

private struct LauncherCommandNotificationHandlers: ViewModifier {
    @ObservedObject var viewModel: LauncherViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .runSelectedLauncherCommand)) { _ in
                viewModel.runSelectedCommand()
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveLauncherSelection)) { notification in
                viewModel.moveFocusedSelection(notification.object as? Int ?? 0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .showLauncherActions)) { _ in
                viewModel.showActionPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleLauncherFavorite)) { _ in
                viewModel.toggleSelectedFavorite()
            }
            .onReceive(NotificationCenter.default.publisher(for: .copyLauncherOutput)) { _ in
                viewModel.copyOutput()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLauncherOutputDraft)) { _ in
                viewModel.openOutputDraftInCLI()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveLauncherOutputSnippet)) { _ in
                viewModel.saveOutputAsSnippet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .captureLauncherClipboard)) { _ in
                viewModel.captureCurrentClipboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearLauncherClipboardHistory)) { _ in
                viewModel.clearClipboardHistory()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearLauncherCLIContexts)) { _ in
                viewModel.clearCLIContexts()
            }
            .onReceive(NotificationCenter.default.publisher(for: .askLauncherFollowUp)) { _ in
                viewModel.askFollowUp()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cancelLauncherRun)) { _ in
                viewModel.cancelRunningCommand()
            }
    }
}

private struct LauncherReloadNotificationHandlers: ViewModifier {
    @ObservedObject var viewModel: LauncherViewModel
    var inputFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .refreshLauncherContext)) { _ in
                viewModel.refreshDesktopContext()
                viewModel.refreshWorkspaceFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherScripts)) { _ in
                viewModel.reloadScriptCommands()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherQuicklinks)) { _ in
                viewModel.reloadQuicklinks()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherPromptCommands)) { _ in
                viewModel.reloadPromptCommands()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherWorkflows)) { _ in
                viewModel.reloadWorkflows()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherAIHistory)) { _ in
                viewModel.reloadAIHistory()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherCLIContexts)) { _ in
                viewModel.reloadCLIContexts()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherAIProfiles)) { _ in
                viewModel.reloadAIProfiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherCommandAliases)) { _ in
                viewModel.reloadCommandAliases()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reloadLauncherSnippets)) { _ in
                viewModel.reloadSnippets()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .runLauncherCommandById),
                perform: handleRunCommandById
            )
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                viewModel.reloadPreferences()
            }
            .onOpenURL { url in
                handleOpenURL(url)
            }
    }

    private func handleOpenURL(_ url: URL) {
        if let request = LauncherDeepLinkRequest(url: url) {
            switch request.mode {
            case .hide:
                NotificationCenter.default.post(name: .hideLauncher, object: nil)
                return
            case .toggle:
                NotificationCenter.default.post(name: .toggleLauncher, object: nil)
                return
            case .search, .ask:
                break
            }
        }

        NotificationCenter.default.post(name: .showLauncher, object: nil)
        viewModel.handleDeepLink(url)
        inputFocused.wrappedValue = true
    }

    private func handleRunCommandById(_ notification: Notification) {
        guard let commandId = notification.object as? String else { return }
        viewModel.runCommandFromMenu(commandId: commandId)
        inputFocused.wrappedValue = true
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            Self.configure(view.window, coordinator: coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            Self.configure(nsView.window, coordinator: coordinator)
        }
    }

    private static func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("KWWKLauncherWindow")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        coordinator.attach(to: window)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var configuredWindow: NSWindow?

        @MainActor
        func attach(to window: NSWindow) {
            guard configuredWindow !== window else { return }
            if configuredWindow?.delegate === self {
                configuredWindow?.delegate = nil
            }
            configuredWindow = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }
    }
}

#endif
