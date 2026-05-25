import Foundation

public enum LauncherCommandCategory: String, CaseIterable, Sendable, Hashable {
    case ai = "AI"
    case alias = "Aliases"
    case app = "Apps"
    case calculator = "Calculator"
    case clipboard = "Clipboard"
    case cli = "CLI"
    case model = "Models"
    case quicklink = "Quicklinks"
    case recent = "Recent"
    case script = "Scripts"
    case scope = "Scopes"
    case snippet = "Snippets"
    case system = "System"
    case window = "Window"
    case workflow = "Workflows"
    case workspace = "Workspace"
}

public enum LauncherCommandAction: Sendable, Hashable {
    case askAI
    case askClipboard
    case askPrompt(String)
    case askContext(LauncherContextPromptKind)
    case askCLIContext(LauncherCLIContextRecord)
    case runAIPreset(LauncherAIPreset)
    case runPromptCommand(LauncherPromptCommand)
    case applyAIProfile(LauncherAIProfile)
    case saveCurrentAIProfile
    case setDefaultModel(LauncherModelCommand)
    case clearDefaultModel
    case setThinkingLevel(KWWKThinkingLevel)
    case setSearchQuery(String)
    case enableContext1M
    case disableContext1M
    case captureClipboard
    case clearClipboardHistory
    case copyClipboardHistory(LauncherClipboardHistoryRecord)
    case copyCalculatorResult(LauncherCalculatorResult)
    case copyUnitConversionResult(LauncherUnitConversionResult)
    case copySnippet(LauncherSnippet)
    case openApplication(String)
    case openInteractiveCLI
    case openInteractiveCLIAt(String)
    case openQuicklink(LauncherQuicklink)
    case openPath(LauncherPathCommandTarget)
    case runShellCommand(String)
    case runSystemCommand(LauncherSystemCommand)
    case runWindowCommand(LauncherWindowCommand)
    case login
    case rerunPrompt(String)
    case rerunAIHistory(AIRunHistoryRecord)
    case runRecentCommand(String)
    case runCommandAlias(LauncherCommandAlias)
    case copyCommand(String)
    case revealCLIContextsFolder
    case reloadCLIContexts
    case clearCLIContexts
    case revealOAuthStore
    case revealAIHistoryFile
    case reloadAIHistory
    case revealClipboardHistoryFile
    case revealWorkspace(String)
    case copyWorkspacePath(String)
    case openWorkspaceFile(LauncherWorkspaceFile)
    case runScript(LauncherScriptCommand)
    case runWorkflow(LauncherWorkflow)
    case revealScriptCommandsFolder
    case reloadScriptCommands
    case revealWorkflowsFile
    case reloadWorkflows
    case revealQuicklinksFile
    case reloadQuicklinks
    case revealPromptCommandsFile
    case reloadPromptCommands
    case revealAIProfilesFile
    case reloadAIProfiles
    case revealCommandAliasesFile
    case reloadCommandAliases
    case revealSnippetsFile
    case reloadSnippets
}

public enum LauncherDynamicCommandFactory {
    public static let askPromptPrefix = "ask-query:"

    public static func commands(for query: String) -> [LauncherCommand] {
        let prompt = LauncherCommandFilter.promptText(from: query)
        guard LauncherCommandFilter.looksLikePrompt(query), !prompt.isEmpty else { return [] }
        return [
            LauncherCommand(
                id: "\(askPromptPrefix)\(prompt)",
                title: "Ask KWWK",
                subtitle: prompt.truncatedForDynamicCommand(maxLength: 96),
                systemImage: "sparkles",
                category: .ai,
                keywords: ["ask", "ai", "prompt", "natural language"],
                action: .askPrompt(prompt)
            ),
        ]
    }
}

public enum LauncherShellCommandFactory {
    public static let commandPrefix = "shell:"

    public static func commands(for query: String) -> [LauncherCommand] {
        let text = LauncherCommandFilter.scopedQuery(from: query).text
        guard let commandText = commandText(from: text) else { return [] }
        return [
            LauncherCommand(
                id: "\(commandPrefix)\(commandText)",
                title: "Run Shell Command",
                subtitle: commandText.truncatedForShellCommand(maxLength: 96),
                systemImage: "terminal",
                category: .cli,
                keywords: ["shell", "terminal", "zsh", "command", commandText],
                action: .runShellCommand(commandText)
            ),
        ]
    }

    public static func commandText(from query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$") || trimmed.hasPrefix("!") else { return nil }
        let command = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }
}

public struct LauncherCommand: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var category: LauncherCommandCategory
    public var keywords: [String]
    public var action: LauncherCommandAction

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        category: LauncherCommandCategory,
        keywords: [String],
        action: LauncherCommandAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.category = category
        self.keywords = keywords
        self.action = action
    }
}

private extension String {
    func truncatedForDynamicCommand(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let end = index(startIndex, offsetBy: maxLength)
        return String(self[..<end]) + "..."
    }

    func truncatedForShellCommand(maxLength: Int) -> String {
        guard count > maxLength else { return self }
        let end = index(startIndex, offsetBy: maxLength)
        return String(self[..<end]) + "..."
    }
}

public enum LauncherCommandCatalog {
    public static let defaults: [LauncherCommand] = [
        LauncherCommand(
            id: "ask-kwwk",
            title: "Ask KWWK",
            subtitle: "Run a headless coding-agent prompt",
            systemImage: "sparkles",
            category: .ai,
            keywords: ["ask", "ai", "agent", "prompt", "headless", "kwwk -p"],
            action: .askAI
        ),
        LauncherCommand(
            id: "ask-clipboard",
            title: "Ask With Clipboard",
            subtitle: "Send clipboard text to the coding agent",
            systemImage: "doc.on.clipboard",
            category: .ai,
            keywords: ["clipboard", "paste", "prompt", "ai"],
            action: .askClipboard
        ),
    ] + LauncherScopeCommandCatalog.commands() + LauncherAIPresetCatalog.commands() + LauncherModelCommandCatalog.commands() + LauncherAISettingCommandCatalog.commands() + LauncherAIProfileCatalog.defaultCommands() + LauncherSystemCommandCatalog.commands() + LauncherWindowCommandCatalog.commands() + [
        LauncherCommand(
            id: "open-cli",
            title: "Open KWWK CLI",
            subtitle: "Start the interactive terminal agent",
            systemImage: "terminal",
            category: .cli,
            keywords: ["terminal", "interactive", "tui", "cli", "kwwk"],
            action: .openInteractiveCLI
        ),
        LauncherCommand(
            id: "login",
            title: "KWWK Login",
            subtitle: "Configure OAuth or API key credentials",
            systemImage: "key",
            category: .cli,
            keywords: ["auth", "oauth", "api key", "login", "credentials"],
            action: .login
        ),
        LauncherCommand(
            id: "copy-headless-command",
            title: "Copy Headless Command",
            subtitle: "kwwk -p",
            systemImage: "doc.on.doc",
            category: .cli,
            keywords: ["copy", "headless", "script", "shell", "automation"],
            action: .copyCommand("kwwk -p \"<prompt>\"")
        ),
        LauncherCommand(
            id: "reveal-cli-contexts",
            title: "Reveal Terminal Contexts Folder",
            subtitle: "~/.kwwk/launcher/context",
            systemImage: "folder.badge.gearshape",
            category: .cli,
            keywords: ["terminal", "context", "contexts", "stdin", "pipe", "captured", "folder", "file"],
            action: .revealCLIContextsFolder
        ),
        LauncherCommand(
            id: "reload-cli-contexts",
            title: "Reload Terminal Contexts",
            subtitle: "Rescan ~/.kwwk/launcher/context",
            systemImage: "arrow.clockwise",
            category: .cli,
            keywords: ["reload", "refresh", "terminal", "context", "contexts", "stdin", "pipe", "captured"],
            action: .reloadCLIContexts
        ),
        LauncherCommand(
            id: "clear-cli-contexts",
            title: "Clear Terminal Contexts",
            subtitle: "Move captured terminal contexts to Trash",
            systemImage: "trash",
            category: .cli,
            keywords: ["clear", "delete", "trash", "context", "contexts", "stdin", "pipe", "captured"],
            action: .clearCLIContexts
        ),
        LauncherCommand(
            id: "capture-current-clipboard",
            title: "Capture Current Clipboard",
            subtitle: "Save the current clipboard as a searchable result",
            systemImage: "doc.on.clipboard",
            category: .clipboard,
            keywords: ["clipboard", "pasteboard", "history", "capture", "copy"],
            action: .captureClipboard
        ),
        LauncherCommand(
            id: "clear-clipboard-history",
            title: "Clear Clipboard History",
            subtitle: "Remove saved clipboard command results",
            systemImage: "trash",
            category: .clipboard,
            keywords: ["clipboard", "pasteboard", "history", "clear", "delete"],
            action: .clearClipboardHistory
        ),
        LauncherCommand(
            id: "reveal-ai-history",
            title: "Reveal AI History File",
            subtitle: "~/.kwwk/launcher/ai-history.json",
            systemImage: "clock.arrow.circlepath",
            category: .ai,
            keywords: ["ai", "history", "recent", "file", "config"],
            action: .revealAIHistoryFile
        ),
        LauncherCommand(
            id: "reload-ai-history",
            title: "Reload AI History",
            subtitle: "Rescan ~/.kwwk/launcher/ai-history.json",
            systemImage: "arrow.clockwise",
            category: .ai,
            keywords: ["reload", "refresh", "ai", "history", "recent"],
            action: .reloadAIHistory
        ),
        LauncherCommand(
            id: "reveal-clipboard-history",
            title: "Reveal Clipboard History File",
            subtitle: "~/.kwwk/launcher/clipboard-history.json",
            systemImage: "folder",
            category: .clipboard,
            keywords: ["clipboard", "pasteboard", "history", "file", "config"],
            action: .revealClipboardHistoryFile
        ),
        LauncherCommand(
            id: "reveal-oauth-store",
            title: "Reveal OAuth Store",
            subtitle: "~/.kwwk/oauth.json",
            systemImage: "folder",
            category: .workspace,
            keywords: ["oauth", "store", "credentials", "file", "config"],
            action: .revealOAuthStore
        ),
        LauncherCommand(
            id: "reveal-script-commands",
            title: "Reveal Script Commands Folder",
            subtitle: "~/.kwwk/launcher/commands",
            systemImage: "folder.badge.gearshape",
            category: .script,
            keywords: ["script", "commands", "folder", "extension", "raycast"],
            action: .revealScriptCommandsFolder
        ),
        LauncherCommand(
            id: "reload-script-commands",
            title: "Reload Script Commands",
            subtitle: "Rescan ~/.kwwk/launcher/commands",
            systemImage: "arrow.clockwise",
            category: .script,
            keywords: ["reload", "refresh", "script", "commands", "extension"],
            action: .reloadScriptCommands
        ),
        LauncherCommand(
            id: "reveal-workflows",
            title: "Reveal Workflows File",
            subtitle: "~/.kwwk/launcher/workflows.json",
            systemImage: "point.3.connected.trianglepath.dotted",
            category: .workflow,
            keywords: ["workflow", "workflows", "automation", "file", "config"],
            action: .revealWorkflowsFile
        ),
        LauncherCommand(
            id: "reload-workflows",
            title: "Reload Workflows",
            subtitle: "Rescan ~/.kwwk/launcher/workflows.json",
            systemImage: "arrow.clockwise",
            category: .workflow,
            keywords: ["reload", "refresh", "workflow", "workflows", "automation"],
            action: .reloadWorkflows
        ),
        LauncherCommand(
            id: "reveal-quicklinks",
            title: "Reveal Quicklinks File",
            subtitle: "~/.kwwk/launcher/quicklinks.json",
            systemImage: "link",
            category: .quicklink,
            keywords: ["quicklink", "quicklinks", "url", "links", "config"],
            action: .revealQuicklinksFile
        ),
        LauncherCommand(
            id: "reload-quicklinks",
            title: "Reload Quicklinks",
            subtitle: "Rescan ~/.kwwk/launcher/quicklinks.json",
            systemImage: "arrow.clockwise",
            category: .quicklink,
            keywords: ["reload", "refresh", "quicklink", "quicklinks", "url"],
            action: .reloadQuicklinks
        ),
        LauncherCommand(
            id: "reveal-prompt-commands",
            title: "Reveal AI Prompt Commands File",
            subtitle: "~/.kwwk/launcher/prompts.json",
            systemImage: "sparkles",
            category: .ai,
            keywords: ["ai", "prompt", "prompts", "commands", "config"],
            action: .revealPromptCommandsFile
        ),
        LauncherCommand(
            id: "reload-prompt-commands",
            title: "Reload AI Prompt Commands",
            subtitle: "Rescan ~/.kwwk/launcher/prompts.json",
            systemImage: "arrow.clockwise",
            category: .ai,
            keywords: ["reload", "refresh", "ai", "prompt", "prompts", "commands"],
            action: .reloadPromptCommands
        ),
        LauncherCommand(
            id: "reveal-command-aliases",
            title: "Reveal Command Aliases File",
            subtitle: "~/.kwwk/launcher/aliases.json",
            systemImage: "arrow.triangle.branch",
            category: .alias,
            keywords: ["alias", "aliases", "shortcut", "shortcuts", "commands", "config"],
            action: .revealCommandAliasesFile
        ),
        LauncherCommand(
            id: "reload-command-aliases",
            title: "Reload Command Aliases",
            subtitle: "Rescan ~/.kwwk/launcher/aliases.json",
            systemImage: "arrow.clockwise",
            category: .alias,
            keywords: ["reload", "refresh", "alias", "aliases", "shortcut", "shortcuts"],
            action: .reloadCommandAliases
        ),
        LauncherCommand(
            id: "reveal-snippets",
            title: "Reveal Snippets File",
            subtitle: "~/.kwwk/launcher/snippets.json",
            systemImage: "text.quote",
            category: .snippet,
            keywords: ["snippet", "snippets", "text", "template", "config"],
            action: .revealSnippetsFile
        ),
        LauncherCommand(
            id: "reload-snippets",
            title: "Reload Snippets",
            subtitle: "Rescan ~/.kwwk/launcher/snippets.json",
            systemImage: "arrow.clockwise",
            category: .snippet,
            keywords: ["reload", "refresh", "snippet", "snippets", "text"],
            action: .reloadSnippets
        ),
    ]
}

public enum LauncherRecentCommandFactory {
    public static let commandPrefix = "recent:"

    public static func commands(
        from commands: [LauncherCommand],
        usage: LauncherCommandUsage,
        limit: Int = 5
    ) -> [LauncherCommand] {
        let commandsById = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
        return usage.records
            .compactMap { id, record -> RecentCommand? in
                guard let lastUsedAt = record.lastUsedAt,
                      let command = commandsById[id]
                else {
                    return nil
                }
                return RecentCommand(command: command, lastUsedAt: lastUsedAt)
            }
            .sorted { lhs, rhs in
                if lhs.lastUsedAt != rhs.lastUsedAt { return lhs.lastUsedAt > rhs.lastUsedAt }
                return lhs.command.title.localizedStandardCompare(rhs.command.title) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { recent in
                LauncherCommand(
                    id: "\(commandPrefix)\(recent.command.id)",
                    title: recent.command.title,
                    subtitle: "Recent - \(recent.command.subtitle)",
                    systemImage: "clock.arrow.circlepath",
                    category: .recent,
                    keywords: recent.command.keywords + ["recent", "again", recent.command.category.rawValue],
                    action: .runRecentCommand(recent.command.id)
                )
            }
    }

    public static func originalCommandId(for commandId: LauncherCommand.ID) -> LauncherCommand.ID? {
        guard commandId.hasPrefix(commandPrefix) else { return nil }
        return String(commandId.dropFirst(commandPrefix.count))
    }
}

private struct RecentCommand {
    var command: LauncherCommand
    var lastUsedAt: Date
}

public struct LauncherWorkspaceContext: Sendable, Hashable {
    public var path: String
    public var displayName: String

    public init?(path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded, isDirectory: true)
            .standardizedFileURL
            .path
        guard !standardized.isEmpty else { return nil }

        let lastPathComponent = URL(fileURLWithPath: standardized, isDirectory: true).lastPathComponent
        self.path = standardized
        self.displayName = lastPathComponent.isEmpty ? standardized : lastPathComponent
    }
}

public enum LauncherWorkspaceCommandFactory {
    public static func commands(for workingDirectory: String?) -> [LauncherCommand] {
        guard let context = LauncherWorkspaceContext(path: workingDirectory) else { return [] }
        return [
            LauncherCommand(
                id: "workspace:open-cli",
                title: "Open CLI Here",
                subtitle: context.subtitle,
                systemImage: "terminal",
                category: .workspace,
                keywords: context.keywords + ["terminal", "interactive", "cli", "cwd"],
                action: .openInteractiveCLIAt(context.path)
            ),
            LauncherCommand(
                id: "workspace:reveal",
                title: "Reveal Workspace",
                subtitle: context.path,
                systemImage: "folder",
                category: .workspace,
                keywords: context.keywords + ["finder", "reveal", "project"],
                action: .revealWorkspace(context.path)
            ),
            LauncherCommand(
                id: "workspace:copy-path",
                title: "Copy Workspace Path",
                subtitle: context.path,
                systemImage: "doc.on.doc",
                category: .workspace,
                keywords: context.keywords + ["copy", "path", "pwd"],
                action: .copyWorkspacePath(context.path)
            ),
        ]
    }
}

private extension LauncherWorkspaceContext {
    var subtitle: String {
        "Active workspace: \(displayName)"
    }

    var keywords: [String] {
        ["workspace", "project", "directory", displayName, path]
    }
}
