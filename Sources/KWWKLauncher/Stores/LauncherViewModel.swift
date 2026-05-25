#if os(macOS) && canImport(SwiftUI)
import AppKit
import ApplicationServices
import Foundation
import KWWKLauncherCore

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedCommandId: LauncherCommand.ID?
    @Published var output = ""
    @Published var status: LauncherStatus = .idle
    @Published var modelOverride: String
    @Published var thinking: KWWKThinkingLevel
    @Published var context1m: Bool
    @Published var trackClipboardHistory: Bool
    @Published private var applicationCommands: [LauncherCommand] = []
    @Published private var aliasCommands: [LauncherCommand] = []
    @Published private var scriptCommands: [LauncherCommand] = []
    @Published private var promptCommands: [LauncherCommand] = []
    @Published private var profileCommands: [LauncherCommand] = []
    @Published private var workflowCommands: [LauncherCommand] = []
    @Published private var cliContextCommands: [LauncherCommand] = []
    @Published private var quicklinkCommands: [LauncherCommand] = []
    @Published private var snippetCommands: [LauncherCommand] = []
    @Published private var clipboardCommands: [LauncherCommand] = []
    @Published private var contextCommands: [LauncherCommand] = []
    @Published private var workspaceCommands: [LauncherCommand] = []
    @Published private var workspaceTaskCommands: [LauncherCommand] = []
    @Published private var workspaceFileCommands: [LauncherCommand] = []
    @Published private var usage: LauncherCommandUsage
    @Published private var aiHistory: AIRunHistory
    @Published private var clipboardHistory: LauncherClipboardHistory
    @Published var isActionPanelPresented = false
    @Published var selectedActionId: LauncherActionItem.ID?
    @Published var actionQuery = ""

    private let aiHistoryDefaultsKey = "KWWKLauncher.AIRunHistory.v1"
    private let baseCommands = LauncherCommandCatalog.defaults
    private let clipboardHistoryLimit = 80
    private let cliClient = ProcessBackedKWWKCLIClient()
    private var executablePath: String
    private var historyLimit: Int
    private var workingDirectory: String?
    private var contextSnapshot = LauncherContextSnapshot()
    private var forcedCommandId: LauncherCommand.ID?
    private var forcedCommandQuery: String?
    private var pendingDeepLinkRunCommandId: LauncherCommand.ID?
    private var pendingDeepLinkActionId: LauncherActionItem.ID?
    private var runningTask: Task<Void, Never>?
    private var activeRunId: UUID?
    private var clipboardPollTimer: Timer?
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount

    init() {
        let preferences = Self.loadPreferences()
        modelOverride = preferences.defaultModel
        thinking = preferences.defaultThinking
        context1m = preferences.context1m
        trackClipboardHistory = preferences.trackClipboardHistory
        executablePath = KWWKExecutableLocator.resolve(preferences: preferences)
        historyLimit = preferences.aiHistoryLimit
        usage = Self.loadUsage(defaultsKey: LauncherCommandUsage.defaultsKey)
        aiHistory = Self.loadAIHistory(defaultsKey: aiHistoryDefaultsKey)
        clipboardHistory = LauncherClipboardHistoryStore.load()
        clipboardCommands = LauncherClipboardHistoryCommandFactory.commands(for: clipboardHistory)
        profileCommands = LauncherAIProfileCatalog.commands(
            for: LauncherAIProfileIndex.load(),
            reservedCommandIds: LauncherAIProfileCatalog.defaultCommandIds
        )
        cliContextCommands = LauncherCLIContextIndex.commands(
            for: LauncherCLIContextIndex.scan()
        )
        rebuildCommandAliases()
    }

    var commands: [LauncherCommand] {
        LauncherShellCommandFactory.commands(for: query)
            + LauncherPathCommandFactory.commands(for: query, workingDirectory: workingDirectory)
            + LauncherCalculatorCommandFactory.commands(for: query)
            + LauncherUnitConversionCommandFactory.commands(for: query)
            + LauncherWebCommandFactory.commands(for: query)
            + LauncherDynamicCommandFactory.commands(for: query)
            + LauncherRecentCommandFactory.commands(from: runnableCommands, usage: usage)
            + runnableCommands
    }

    private var runnableCommands: [LauncherCommand] {
        baseCommands
            + AIRunHistoryCommandFactory.commands(for: aiHistory)
            + aliasCommands
            + clipboardCommands
            + profileCommands
            + promptCommands
            + workflowCommands
            + cliContextCommands
            + contextCommands
            + workspaceCommands
            + workspaceTaskCommands
            + workspaceFileCommands
            + quicklinkCommands
            + snippetCommands
            + scriptCommands
            + applicationCommands
    }

    private var aliasTargetCommands: [LauncherCommand] {
        baseCommands
            + AIRunHistoryCommandFactory.commands(for: aiHistory)
            + clipboardCommands
            + profileCommands
            + promptCommands
            + workflowCommands
            + cliContextCommands
            + contextCommands
            + workspaceCommands
            + workspaceTaskCommands
            + workspaceFileCommands
            + quicklinkCommands
            + snippetCommands
            + scriptCommands
            + applicationCommands
    }

    var filteredCommands: [LauncherCommand] {
        LauncherCommandSectionFactory.visibleCommands(from: filteredCommandMatches)
    }

    var filteredCommandSections: [LauncherCommandSection] {
        LauncherCommandSectionFactory.sections(from: filteredCommandMatches)
    }

    private var filteredCommandMatches: [LauncherCommand] {
        let filtered = LauncherCommandFilter.filter(commands, query: query, usage: usage)
        guard let forcedCommand else { return filtered }
        if filtered.contains(where: { $0.id == forcedCommand.id }) {
            return filtered
        }
        return [forcedCommand] + filtered
    }

    var scopeShortcuts: [LauncherScopeCommand] {
        LauncherScopeCommandCatalog.shortcuts()
    }

    var activeScopeShortcutId: String? {
        LauncherScopeCommandCatalog.activeShortcutId(for: query)
    }

    var selectedCommand: LauncherCommand? {
        let filtered = filteredCommands
        if let selectedCommandId, let match = filtered.first(where: { $0.id == selectedCommandId }) {
            return match
        }
        return filtered.first
    }

    var primaryPrompt: String {
        LauncherCommandFilter.promptText(from: query)
    }

    var canRunPrompt: Bool {
        !primaryPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedCommandIsFavorite: Bool {
        selectedCommand.map { usage.isFavorite(usageCommandId(for: $0)) } ?? false
    }

    var selectedCommandPrimaryActionTitle: String {
        selectedCommand.map(LauncherActionCatalog.primaryTitle(for:)) ?? "Run"
    }

    var selectedCommandPreview: String {
        guard let selectedCommand else { return "" }
        return LauncherCommandPreview.text(
            for: selectedCommand,
            query: query,
            clipboard: clipboardText(),
            context: contextSnapshot,
            workingDirectory: workingDirectory,
            availableCommands: runnableCommands,
            targetApplicationName: LauncherTargetApplicationStore.lastApplicationName
        )
    }

    var canCancelRun: Bool {
        runningTask != nil && status.isRunning
    }

    var canCopyOutput: Bool {
        !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canAskFollowUp: Bool {
        canCopyOutput && canRunPrompt && !status.isRunning
    }

    var canOpenOutputDraft: Bool {
        canCopyOutput && !status.isRunning
    }

    var canSaveOutputAsSnippet: Bool {
        canCopyOutput && !status.isRunning
    }

    var selectedCommandActions: [LauncherActionItem] {
        guard let selectedCommand else { return [] }
        return LauncherActionFilter.filter(
            selectedCommandActions(for: selectedCommand),
            query: actionQuery
        )
    }

    var selectedCommandFeaturedActions: [LauncherActionItem] {
        guard let selectedCommand else { return [] }
        return LauncherActionCatalog.featuredActions(
            from: selectedCommandActions(for: selectedCommand)
        )
    }

    var selectedAction: LauncherActionItem? {
        let actions = selectedCommandActions
        if let selectedActionId, let match = actions.first(where: { $0.id == selectedActionId }) {
            return match
        }
        return actions.first
    }

    func normalizeSelection() {
        if let forcedCommandId, command(withId: forcedCommandId) != nil {
            selectedCommandId = forcedCommandId
            return
        }

        let filtered = filteredCommands
        guard !filtered.isEmpty else {
            selectedCommandId = nil
            return
        }
        if let selectedCommandId, filtered.contains(where: { $0.id == selectedCommandId }) {
            return
        }
        selectedCommandId = filtered[0].id
    }

    func queryDidChange() {
        if forcedCommandId != nil, query != forcedCommandQuery {
            forcedCommandId = nil
            forcedCommandQuery = nil
            pendingDeepLinkRunCommandId = nil
            pendingDeepLinkActionId = nil
        }
        normalizeSelection()
        normalizeActionSelection()
    }

    func moveSelection(_ delta: Int) {
        let filtered = filteredCommands
        guard !filtered.isEmpty else { return }
        let current = selectedCommand.flatMap { selected in filtered.firstIndex(of: selected) } ?? 0
        let next = min(max(current + delta, 0), filtered.count - 1)
        selectedCommandId = filtered[next].id
    }

    func normalizeActionSelection() {
        let actions = selectedCommandActions
        guard !actions.isEmpty else {
            selectedActionId = nil
            return
        }
        if let selectedActionId, actions.contains(where: { $0.id == selectedActionId }) {
            return
        }
        selectedActionId = actions[0].id
    }

    func moveActionSelection(_ delta: Int) {
        let actions = selectedCommandActions
        guard !actions.isEmpty else { return }
        let current = selectedAction.flatMap { selected in actions.firstIndex(of: selected) } ?? 0
        let next = min(max(current + delta, 0), actions.count - 1)
        selectedActionId = actions[next].id
    }

    func moveFocusedSelection(_ delta: Int) {
        if isActionPanelPresented {
            moveActionSelection(delta)
        } else {
            moveSelection(delta)
        }
    }

    func actionQueryDidChange() {
        normalizeActionSelection()
    }

    func refreshApplications() {
        Task.detached(priority: .utility) {
            let applications = ApplicationIndex.scan(roots: ApplicationIndex.defaultRoots())
            let commands = ApplicationIndex.commands(for: applications)
            await MainActor.run {
                self.applicationCommands = commands
                self.rebuildCommandAliases()
                self.normalizeSelection()
                self.runPendingDeepLinkCommandIfAvailable()
            }
        }
    }

    func refreshScripts() {
        Task.detached(priority: .utility) {
            let scripts = LauncherScriptCommandIndex.scan(roots: LauncherScriptCommandIndex.defaultRoots())
            let commands = LauncherScriptCommandIndex.commands(for: scripts)
            await MainActor.run {
                self.scriptCommands = commands
                self.rebuildCommandAliases()
                self.normalizeSelection()
                self.runPendingDeepLinkCommandIfAvailable()
            }
        }
    }

    func reloadScriptCommands() {
        refreshScripts()
        status = .succeeded("Reloaded")
        output = LauncherScriptCommandIndex.defaultRoots()[0].path
    }

    func refreshQuicklinks() {
        Task.detached(priority: .utility) {
            let quicklinks = LauncherQuicklinkIndex.load()
            let commands = LauncherQuicklinkIndex.commands(for: quicklinks)
            await MainActor.run {
                self.quicklinkCommands = commands
                self.rebuildCommandAliases()
                self.normalizeSelection()
                self.normalizeActionSelection()
                self.runPendingDeepLinkCommandIfAvailable()
            }
        }
    }

    func reloadQuicklinks() {
        refreshQuicklinks()
        status = .succeeded("Reloaded")
        output = LauncherQuicklinkIndex.defaultURL().path
    }

    func refreshPromptCommands() {
        Task.detached(priority: .utility) {
            let promptCommands = LauncherPromptCommandIndex.load()
            let commands = LauncherPromptCommandIndex.commands(for: promptCommands)
            await MainActor.run {
                self.promptCommands = commands
                self.rebuildCommandAliases()
                self.normalizeSelection()
                self.normalizeActionSelection()
                self.runPendingDeepLinkCommandIfAvailable()
            }
        }
    }

    func reloadPromptCommands() {
        refreshPromptCommands()
        status = .succeeded("Reloaded")
        output = LauncherPromptCommandIndex.defaultURL().path
    }

    func refreshWorkflows() {
        Task.detached(priority: .utility) {
            let workflows = LauncherWorkflowIndex.load()
            let commands = LauncherWorkflowIndex.commands(for: workflows)
            await MainActor.run {
                self.workflowCommands = commands
                self.rebuildCommandAliases()
                self.normalizeSelection()
                self.normalizeActionSelection()
                self.runPendingDeepLinkCommandIfAvailable()
            }
        }
    }

    func reloadWorkflows() {
        refreshWorkflows()
        status = .succeeded("Reloaded")
        output = LauncherWorkflowIndex.defaultURL().path
    }

    func refreshAIHistory() {
        aiHistory = AIRunHistoryStore.load()
        rebuildCommandAliases()
        normalizeSelection()
        normalizeActionSelection()
        runPendingDeepLinkCommandIfAvailable()
    }

    func reloadAIHistory() {
        refreshAIHistory()
        status = .succeeded("Reloaded")
        output = AIRunHistoryStore.defaultURL().path
    }

    func refreshAIProfiles() {
        profileCommands = LauncherAIProfileCatalog.commands(
            for: LauncherAIProfileIndex.load(),
            reservedCommandIds: LauncherAIProfileCatalog.defaultCommandIds
        )
        rebuildCommandAliases()
        normalizeSelection()
        normalizeActionSelection()
        runPendingDeepLinkCommandIfAvailable()
    }

    func reloadAIProfiles() {
        refreshAIProfiles()
        status = .succeeded("Reloaded")
        output = LauncherAIProfileIndex.defaultURL().path
    }

    func refreshCLIContexts() {
        cliContextCommands = LauncherCLIContextIndex.commands(
            for: LauncherCLIContextIndex.scan()
        )
        rebuildCommandAliases()
        normalizeSelection()
        normalizeActionSelection()
        runPendingDeepLinkCommandIfAvailable()
    }

    func reloadCLIContexts() {
        refreshCLIContexts()
        status = .succeeded("Reloaded")
        output = LauncherCLIContextStore.defaultDirectory().path
    }

    func clearCLIContexts() {
        let records = LauncherCLIContextIndex.scan(limit: Int.max)
        guard !records.isEmpty else {
            status = .succeeded("No Contexts")
            output = LauncherCLIContextStore.defaultDirectory().path
            return
        }

        do {
            for record in records {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: record.path), resultingItemURL: nil)
            }
            refreshCLIContexts()
            status = .succeeded(records.count == 1 ? "Cleared 1 Context" : "Cleared \(records.count) Contexts")
            output = LauncherCLIContextStore.defaultDirectory().path
        } catch {
            status = .failed("Clear failed")
            output = error.localizedDescription
        }
    }

    func refreshSnippets() {
        Task.detached(priority: .utility) {
            let snippets = LauncherSnippetIndex.load()
            let commands = LauncherSnippetIndex.commands(for: snippets)
            await MainActor.run {
                self.snippetCommands = commands
                self.rebuildCommandAliases()
                self.normalizeSelection()
                self.normalizeActionSelection()
                self.runPendingDeepLinkCommandIfAvailable()
            }
        }
    }

    func reloadSnippets() {
        refreshSnippets()
        status = .succeeded("Reloaded")
        output = LauncherSnippetIndex.defaultURL().path
    }

    func refreshCommandAliases() {
        rebuildCommandAliases()
        normalizeSelection()
        normalizeActionSelection()
        runPendingDeepLinkCommandIfAvailable()
    }

    func reloadCommandAliases() {
        refreshCommandAliases()
        status = .succeeded("Reloaded")
        output = LauncherCommandAliasIndex.defaultURL().path
    }

    private func rebuildCommandAliases() {
        aliasCommands = LauncherCommandAliasIndex.commands(
            for: LauncherCommandAliasIndex.load(),
            availableCommands: aliasTargetCommands
        )
    }

    func refreshClipboardHistory() {
        clipboardHistory = LauncherClipboardHistoryStore.load()
        clipboardCommands = LauncherClipboardHistoryCommandFactory.commands(for: clipboardHistory)
        rebuildCommandAliases()
        normalizeSelection()
        normalizeActionSelection()
        runPendingDeepLinkCommandIfAvailable()
    }

    func startClipboardMonitoring() {
        guard trackClipboardHistory else { return }
        guard clipboardPollTimer == nil else { return }
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        captureCurrentClipboard(showStatus: false)
        clipboardPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureClipboardIfChanged()
            }
        }
    }

    func stopClipboardMonitoring() {
        clipboardPollTimer?.invalidate()
        clipboardPollTimer = nil
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
    }

    func refreshDesktopContext() {
        let workingDirectory = workingDirectory
        Task.detached(priority: .utility) {
            let finderSelectionPaths = DesktopContextProvider.finderSelectionPaths()
            await MainActor.run {
                let snapshot = LauncherContextSnapshot(
                    workingDirectory: workingDirectory,
                    finderSelectionPaths: finderSelectionPaths,
                    frontmostApplicationName: DesktopContextProvider.frontmostApplicationName()
                )
                self.contextSnapshot = snapshot
                self.contextCommands = LauncherContextCommandFactory.commands(for: snapshot)
                self.rebuildCommandAliases()
                self.normalizeSelection()
                self.normalizeActionSelection()
            }
        }
    }

    func refreshWorkspaceFiles() {
        guard let context = LauncherWorkspaceContext(path: workingDirectory) else {
            workspaceFileCommands = []
            rebuildCommandAliases()
            normalizeSelection()
            normalizeActionSelection()
            return
        }

        Task.detached(priority: .utility) {
            let files = LauncherWorkspaceFileIndex.scan(
                root: URL(fileURLWithPath: context.path, isDirectory: true)
            )
            let commands = LauncherWorkspaceFileIndex.commands(for: files)

            await MainActor.run {
                guard LauncherWorkspaceContext(path: self.workingDirectory)?.path == context.path else { return }
                self.workspaceFileCommands = commands
                self.rebuildCommandAliases()
                self.normalizeSelection()
                self.normalizeActionSelection()
                self.runPendingDeepLinkCommandIfAvailable()
            }
        }
    }

    func refreshWorkspaceTasks() {
        workspaceTaskCommands = LauncherWorkspaceTaskCommandFactory.commands(for: workingDirectory)
        rebuildCommandAliases()
        normalizeSelection()
        normalizeActionSelection()
    }

    func reloadPreferences() {
        let preferences = Self.loadPreferences()
        modelOverride = preferences.defaultModel
        thinking = preferences.defaultThinking
        context1m = preferences.context1m
        trackClipboardHistory = preferences.trackClipboardHistory
        executablePath = KWWKExecutableLocator.resolve(preferences: preferences)
        historyLimit = preferences.aiHistoryLimit
        if trackClipboardHistory {
            startClipboardMonitoring()
        } else {
            stopClipboardMonitoring()
        }
    }

    func persistPromptDefaults() {
        UserDefaults.standard.set(modelOverride, forKey: LauncherPreferenceKeys.defaultModel)
        UserDefaults.standard.set(thinking.rawValue, forKey: LauncherPreferenceKeys.defaultThinking)
        UserDefaults.standard.set(context1m, forKey: LauncherPreferenceKeys.context1m)
    }

    func cancelRunningCommand() {
        cancelRunningCommand(markStopped: true)
    }

    func copyOutput() {
        let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            status = .failed("No Result")
            return
        }
        copyToPasteboard(value)
        status = .succeeded("Copied Result")
    }

    func askFollowUp() {
        let request = primaryPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            status = .waitingForPrompt
            output = previousOutput
            return
        }
        guard !previousOutput.isEmpty else {
            status = .failed("No Result")
            return
        }

        let prompt = LauncherFollowUpPromptBuilder.prompt(
            request: request,
            previousOutput: previousOutput,
            sourceTitle: selectedCommand?.title
        )
        runPrompt(prompt, usageCommandId: selectedCommand.map(usageCommandId(for:)) ?? "ask-kwwk")
    }

    func openOutputDraftInCLI() {
        guard let prompt = LauncherResultDraftPromptBuilder.prompt(
            output: output,
            sourceTitle: selectedCommand?.title
        ) else {
            status = .failed("No Result")
            return
        }

        openTerminal(invocation: .interactiveDraft(
            prompt: prompt,
            executable: executablePath,
            thinking: thinking,
            model: modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            context1m: context1m,
            workingDirectory: workingDirectory
        ))
    }

    func saveOutputAsSnippet() {
        guard let snippet = LauncherSnippetIndex.snippet(
            fromLauncherOutput: output,
            sourceTitle: selectedCommand?.title,
            sourceId: selectedCommand?.id
        ) else {
            status = .failed("No Result")
            return
        }

        saveSnippet(snippet)
    }

    func handleDeepLink(_ url: URL) {
        guard let request = LauncherDeepLinkRequest(url: url) else {
            status = .failed("Bad launcher URL")
            output = url.absoluteString
            return
        }

        guard request.mode != .hide, request.mode != .toggle else { return }

        workingDirectory = request.workingDirectory
        let resolvedQuery: String
        if request.mode == .ask, !request.pathContexts.isEmpty {
            guard let pathPrompt = LauncherPathAskPromptBuilder.prompt(
                pathArguments: request.pathContexts,
                request: request.query,
                workingDirectory: workingDirectory
            ) else {
                query = request.query
                status = .failed("Path unavailable")
                output = request.pathContexts.joined(separator: "\n")
                return
            }
            resolvedQuery = pathPrompt
        } else {
            resolvedQuery = request.query
        }
        workspaceCommands = LauncherWorkspaceCommandFactory.commands(for: workingDirectory)
        workspaceTaskCommands = LauncherWorkspaceTaskCommandFactory.commands(for: workingDirectory)
        contextSnapshot = LauncherContextSnapshot(workingDirectory: workingDirectory)
        contextCommands = LauncherContextCommandFactory.commands(for: contextSnapshot)
        forcedCommandId = request.commandId
        forcedCommandQuery = request.commandId == nil ? nil : resolvedQuery
        pendingDeepLinkRunCommandId = nil
        pendingDeepLinkActionId = nil
        query = resolvedQuery
        if let actionId = request.actionId {
            selectedActionId = actionId
        }
        if case .search = request.mode,
           let commandId = request.commandId,
           request.runImmediately {
            pendingDeepLinkRunCommandId = commandId
            pendingDeepLinkActionId = request.actionId
        }
        refreshPromptCommands()
        refreshWorkflows()
        refreshAIProfiles()
        refreshCLIContexts()
        refreshQuicklinks()
        refreshSnippets()
        refreshClipboardHistory()
        refreshCommandAliases()
        refreshScripts()
        refreshWorkspaceTasks()
        refreshWorkspaceFiles()
        refreshDesktopContext()
        normalizeSelection()
        normalizeActionSelection()

        switch request.mode {
        case .search:
            output = ""
            status = resolvedQuery.isEmpty ? .idle : .succeeded("Ready")
            if request.commandId != nil, request.runImmediately {
                status = .succeeded("Ready")
                runPendingDeepLinkCommandIfAvailable()
            } else if let actionId = request.actionId, request.runImmediately {
                runDeepLinkAction(actionId)
            } else if let actionId = request.actionId {
                showDeepLinkAction(actionId)
            } else if request.runImmediately {
                runPrimaryAction()
            }
        case .ask:
            selectedCommandId = "ask-kwwk"
            output = ""
            if request.runImmediately {
                runPrompt(resolvedQuery, usageCommandId: "ask-kwwk")
            } else {
                status = resolvedQuery.isEmpty ? .waitingForPrompt : .succeeded("Ready")
            }
        case .hide, .toggle:
            break
        }
    }

    func runCommandFromMenu(commandId: LauncherCommand.ID) {
        forcedCommandId = commandId
        forcedCommandQuery = ""
        pendingDeepLinkRunCommandId = commandId
        pendingDeepLinkActionId = nil
        query = ""
        selectedCommandId = commandId
        refreshPromptCommands()
        refreshWorkflows()
        refreshAIProfiles()
        refreshCLIContexts()
        refreshQuicklinks()
        refreshSnippets()
        refreshClipboardHistory()
        refreshCommandAliases()
        refreshScripts()
        refreshWorkspaceTasks()
        refreshWorkspaceFiles()
        refreshDesktopContext()
        normalizeSelection()
        normalizeActionSelection()
        status = .succeeded("Ready")
        runPendingDeepLinkCommandIfAvailable()
    }

    func isFavorite(_ command: LauncherCommand) -> Bool {
        usage.isFavorite(usageCommandId(for: command))
    }

    func selectedCommandActions(for command: LauncherCommand) -> [LauncherActionItem] {
        LauncherActionCatalog.actions(
            for: command,
            isFavorite: usage.isFavorite(usageCommandId(for: command)),
            query: primaryPrompt,
            clipboard: clipboardText(),
            context: contextSnapshot,
            executable: executablePath,
            thinking: thinking,
            model: modelOverride,
            context1m: context1m,
            workingDirectory: workingDirectory
        )
    }

    func runSelectedCommand() {
        if let command = selectedCommand {
            run(command)
        } else if canRunPrompt {
            runPrompt(primaryPrompt, usageCommandId: "ask-kwwk")
        }
    }

    func toggleSelectedFavorite() {
        guard let command = selectedCommand else { return }
        toggleFavorite(command)
    }

    func toggleFavorite(_ command: LauncherCommand) {
        usage.toggleFavorite(usageCommandId(for: command))
        saveUsage()
        normalizeSelection()
        normalizeActionSelection()
    }

    func applyScopeShortcut(_ scope: LauncherScopeCommand?) {
        query = LauncherScopeCommandCatalog.query(replacingScopeIn: query, with: scope)
        forcedCommandId = nil
        forcedCommandQuery = nil
        pendingDeepLinkRunCommandId = nil
        pendingDeepLinkActionId = nil
        selectedCommandId = nil
        selectedActionId = nil
        status = scope == nil ? .succeeded("All Results") : .succeeded(scope?.shortTitle ?? "Scope")
        output = ""
        normalizeSelection()
        normalizeActionSelection()
    }

    func showActionPanel() {
        guard selectedCommand != nil else { return }
        actionQuery = ""
        normalizeActionSelection()
        isActionPanelPresented = true
    }

    func runSelectedAction() {
        guard let command = selectedCommand, let action = selectedAction else { return }
        run(action, for: command)
    }

    func run(_ action: LauncherActionItem, for command: LauncherCommand) {
        switch action.kind {
        case .runPrimary:
            run(command)
        case .toggleFavorite:
            toggleFavorite(command)
        case .askKWWK(let prompt):
            isActionPanelPresented = false
            runPrompt(prompt, usageCommandId: usageCommandId(for: command))
        case .copyText(let value):
            remember(usageCommandId(for: command))
            copyToPasteboard(value)
            status = .succeeded("Copied")
            output = value
            isActionPanelPresented = false
        case .openTerminalCommand(let shellCommand):
            remember(usageCommandId(for: command))
            openTerminal(shellCommand: shellCommand)
            isActionPanelPresented = false
        case .revealPath(let path):
            remember(usageCommandId(for: command))
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            status = .succeeded("Finder")
            output = path
            isActionPanelPresented = false
        case .trashPath(let path):
            remember(usageCommandId(for: command))
            movePathToTrash(path)
            isActionPanelPresented = false
        case .savePromptCommand(let record):
            remember(usageCommandId(for: command))
            savePromptCommand(from: record)
            isActionPanelPresented = false
        case .savePromptTemplate(let promptCommand):
            remember(usageCommandId(for: command))
            savePromptCommand(promptCommand)
            isActionPanelPresented = false
        case .saveSnippet(let snippet):
            remember(usageCommandId(for: command))
            saveSnippet(snippet)
            isActionPanelPresented = false
        case .saveQuicklink(let quicklink):
            remember(usageCommandId(for: command))
            saveQuicklink(quicklink)
            isActionPanelPresented = false
        case .saveCommandAlias(let alias):
            remember(usageCommandId(for: command))
            saveCommandAlias(alias)
            isActionPanelPresented = false
        case .saveScriptCommand(let draft):
            remember(usageCommandId(for: command))
            saveScriptCommand(draft)
            isActionPanelPresented = false
        case .saveWorkflow(let workflow):
            remember(usageCommandId(for: command))
            saveWorkflow(workflow)
            isActionPanelPresented = false
        }
    }

    func runPrimaryAction() {
        normalizeSelection()
        if let command = selectedCommand {
            run(command)
            return
        }
        if LauncherCommandFilter.looksLikePrompt(query), canRunPrompt {
            runPrompt(primaryPrompt, usageCommandId: "ask-kwwk")
        }
    }

    func run(_ command: LauncherCommand) {
        switch command.action {
        case .askAI:
            guard canRunPrompt else {
                status = .waitingForPrompt
                output = ""
                return
            }
            runPrompt(primaryPrompt, usageCommandId: command.id)
        case .askClipboard:
            let text = NSPasteboard.general.string(forType: .string) ?? ""
            let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                status = .failed("Clipboard is empty")
                output = ""
                return
            }
            runPrompt(prompt, usageCommandId: command.id)
        case .askPrompt(let prompt):
            runPrompt(prompt, usageCommandId: "ask-kwwk")
        case .askContext(let kind):
            guard contextSnapshot.supports(kind) else {
                status = .failed("Context unavailable")
                output = "Refresh the launcher after selecting Finder items or opening it from the CLI."
                return
            }
            let prompt = LauncherContextPromptBuilder.prompt(
                for: kind,
                query: primaryPrompt,
                context: contextSnapshot
            )
            runPrompt(prompt, usageCommandId: command.id)
        case .askCLIContext(let record):
            runPrompt(record.askPrompt, usageCommandId: command.id)
        case .runAIPreset(let preset):
            runAIPreset(preset, usageCommandId: command.id)
        case .runPromptCommand(let promptCommand):
            let prompt = promptCommand.renderedPrompt(
                query: primaryPrompt,
                clipboard: clipboardText(),
                context: contextSnapshot
            )
            guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                status = .waitingForPrompt
                output = "Type input in the launcher query or update the prompt command template."
                return
            }
            runPrompt(prompt, usageCommandId: command.id)
        case .runWorkflow(let workflow):
            remember(command.id)
            runWorkflow(workflow)
        case .applyAIProfile(let profile):
            remember(command.id)
            modelOverride = profile.model
            thinking = profile.thinking
            context1m = profile.context1m
            persistPromptDefaults()
            status = .succeeded("Profile Applied")
            output = [
                profile.title,
                "",
                "Model: \(profile.modelDisplayName)",
                "Thinking: \(profile.thinking.displayName)",
                "1M context: \(profile.context1m ? "enabled" : "disabled")",
            ].joined(separator: "\n")
        case .saveCurrentAIProfile:
            remember(command.id)
            saveCurrentAIProfile()
        case .setDefaultModel(let model):
            remember(command.id)
            modelOverride = model.id
            persistPromptDefaults()
            status = .succeeded("Model Selected")
            output = "\(model.name)\n\nModel ID: \(model.id)\nProvider: \(model.provider)\nAPI: \(model.api)"
        case .clearDefaultModel:
            remember(command.id)
            modelOverride = ""
            persistPromptDefaults()
            status = .succeeded("Provider Default")
            output = "Cleared the launcher model override."
        case .setThinkingLevel(let level):
            remember(command.id)
            thinking = level
            persistPromptDefaults()
            status = .succeeded("Thinking Set")
            output = "Thinking: \(level.displayName)\n\n--thinking \(level.rawValue)"
        case .setSearchQuery(let searchQuery):
            remember(command.id)
            query = searchQuery
            forcedCommandId = nil
            forcedCommandQuery = nil
            pendingDeepLinkRunCommandId = nil
            pendingDeepLinkActionId = nil
            selectedCommandId = nil
            selectedActionId = nil
            status = .succeeded("Scope Applied")
            output = ""
            normalizeSelection()
            normalizeActionSelection()
        case .enableContext1M:
            remember(command.id)
            context1m = true
            persistPromptDefaults()
            status = .succeeded("1M Context")
            output = "Enabled --context-1m for launcher AI runs."
        case .disableContext1M:
            remember(command.id)
            context1m = false
            persistPromptDefaults()
            status = .succeeded("Normal Context")
            output = "Disabled --context-1m for launcher AI runs."
        case .captureClipboard:
            remember(command.id)
            captureCurrentClipboard()
        case .clearClipboardHistory:
            remember(command.id)
            clearClipboardHistory()
        case .copyClipboardHistory(let record):
            remember(command.id)
            copyToPasteboard(record.text)
            status = .succeeded("Copied Clipboard")
            output = record.text
        case .copyCalculatorResult(let result):
            remember(command.id)
            copyToPasteboard(result.formattedValue)
            status = .succeeded("Copied Result")
            output = result.displayText
        case .copyUnitConversionResult(let result):
            remember(command.id)
            copyToPasteboard(result.formattedOutput)
            status = .succeeded("Copied Result")
            output = result.displayText
        case .copySnippet(let snippet):
            let text = snippet.renderedText(
                query: primaryPrompt,
                clipboard: clipboardText(),
                context: contextSnapshot
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                status = .failed("Snippet empty")
                output = "Type input in the launcher query or update the snippet template."
                return
            }
            remember(command.id)
            copyToPasteboard(text)
            status = .succeeded("Copied Snippet")
            output = text
        case .rerunPrompt(let prompt):
            query = prompt
            runPrompt(prompt, usageCommandId: command.id)
        case .rerunAIHistory(let record):
            query = record.prompt
            runPrompt(record.prompt, usageCommandId: command.id)
        case .runRecentCommand(let commandId):
            guard let recentCommand = runnableCommand(withId: commandId) else {
                status = .failed("Recent unavailable")
                output = commandId
                return
            }
            run(recentCommand)
        case .runCommandAlias(let alias):
            guard let targetCommand = runnableCommand(withId: alias.targetCommandId) else {
                status = .failed("Alias unavailable")
                output = alias.targetCommandId
                return
            }
            remember(command.id)
            run(targetCommand)
        case .openApplication(let path):
            remember(command.id)
            openApplication(path)
        case .openWorkspaceFile(let file):
            remember(command.id)
            openFile(file.path)
        case .runScript(let script):
            remember(command.id)
            runScript(script)
        case .openQuicklink(let quicklink):
            remember(command.id)
            openQuicklink(quicklink)
        case .openPath(let target):
            remember(command.id)
            openFile(target.path)
        case .openInteractiveCLI:
            remember(command.id)
            openTerminal(invocation: .interactive(executable: executablePath, workingDirectory: workingDirectory))
        case .openInteractiveCLIAt(let path):
            remember(command.id)
            openTerminal(invocation: .interactive(executable: executablePath, workingDirectory: path))
        case .runShellCommand(let commandText):
            remember(command.id)
            openTerminal(shellCommand: KWWKShellCommand.terminalCommand(commandText, workingDirectory: workingDirectory))
        case .runSystemCommand(let systemCommand):
            remember(command.id)
            runSystemCommand(systemCommand)
        case .runWindowCommand(let windowCommand):
            remember(command.id)
            runWindowCommand(windowCommand)
        case .login:
            remember(command.id)
            openTerminal(invocation: .login(executable: executablePath, workingDirectory: workingDirectory))
        case .copyCommand(let shellCommand):
            remember(command.id)
            copyToPasteboard(shellCommand)
            status = .succeeded("Copied")
            output = shellCommand
        case .revealOAuthStore:
            remember(command.id)
            revealOAuthStore()
        case .revealAIHistoryFile:
            remember(command.id)
            revealAIHistoryFile()
        case .reloadAIHistory:
            remember(command.id)
            reloadAIHistory()
        case .revealCLIContextsFolder:
            remember(command.id)
            revealCLIContextsFolder()
        case .reloadCLIContexts:
            remember(command.id)
            reloadCLIContexts()
        case .clearCLIContexts:
            remember(command.id)
            clearCLIContexts()
        case .revealClipboardHistoryFile:
            remember(command.id)
            revealClipboardHistoryFile()
        case .revealWorkspace(let path):
            remember(command.id)
            revealWorkspace(path)
        case .copyWorkspacePath(let path):
            remember(command.id)
            copyToPasteboard(path)
            status = .succeeded("Copied")
            output = path
        case .revealScriptCommandsFolder:
            remember(command.id)
            revealScriptCommandsFolder()
        case .reloadScriptCommands:
            remember(command.id)
            reloadScriptCommands()
        case .revealQuicklinksFile:
            remember(command.id)
            revealQuicklinksFile()
        case .reloadQuicklinks:
            remember(command.id)
            reloadQuicklinks()
        case .revealPromptCommandsFile:
            remember(command.id)
            revealPromptCommandsFile()
        case .reloadPromptCommands:
            remember(command.id)
            reloadPromptCommands()
        case .revealWorkflowsFile:
            remember(command.id)
            revealWorkflowsFile()
        case .reloadWorkflows:
            remember(command.id)
            reloadWorkflows()
        case .revealAIProfilesFile:
            remember(command.id)
            revealAIProfilesFile()
        case .reloadAIProfiles:
            remember(command.id)
            reloadAIProfiles()
        case .revealCommandAliasesFile:
            remember(command.id)
            revealCommandAliasesFile()
        case .reloadCommandAliases:
            remember(command.id)
            reloadCommandAliases()
        case .revealSnippetsFile:
            remember(command.id)
            revealSnippetsFile()
        case .reloadSnippets:
            remember(command.id)
            reloadSnippets()
        }
    }

    private func runAIPreset(_ preset: LauncherAIPreset, usageCommandId: LauncherCommand.ID) {
        let input = input(for: preset)
        guard !input.isEmpty else {
            status = .waitingForPrompt
            output = missingInputMessage(for: preset)
            return
        }
        runPrompt(preset.prompt(input: input), usageCommandId: usageCommandId)
    }

    private func input(for preset: LauncherAIPreset) -> String {
        preset.input(query: primaryPrompt, clipboard: clipboardText())
    }

    private func clipboardText() -> String {
        (NSPasteboard.general.string(forType: .string) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
        guard trackClipboardHistory else { return }
        rememberClipboardText(value)
    }

    private func missingInputMessage(for preset: LauncherAIPreset) -> String {
        switch preset.inputSource {
        case .query:
            return "Type input in the launcher query, then run \(preset.title)."
        case .clipboard:
            return "Copy text first, then run \(preset.title)."
        case .queryOrClipboard:
            return "Type input in the launcher query or copy text first, then run \(preset.title)."
        }
    }

    private func runScript(_ script: LauncherScriptCommand) {
        let invocation = script.invocation(query: primaryPrompt, workingDirectoryOverride: workingDirectory)
        let runId = beginRun(command: invocation.shellCommand)

        runningTask = Task {
            do {
                let result = try await cliClient.run(
                    invocation,
                    onStdout: { [weak self] chunk in
                        Task { @MainActor in
                            guard self?.activeRunId == runId else { return }
                            self?.output += chunk
                        }
                    },
                    onStderr: { [weak self] chunk in
                        Task { @MainActor in
                            guard self?.activeRunId == runId else { return }
                            if self?.output.isEmpty == true {
                                self?.output = chunk
                            } else {
                                self?.output += chunk
                            }
                        }
                    }
                )
                await MainActor.run {
                    guard activeRunId == runId else { return }
                    if output.isEmpty {
                        output = result.stdout.isEmpty ? result.stderr : result.stdout
                    }
                    finishRun(runId)
                    status = result.succeeded ? .succeeded("Done") : .failed("Exited \(result.exitCode)")
                }
            } catch is CancellationError {
                await MainActor.run {
                    stopRun(runId)
                }
            } catch {
                await MainActor.run {
                    guard activeRunId == runId else { return }
                    finishRun(runId)
                    output = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    status = .failed("Launch failed")
                }
            }
        }
    }

    private func runWorkflow(_ workflow: LauncherWorkflow) {
        let workflowQuery = primaryPrompt
        let workflowClipboard = clipboardText()
        let workflowContext = contextSnapshot
        let workflowWorkingDirectory = workingDirectory
        let runId = beginRun(command: "workflow \(workflow.id)")

        runningTask = Task {
            var previousOutput = ""

            do {
                for (index, step) in workflow.steps.enumerated() {
                    let rendered = workflow.renderedTemplate(
                        for: step,
                        query: workflowQuery,
                        clipboard: workflowClipboard,
                        context: workflowContext,
                        previousOutput: previousOutput
                    )
                    let trimmedRendered = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmedRendered.isEmpty else {
                        await MainActor.run {
                            guard activeRunId == runId else { return }
                            finishRun(runId)
                            status = .failed("Workflow step empty")
                            output = "Step \(index + 1), \(step.title), rendered an empty \(step.kind.rawValue) body."
                        }
                        return
                    }

                    let invocation = workflow.invocation(
                        for: step,
                        renderedTemplate: rendered,
                        query: workflowQuery,
                        executable: executablePath,
                        defaultThinking: thinking,
                        defaultModel: modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                        defaultContext1M: context1m,
                        workingDirectory: workflowWorkingDirectory,
                        context: workflowContext,
                        previousOutput: previousOutput
                    )
                    await MainActor.run {
                        guard activeRunId == runId else { return }
                        appendWorkflowStepHeader(index: index, step: step)
                    }

                    let result = try await cliClient.run(
                        invocation,
                        onStdout: { [weak self] chunk in
                            Task { @MainActor in
                                guard self?.activeRunId == runId else { return }
                                self?.output += chunk
                            }
                        },
                        onStderr: { [weak self] chunk in
                            Task { @MainActor in
                                guard self?.activeRunId == runId else { return }
                                self?.output += chunk
                            }
                        }
                    )
                    previousOutput = LauncherWorkflow.stepOutput(result)

                    await MainActor.run {
                        guard activeRunId == runId else { return }
                        if step.kind == .prompt {
                            rememberAIResult(
                                prompt: rendered,
                                invocation: invocation,
                                result: result,
                                model: workflow.resolvedModel(
                                    default: modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                                )
                            )
                        }
                    }

                    guard result.succeeded else {
                        await MainActor.run {
                            guard activeRunId == runId else { return }
                            if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                output = previousOutput
                            }
                            finishRun(runId)
                            status = .failed("Step \(index + 1) exited \(result.exitCode)")
                        }
                        return
                    }

                    await MainActor.run {
                        guard activeRunId == runId else { return }
                        appendWorkflowStepSeparator()
                    }
                }

                await MainActor.run {
                    guard activeRunId == runId else { return }
                    finishRun(runId)
                    status = .succeeded("Workflow Done")
                }
            } catch is CancellationError {
                await MainActor.run {
                    stopRun(runId)
                }
            } catch {
                await MainActor.run {
                    guard activeRunId == runId else { return }
                    finishRun(runId)
                    output = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    status = .failed("Workflow failed")
                }
            }
        }
    }

    private func appendWorkflowStepHeader(index: Int, step: LauncherWorkflowStep) {
        if !output.isEmpty, !output.hasSuffix("\n") {
            output += "\n"
        }
        if !output.isEmpty {
            output += "\n"
        }
        output += "## \(index + 1). \(step.title)\n"
    }

    private func appendWorkflowStepSeparator() {
        guard !output.isEmpty, !output.hasSuffix("\n") else { return }
        output += "\n"
    }

    private func runPrompt(_ prompt: String, usageCommandId: LauncherCommand.ID?) {
        if let usageCommandId {
            remember(usageCommandId)
        }
        let invocation = KWWKCLIInvocation.headless(
            prompt: prompt,
            executable: executablePath,
            thinking: thinking,
            model: modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            context1m: context1m,
            workingDirectory: workingDirectory
        )
        let runId = beginRun(command: invocation.shellCommand)

        runningTask = Task {
            do {
                let result = try await cliClient.run(
                    invocation,
                    onStdout: { [weak self] chunk in
                        Task { @MainActor in
                            guard self?.activeRunId == runId else { return }
                            self?.output += chunk
                        }
                    },
                    onStderr: { [weak self] chunk in
                        Task { @MainActor in
                            guard self?.activeRunId == runId else { return }
                            if self?.output.isEmpty == true {
                                self?.output = chunk
                            } else {
                                self?.output += chunk
                            }
                        }
                    }
                )
                await MainActor.run {
                    guard activeRunId == runId else { return }
                    if output.isEmpty {
                        output = result.stdout.isEmpty ? result.stderr : result.stdout
                    }
                    rememberAIResult(prompt: prompt, invocation: invocation, result: result)
                    finishRun(runId)
                    status = result.succeeded ? .succeeded("Done") : .failed("Exited \(result.exitCode)")
                }
            } catch is CancellationError {
                await MainActor.run {
                    stopRun(runId)
                }
            } catch {
                await MainActor.run {
                    guard activeRunId == runId else { return }
                    finishRun(runId)
                    output = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    status = .failed("Launch failed")
                }
            }
        }
    }

    private func beginRun(command: String) -> UUID {
        cancelRunningCommand(markStopped: false)
        let runId = UUID()
        activeRunId = runId
        status = .running(command)
        output = ""
        return runId
    }

    private func finishRun(_ runId: UUID) {
        guard activeRunId == runId else { return }
        activeRunId = nil
        runningTask = nil
    }

    private func stopRun(_ runId: UUID) {
        guard activeRunId == runId else { return }
        activeRunId = nil
        runningTask = nil
        appendStoppedOutput()
        status = .cancelled
    }

    private func cancelRunningCommand(markStopped: Bool) {
        let hadRunningTask = runningTask != nil
        runningTask?.cancel()
        runningTask = nil
        activeRunId = nil
        guard markStopped, hadRunningTask else { return }
        appendStoppedOutput()
        status = .cancelled
    }

    private func appendStoppedOutput() {
        let message = "Stopped."
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output = message
        } else if output.hasSuffix("\n") {
            output += message
        } else {
            output += "\n\(message)"
        }
    }

    private func remember(_ commandId: LauncherCommand.ID) {
        guard !commandId.isEmpty else { return }
        usage.markUsed(commandId)
        saveUsage()
    }

    private func usageCommandId(for command: LauncherCommand) -> LauncherCommand.ID {
        if case .runRecentCommand(let commandId) = command.action {
            return commandId
        }
        return LauncherRecentCommandFactory.originalCommandId(for: command.id) ?? command.id
    }

    private func runnableCommand(withId commandId: LauncherCommand.ID) -> LauncherCommand? {
        runnableCommands.first { $0.id == commandId }
    }

    private var forcedCommand: LauncherCommand? {
        forcedCommandId.flatMap(command(withId:))
    }

    private func command(withId commandId: LauncherCommand.ID) -> LauncherCommand? {
        commands.first { $0.id == commandId }
    }

    private func runPendingDeepLinkCommandIfAvailable() {
        guard let commandId = pendingDeepLinkRunCommandId,
              let command = command(withId: commandId)
        else {
            return
        }
        let actionId = pendingDeepLinkActionId
        pendingDeepLinkRunCommandId = nil
        pendingDeepLinkActionId = nil
        forcedCommandId = commandId
        selectedCommandId = commandId
        if let actionId {
            runDeepLinkAction(actionId, for: command)
        } else {
            run(command)
        }
    }

    private func runDeepLinkAction(_ actionId: LauncherActionItem.ID) {
        normalizeSelection()
        guard let command = selectedCommand else {
            status = .failed("No Command")
            output = actionId
            return
        }
        runDeepLinkAction(actionId, for: command)
    }

    private func runDeepLinkAction(_ actionId: LauncherActionItem.ID, for command: LauncherCommand) {
        let actions = selectedCommandActions(for: command)
        guard let action = actions.first(where: { $0.id == actionId }) else {
            status = .failed("No Action")
            output = actionId
            return
        }
        selectedCommandId = command.id
        selectedActionId = actionId
        run(action, for: command)
    }

    private func showDeepLinkAction(_ actionId: LauncherActionItem.ID) {
        normalizeSelection()
        guard let command = selectedCommand else {
            status = .failed("No Command")
            output = actionId
            return
        }
        let actions = selectedCommandActions(for: command)
        guard actions.contains(where: { $0.id == actionId }) else {
            status = .failed("No Action")
            output = actionId
            return
        }
        selectedCommandId = command.id
        selectedActionId = actionId
        actionQuery = ""
        isActionPanelPresented = true
        status = .succeeded("Actions")
    }

    private func rememberAIResult(
        prompt: String,
        invocation: KWWKCLIInvocation,
        result: KWWKCLIRunResult,
        model: String? = nil
    ) {
        aiHistory.add(AIRunHistoryRecord(
            prompt: prompt,
            output: result.stdout,
            errorOutput: result.stderr,
            exitCode: result.exitCode,
            model: model ?? modelOverride.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            command: invocation.shellCommand,
            workingDirectory: invocation.workingDirectory
        ), limit: historyLimit)
        saveAIHistory()
    }

    private func openTerminal(invocation: KWWKCLIInvocation) {
        openTerminal(shellCommand: invocation.terminalShellCommand)
    }

    private func openTerminal(shellCommand command: String) {
        let script = """
        tell application "Terminal"
          activate
          do script \(appleScriptString(command))
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            status = .succeeded("Terminal")
            output = command
        } catch {
            status = .failed("Terminal failed")
            output = error.localizedDescription
        }
    }

    private func openApplication(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if NSWorkspace.shared.open(url) {
            status = .succeeded("Opened")
            output = path
            NSApp.keyWindow?.orderOut(nil)
        } else {
            status = .failed("Open failed")
            output = path
        }
    }

    private func openFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if NSWorkspace.shared.open(url) {
            status = .succeeded("Opened")
            output = path
            NSApp.keyWindow?.orderOut(nil)
        } else {
            status = .failed("Open failed")
            output = path
        }
    }

    private func openQuicklink(_ quicklink: LauncherQuicklink) {
        let urlString = quicklink.renderedURLString(query: primaryPrompt)
        guard let url = URL(string: urlString) else {
            status = .failed("Bad URL")
            output = urlString
            return
        }

        if NSWorkspace.shared.open(url) {
            status = .succeeded("Opened")
            output = urlString
            NSApp.keyWindow?.orderOut(nil)
        } else {
            status = .failed("Open failed")
            output = urlString
        }
    }

    private func runSystemCommand(_ command: LauncherSystemCommand) {
        switch command.kind {
        case .lockScreen:
            runSystemProcess(
                command,
                executable: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession",
                arguments: ["-suspend"],
                successMessage: "Locked"
            )
        case .sleepDisplay:
            runSystemProcess(
                command,
                executable: "/usr/bin/pmset",
                arguments: ["displaysleepnow"],
                successMessage: "Display Sleep"
            )
        case .startScreenSaver:
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
            if NSWorkspace.shared.open(url) {
                status = .succeeded("Screen Saver")
                output = url.path
                NSApp.keyWindow?.orderOut(nil)
            } else {
                status = .failed("Open failed")
                output = url.path
            }
        case .openSystemSettings:
            guard let url = URL(string: "x-apple.systempreferences:") else {
                status = .failed("Bad URL")
                output = "x-apple.systempreferences:"
                return
            }
            if NSWorkspace.shared.open(url) {
                status = .succeeded("System Settings")
                output = url.absoluteString
                NSApp.keyWindow?.orderOut(nil)
            } else {
                status = .failed("Open failed")
                output = url.absoluteString
            }
        case .quitAllApplications:
            quitAllApplications()
        }
    }

    private func runWindowCommand(_ command: LauncherWindowCommand) {
        guard AXIsProcessTrusted() else {
            status = .failed("Accessibility Needed")
            output = "Enable Accessibility for KWWKLauncher in System Settings > Privacy & Security > Accessibility."
            return
        }
        guard let window = targetWindowElement() else {
            status = .failed("No Window")
            output = "No target window was available for \(command.title)."
            return
        }
        guard let screen = screenForTargetWindow(window) ?? NSScreen.main else {
            status = .failed("No Screen")
            output = "No screen was available for \(command.title)."
            return
        }

        let frame = targetFrame(for: command.kind, visibleFrame: screen.visibleFrame)
        guard setFrame(frame, for: window) else {
            status = .failed("Move Failed")
            output = "The target app did not allow its window to be resized."
            return
        }

        status = .succeeded("Window Moved")
        output = [
            command.title,
            LauncherTargetApplicationStore.lastApplicationName.map { "Target: \($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
        NSApp.keyWindow?.orderOut(nil)
    }

    private func targetWindowElement() -> AXUIElement? {
        if let pid = LauncherTargetApplicationStore.lastProcessIdentifier,
           let window = firstWindow(forProcessIdentifier: pid) {
            return window
        }

        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private func firstWindow(forProcessIdentifier pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedValue) == .success,
           let focusedValue {
            return (focusedValue as! AXUIElement)
        }

        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return nil
        }
        return windows.first
    }

    private func screenForTargetWindow(_ window: AXUIElement) -> NSScreen? {
        guard let frame = frame(for: window) else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    private func frame(for window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func targetFrame(for kind: LauncherWindowCommandKind, visibleFrame: CGRect) -> CGRect {
        switch kind {
        case .leftHalf:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .rightHalf:
            return CGRect(
                x: visibleFrame.midX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .maximize:
            return visibleFrame
        case .center:
            let width = min(visibleFrame.width * 0.72, 1100)
            let height = min(visibleFrame.height * 0.76, 760)
            return CGRect(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - height / 2,
                width: width,
                height: height
            )
        }
    }

    private func setFrame(_ frame: CGRect, for window: AXUIElement) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            return false
        }

        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return positionResult == .success && sizeResult == .success
    }

    private func runSystemProcess(
        _ command: LauncherSystemCommand,
        executable: String,
        arguments: [String],
        successMessage: String
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                status = .failed("Command failed")
                output = "\(command.title) exited \(process.terminationStatus)"
                return
            }
            status = .succeeded(successMessage)
            output = command.title
            NSApp.keyWindow?.orderOut(nil)
        } catch {
            status = .failed("Command failed")
            output = error.localizedDescription
        }
    }

    private func quitAllApplications() {
        let ownProcessId = ProcessInfo.processInfo.processIdentifier
        var quitCount = 0

        for application in NSWorkspace.shared.runningApplications {
            guard application.activationPolicy == .regular,
                  application.processIdentifier != ownProcessId,
                  application.bundleIdentifier != "com.apple.finder"
            else {
                continue
            }

            if application.terminate() {
                quitCount += 1
            }
        }

        status = .succeeded("Quit Requested")
        output = "Asked \(quitCount) \(quitCount == 1 ? "application" : "applications") to quit."
        NSApp.keyWindow?.orderOut(nil)
    }

    func captureCurrentClipboard(showStatus: Bool = true) {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string) ?? ""
        lastPasteboardChangeCount = pasteboard.changeCount
        guard rememberClipboardText(text) else {
            guard showStatus else { return }
            status = .failed("Clipboard is empty")
            output = ""
            return
        }
        guard showStatus else { return }
        status = .succeeded("Captured Clipboard")
        output = text
    }

    private func captureClipboardIfChanged() {
        guard trackClipboardHistory else { return }
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = changeCount
        rememberClipboardText(pasteboard.string(forType: .string) ?? "")
    }

    func clearClipboardHistory() {
        clipboardHistory.clear()
        guard saveClipboardHistory() else { return }
        status = .succeeded("Cleared")
        output = LauncherClipboardHistoryStore.defaultURL().path
    }

    private func revealOAuthStore() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kwwk")
            .appendingPathComponent("oauth.json")
        NSWorkspace.shared.activateFileViewerSelecting([url])
        status = .succeeded("Finder")
        output = url.path
    }

    private func revealAIHistoryFile() {
        let url = AIRunHistoryStore.defaultURL()
        do {
            try AIRunHistoryStore.save(aiHistory, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("File failed")
            output = error.localizedDescription
        }
    }

    private func revealClipboardHistoryFile() {
        let url = LauncherClipboardHistoryStore.defaultURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try LauncherClipboardHistoryStore.save(clipboardHistory, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("File failed")
            output = error.localizedDescription
        }
    }

    private func revealCLIContextsFolder() {
        let url = LauncherCLIContextStore.defaultDirectory()
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("Folder failed")
            output = error.localizedDescription
        }
    }

    private func movePathToTrash(_ path: String) {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            status = .succeeded("Moved to Trash")
            output = path
            refreshCLIContexts()
        } catch {
            status = .failed("Trash failed")
            output = error.localizedDescription
        }
    }

    private func revealWorkspace(_ path: String) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        status = .succeeded("Finder")
        output = path
    }

    private func revealScriptCommandsFolder() {
        let url = LauncherScriptCommandIndex.defaultRoots()[0]
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("Folder failed")
            output = error.localizedDescription
        }
    }

    private func revealQuicklinksFile() {
        let url = LauncherQuicklinkIndex.defaultURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try "[]\n".write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("File failed")
            output = error.localizedDescription
        }
    }

    private func revealPromptCommandsFile() {
        let url = LauncherPromptCommandIndex.defaultURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try "[]\n".write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("File failed")
            output = error.localizedDescription
        }
    }

    private func revealWorkflowsFile() {
        let url = LauncherWorkflowIndex.defaultURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try "[]\n".write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("File failed")
            output = error.localizedDescription
        }
    }

    private func savePromptCommand(from record: AIRunHistoryRecord) {
        let promptCommand = LauncherPromptCommandIndex.promptCommand(from: record)
        savePromptCommand(promptCommand)
    }

    private func savePromptCommand(_ promptCommand: LauncherPromptCommand) {
        do {
            try LauncherPromptCommandIndex.upsert(promptCommand)
            refreshPromptCommands()
            status = .succeeded("Prompt Saved")
            output = LauncherSavedArtifactSummary.text(promptCommand: promptCommand)
        } catch {
            status = .failed("Prompt save failed")
            output = error.localizedDescription
        }
    }

    private func saveSnippet(_ snippet: LauncherSnippet) {
        do {
            try LauncherSnippetIndex.upsert(snippet)
            refreshSnippets()
            status = .succeeded("Snippet Saved")
            output = LauncherSavedArtifactSummary.text(snippet: snippet)
        } catch {
            status = .failed("Snippet save failed")
            output = error.localizedDescription
        }
    }

    private func saveQuicklink(_ quicklink: LauncherQuicklink) {
        do {
            try LauncherQuicklinkIndex.upsert(quicklink)
            refreshQuicklinks()
            status = .succeeded("Quicklink Saved")
            output = LauncherSavedArtifactSummary.text(quicklink: quicklink)
        } catch {
            status = .failed("Quicklink save failed")
            output = error.localizedDescription
        }
    }

    private func saveCommandAlias(_ alias: LauncherCommandAlias) {
        do {
            try LauncherCommandAliasIndex.upsert(alias)
            refreshCommandAliases()
            status = .succeeded("Alias Saved")
            output = LauncherSavedArtifactSummary.text(alias: alias)
        } catch {
            status = .failed("Alias save failed")
            output = error.localizedDescription
        }
    }

    private func saveScriptCommand(_ draft: LauncherScriptCommandDraft) {
        do {
            let url = try LauncherScriptCommandIndex.save(draft)
            refreshScripts()
            status = .succeeded("Script Saved")
            output = LauncherSavedArtifactSummary.text(
                script: LauncherScriptCommand(
                    id: draft.id,
                    title: draft.title,
                    subtitle: draft.subtitle,
                    keywords: ["shell", "command", "saved"],
                    scriptPath: url.path
                ),
                path: url
            )
        } catch {
            status = .failed("Script save failed")
            output = error.localizedDescription
        }
    }

    private func saveWorkflow(_ workflow: LauncherWorkflow) {
        do {
            try LauncherWorkflowIndex.upsert(workflow)
            refreshWorkflows()
            status = .succeeded("Workflow Saved")
            output = LauncherSavedArtifactSummary.text(workflow: workflow)
        } catch {
            status = .failed("Workflow save failed")
            output = error.localizedDescription
        }
    }

    private func saveCurrentAIProfile() {
        let profile = LauncherAIProfileIndex.profile(
            fromModel: modelOverride,
            thinking: thinking,
            context1m: context1m
        )
        do {
            try LauncherAIProfileIndex.upsert(profile)
            refreshAIProfiles()
            status = .succeeded("Profile Saved")
            output = [
                profile.title,
                "",
                "Model: \(profile.modelDisplayName)",
                "Thinking: \(profile.thinking.displayName)",
                "1M context: \(profile.context1m ? "enabled" : "disabled")",
                "",
                LauncherAIProfileIndex.defaultURL().path,
            ].joined(separator: "\n")
        } catch {
            status = .failed("Profile save failed")
            output = error.localizedDescription
        }
    }

    private func revealAIProfilesFile() {
        let url = LauncherAIProfileIndex.defaultURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try "[]\n".write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("File failed")
            output = error.localizedDescription
        }
    }

    private func revealCommandAliasesFile() {
        let url = LauncherCommandAliasIndex.defaultURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try "[]\n".write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("File failed")
            output = error.localizedDescription
        }
    }

    private func revealSnippetsFile() {
        let url = LauncherSnippetIndex.defaultURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: url.path) {
                try "[]\n".write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            status = .succeeded("Finder")
            output = url.path
        } catch {
            status = .failed("File failed")
            output = error.localizedDescription
        }
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func saveUsage() {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        UserDefaults.standard.set(data, forKey: LauncherCommandUsage.defaultsKey)
    }

    private func saveAIHistory() {
        do {
            try AIRunHistoryStore.save(aiHistory)
            UserDefaults.standard.removeObject(forKey: aiHistoryDefaultsKey)
        } catch {
            // History should never obscure a successful AI response.
        }
    }

    @discardableResult
    private func saveClipboardHistory() -> Bool {
        do {
            try LauncherClipboardHistoryStore.save(clipboardHistory)
            clipboardCommands = LauncherClipboardHistoryCommandFactory.commands(for: clipboardHistory)
            normalizeSelection()
            normalizeActionSelection()
            return true
        } catch {
            status = .failed("Clipboard save failed")
            output = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func rememberClipboardText(_ text: String) -> Bool {
        guard clipboardHistory.add(text, limit: clipboardHistoryLimit) else { return false }
        return saveClipboardHistory()
    }

    private static func loadUsage(defaultsKey: String) -> LauncherCommandUsage {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let usage = try? JSONDecoder().decode(LauncherCommandUsage.self, from: data)
        else {
            return LauncherCommandUsage()
        }
        return usage
    }

    private static func loadAIHistory(defaultsKey: String) -> AIRunHistory {
        let stored = AIRunHistoryStore.load()
        guard stored.records.isEmpty else { return stored }

        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let history = try? JSONDecoder().decode(AIRunHistory.self, from: data)
        else {
            return AIRunHistory()
        }
        do {
            try AIRunHistoryStore.save(history)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } catch {
            return history
        }
        return history
    }

    private static func loadPreferences() -> LauncherPreferences {
        let defaults = UserDefaults.standard
        return LauncherPreferences(
            cliPathOverride: defaults.string(forKey: LauncherPreferenceKeys.cliPathOverride) ?? "",
            defaultModel: defaults.string(forKey: LauncherPreferenceKeys.defaultModel) ?? "",
            defaultThinking: LauncherPreferences.normalizedThinking(
                defaults.string(forKey: LauncherPreferenceKeys.defaultThinking) ?? KWWKThinkingLevel.medium.rawValue
            ),
            context1m: defaults.bool(forKey: LauncherPreferenceKeys.context1m),
            aiHistoryLimit: defaults.object(forKey: LauncherPreferenceKeys.aiHistoryLimit) as? Int
                ?? LauncherPreferences.defaultHistoryLimit,
            trackClipboardHistory: defaults.object(forKey: LauncherPreferenceKeys.trackClipboardHistory) as? Bool
                ?? LauncherPreferences.defaultTrackClipboardHistory,
            globalHotkey: LauncherPreferences.normalizedGlobalHotkey(
                defaults.string(forKey: LauncherPreferenceKeys.globalHotkey)
            ),
            launchAtLogin: defaults.object(forKey: LauncherPreferenceKeys.launchAtLogin) as? Bool
                ?? LauncherPreferences.defaultLaunchAtLogin
        )
    }

    private func aiHistoryRecord(for commandId: LauncherCommand.ID) -> AIRunHistoryRecord? {
        guard let id = AIRunHistoryCommandFactory.recordId(for: commandId) else { return nil }
        return aiHistory.record(id: id)
    }
}

enum LauncherStatus: Equatable {
    case idle
    case waitingForPrompt
    case running(String)
    case succeeded(String)
    case failed(String)
    case cancelled

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .waitingForPrompt: return "Prompt"
        case .running: return "Running"
        case .succeeded(let message): return message
        case .failed(let message): return message
        case .cancelled: return "Stopped"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
