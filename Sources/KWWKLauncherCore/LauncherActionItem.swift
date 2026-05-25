import Foundation

public enum LauncherActionKind: Sendable, Hashable {
    case runPrimary
    case toggleFavorite
    case askKWWK(String)
    case copyText(String)
    case openTerminalCommand(String)
    case revealPath(String)
    case trashPath(String)
    case savePromptCommand(AIRunHistoryRecord)
    case savePromptTemplate(LauncherPromptCommand)
    case saveSnippet(LauncherSnippet)
    case saveQuicklink(LauncherQuicklink)
    case saveCommandAlias(LauncherCommandAlias)
    case saveScriptCommand(LauncherScriptCommandDraft)
    case saveWorkflow(LauncherWorkflow)
}

public struct LauncherActionItem: Identifiable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var kind: LauncherActionKind

    public init(id: String, title: String, subtitle: String, systemImage: String, kind: LauncherActionKind) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.kind = kind
    }
}

public enum LauncherActionFilter {
    public static func filter(_ actions: [LauncherActionItem], query: String) -> [LauncherActionItem] {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return actions }

        return actions
            .enumerated()
            .compactMap { index, action -> ScoredAction? in
                let score = score(action, query: normalized)
                guard score > 0 else { return nil }
                return ScoredAction(action: action, score: score, index: index)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.index < rhs.index
            }
            .map(\.action)
    }

    private static func score(_ action: LauncherActionItem, query: String) -> Int {
        let id = normalize(action.id)
        let title = normalize(action.title)
        let subtitle = normalize(action.subtitle)

        if title == query { return 1000 }
        if title.hasPrefix(query) { return 800 }
        if id == query { return 760 }
        if id.hasPrefix(query) { return 700 }
        if title.contains(query) { return 520 }
        if subtitle.contains(query) { return 260 }

        let tokens = query.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return 0 }
        let haystack = [id, title, subtitle].joined(separator: " ")
        let matched = tokens.filter { haystack.contains($0) }.count
        return matched == tokens.count ? 120 + matched : 0
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
}

private struct ScoredAction {
    var action: LauncherActionItem
    var score: Int
    var index: Int
}

public enum LauncherActionCatalog {
    public static func featuredActions(
        from actions: [LauncherActionItem],
        limit: Int = 3
    ) -> [LauncherActionItem] {
        let genericActionIds: Set<String> = [
            "primary",
            "favorite",
            "ask-kwwk",
            "open-context-draft",
            "copy-launcher-command",
            "copy-launcher-url",
            "copy-inspect-command",
            "save-command-alias",
        ]
        let commandSpecificActions = actions.filter { !genericActionIds.contains($0.id) }
        let fallbackActions = actions.filter { $0.id == "open-context-draft" }
        return Array((commandSpecificActions + fallbackActions).prefix(max(0, limit)))
    }

    public static func actions(
        for command: LauncherCommand,
        isFavorite: Bool,
        query: String = "",
        clipboard: String = "",
        context: LauncherContextSnapshot = LauncherContextSnapshot(),
        executable: String = "kwwk",
        thinking: KWWKThinkingLevel = .medium,
        model: String = "",
        context1m: Bool = false,
        workingDirectory: String? = nil
    ) -> [LauncherActionItem] {
        let headlessContext = HeadlessTerminalActionContext(
            executable: executable,
            thinking: thinking,
            model: model,
            context1m: context1m,
            workingDirectory: workingDirectory
        )
        let commandContextPrompt = prompt(
            for: command,
            query: query,
            clipboard: clipboard,
            context: context
        )
        var actions: [LauncherActionItem] = [
            LauncherActionItem(
                id: "primary",
                title: primaryTitle(for: command),
                subtitle: command.title,
                systemImage: primarySystemImage(for: command),
                kind: .runPrimary
            ),
            LauncherActionItem(
                id: "favorite",
                title: isFavorite ? "Remove Favorite" : "Favorite",
                subtitle: isFavorite ? "Stop ranking this command first" : "Rank this command first",
                systemImage: isFavorite ? "star.slash" : "star",
                kind: .toggleFavorite
            ),
            LauncherActionItem(
                id: "ask-kwwk",
                title: "Ask KWWK About This",
                subtitle: "Send the selected result as context",
                systemImage: "sparkles",
                kind: .askKWWK(commandContextPrompt)
            ),
            LauncherActionItem(
                id: "open-context-draft",
                title: "Open Context Draft in CLI",
                subtitle: "Interactive CLI draft",
                systemImage: "terminal",
                kind: .openTerminalCommand(KWWKCLIInvocation.interactiveDraftTerminalCommand(
                    prompt: commandContextPrompt,
                    executable: executable,
                    thinking: thinking,
                    model: model,
                    context1m: context1m,
                    workingDirectory: workingDirectory
                ))
            ),
            LauncherActionItem(
                id: "copy-launcher-command",
                title: "Copy Launcher Command",
                subtitle: launcherCommand(for: command, query: query),
                systemImage: "terminal",
                kind: .copyText(launcherCommand(for: command, query: query))
            ),
            LauncherActionItem(
                id: "copy-launcher-url",
                title: "Copy Launcher URL",
                subtitle: launcherURL(for: command, query: query, workingDirectory: workingDirectory),
                systemImage: "link",
                kind: .copyText(launcherURL(for: command, query: query, workingDirectory: workingDirectory))
            ),
            LauncherActionItem(
                id: "copy-inspect-command",
                title: "Copy Inspect Command",
                subtitle: inspectCommand(for: command, query: query),
                systemImage: "curlybraces.square",
                kind: .copyText(inspectCommand(for: command, query: query))
            ),
        ]
        if let alias = LauncherCommandAliasIndex.alias(from: command) {
            actions.append(LauncherActionItem(
                id: "save-command-alias",
                title: "Save as Alias",
                subtitle: alias.targetCommandId,
                systemImage: "arrow.triangle.branch",
                kind: .saveCommandAlias(alias)
            ))
        }

        switch command.action {
        case .askAI:
            let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty {
                actions.append(headlessTerminalAction(prompt: prompt, context: headlessContext))
                actions.append(interactiveDraftAction(prompt: prompt, context: headlessContext))
                if let workflow = LauncherWorkflowIndex.workflow(fromPrompt: prompt) {
                    actions.append(saveWorkflowAction(workflow))
                }
            }
        case .askClipboard:
            let prompt = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prompt.isEmpty {
                actions.append(headlessTerminalAction(prompt: prompt, context: headlessContext))
                actions.append(interactiveDraftAction(prompt: prompt, context: headlessContext))
                if let workflow = LauncherWorkflowIndex.workflow(fromPrompt: prompt) {
                    actions.append(saveWorkflowAction(workflow))
                }
            }
        case .askPrompt(let prompt):
            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPrompt.isEmpty {
                actions.append(headlessTerminalAction(prompt: trimmedPrompt, context: headlessContext))
                actions.append(interactiveDraftAction(prompt: trimmedPrompt, context: headlessContext))
                if let promptCommand = LauncherPromptCommandIndex.promptCommand(fromPrompt: trimmedPrompt) {
                    actions.append(LauncherActionItem(
                        id: "save-prompt-command",
                        title: "Save as Prompt Command",
                        subtitle: LauncherPromptCommandIndex.defaultURL().path,
                        systemImage: "plus.square.on.square",
                        kind: .savePromptTemplate(promptCommand)
                    ))
                }
                if let workflow = LauncherWorkflowIndex.workflow(fromPrompt: trimmedPrompt) {
                    actions.append(saveWorkflowAction(workflow))
                }
            }
        case .askContext(let kind):
            if context.supports(kind) {
                let prompt = LauncherContextPromptBuilder.prompt(for: kind, query: query, context: context)
                actions.append(headlessTerminalAction(prompt: prompt, context: headlessContext))
                actions.append(interactiveDraftAction(prompt: prompt, context: headlessContext))
            }
        case .askCLIContext(let record):
            let prompt = record.askPrompt
            var contextActions = [
                headlessTerminalAction(prompt: prompt, context: headlessContext),
                interactiveDraftAction(prompt: prompt, context: headlessContext),
            ]
            if let capturedText = record.capturedText() {
                contextActions.append(LauncherActionItem(
                    id: "copy-context",
                    title: "Copy Captured Output",
                    subtitle: record.title,
                    systemImage: "doc.on.doc",
                    kind: .copyText(capturedText)
                ))
            }
            contextActions += [
                LauncherActionItem(
                    id: "copy-context-prompt",
                    title: "Copy Ask Prompt",
                    subtitle: "Prompt with captured context",
                    systemImage: "text.quote",
                    kind: .copyText(prompt)
                ),
                LauncherActionItem(
                    id: "save-prompt-command",
                    title: "Save as Prompt Command",
                    subtitle: LauncherPromptCommandIndex.defaultURL().path,
                    systemImage: "plus.square.on.square",
                    kind: .savePromptTemplate(LauncherPromptCommandIndex.promptCommand(from: record))
                ),
                saveWorkflowAction(LauncherWorkflowIndex.workflow(from: record)),
            ]
            if let snippet = LauncherSnippetIndex.snippet(from: record) {
                contextActions.append(LauncherActionItem(
                    id: "save-context-snippet",
                    title: "Save Context as Snippet",
                    subtitle: LauncherSnippetIndex.defaultURL().path,
                    systemImage: "text.quote",
                    kind: .saveSnippet(snippet)
                ))
            }
            contextActions.append(contentsOf: [
                LauncherActionItem(
                    id: "reveal",
                    title: "Reveal in Finder",
                    subtitle: record.path,
                    systemImage: "folder",
                    kind: .revealPath(record.path)
                ),
                LauncherActionItem(
                    id: "copy-path",
                    title: "Copy Context Path",
                    subtitle: record.path,
                    systemImage: "doc.on.doc",
                    kind: .copyText(record.path)
                ),
                LauncherActionItem(
                    id: "trash-context",
                    title: "Move Context to Trash",
                    subtitle: record.path,
                    systemImage: "trash",
                    kind: .trashPath(record.path)
                ),
            ])
            actions.append(contentsOf: contextActions)
        case .openApplication(let path):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "reveal",
                    title: "Reveal in Finder",
                    subtitle: path,
                    systemImage: "folder",
                    kind: .revealPath(path)
                ),
                LauncherActionItem(
                    id: "copy-path",
                    title: "Copy Path",
                    subtitle: path,
                    systemImage: "doc.on.doc",
                    kind: .copyText(path)
                ),
            ])
        case .openInteractiveCLIAt(let path):
            actions.append(contentsOf: workspaceActions(for: path))
        case .openQuicklink(let quicklink):
            let urlString = quicklink.renderedURLString(query: query)
            actions.append(LauncherActionItem(
                id: "copy-url",
                title: "Copy URL",
                subtitle: urlString,
                systemImage: "link",
                kind: .copyText(urlString)
            ))
            if let savedQuicklink = LauncherQuicklinkIndex.quicklink(fromDynamicCommand: command) {
                actions.append(LauncherActionItem(
                    id: "save-quicklink",
                    title: "Save as Quicklink",
                    subtitle: "~/.kwwk/launcher/quicklinks.json",
                    systemImage: "link.badge.plus",
                    kind: .saveQuicklink(savedQuicklink)
                ))
            }
        case .openPath(let target):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "ask-path",
                    title: "Ask KWWK About Path",
                    subtitle: target.displayPath,
                    systemImage: "sparkles",
                    kind: .askKWWK(target.askPrompt)
                ),
                LauncherActionItem(
                    id: "reveal",
                    title: "Reveal in Finder",
                    subtitle: target.path,
                    systemImage: "folder",
                    kind: .revealPath(target.path)
                ),
                LauncherActionItem(
                    id: "copy-path",
                    title: "Copy Path",
                    subtitle: target.path,
                    systemImage: "doc.on.doc",
                    kind: .copyText(target.path)
                ),
            ])
        case .revealWorkspace(let path):
            actions.append(LauncherActionItem(
                id: "copy-path",
                title: "Copy Path",
                subtitle: path,
                systemImage: "doc.on.doc",
                kind: .copyText(path)
            ))
        case .copyWorkspacePath(let path):
            actions.append(LauncherActionItem(
                id: "reveal",
                title: "Reveal in Finder",
                subtitle: path,
                systemImage: "folder",
                kind: .revealPath(path)
            ))
        case .runShellCommand(let commandText):
            actions.append(LauncherActionItem(
                id: "copy-command",
                title: "Copy Command",
                subtitle: commandText,
                systemImage: "doc.on.doc",
                kind: .copyText(commandText)
            ))
            if let draft = LauncherScriptCommandIndex.scriptDraft(fromShellCommand: commandText) {
                actions.append(LauncherActionItem(
                    id: "save-script-command",
                    title: "Save as Script Command",
                    subtitle: "~/.kwwk/launcher/commands/\(draft.fileName)",
                    systemImage: "folder.badge.gearshape",
                    kind: .saveScriptCommand(draft)
                ))
            }
            if let workflow = LauncherWorkflowIndex.workflow(fromShellCommand: commandText) {
                actions.append(saveWorkflowAction(workflow))
            }
        case .openWorkspaceFile(let file):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "ask-file",
                    title: "Ask KWWK About File",
                    subtitle: file.relativePath,
                    systemImage: "sparkles",
                    kind: .askKWWK(file.askPrompt)
                ),
                LauncherActionItem(
                    id: "reveal",
                    title: "Reveal in Finder",
                    subtitle: file.path,
                    systemImage: "folder",
                    kind: .revealPath(file.path)
                ),
                LauncherActionItem(
                    id: "copy-path",
                    title: "Copy Path",
                    subtitle: file.path,
                    systemImage: "doc.on.doc",
                    kind: .copyText(file.path)
                ),
                LauncherActionItem(
                    id: "copy-relative-path",
                    title: "Copy Relative Path",
                    subtitle: file.relativePath,
                    systemImage: "text.badge.checkmark",
                    kind: .copyText(file.relativePath)
                ),
            ])
        case .runScript(let script):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "reveal",
                    title: "Reveal in Finder",
                    subtitle: script.scriptPath,
                    systemImage: "folder",
                    kind: .revealPath(script.scriptPath)
                ),
                LauncherActionItem(
                    id: "copy-path",
                    title: "Copy Script Path",
                    subtitle: script.scriptPath,
                    systemImage: "doc.on.doc",
                    kind: .copyText(script.scriptPath)
                ),
            ])
        case .runWorkflow(let workflow):
            let workflowTerminalCommand = workflow.terminalCommand(
                query: query,
                executable: executable,
                workingDirectory: workingDirectory
            )
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-workflow-id",
                    title: "Copy Workflow ID",
                    subtitle: workflow.id,
                    systemImage: "doc.on.doc",
                    kind: .copyText(workflow.id)
                ),
                LauncherActionItem(
                    id: "copy-workflow-preview",
                    title: "Copy Rendered Workflow",
                    subtitle: workflow.title,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    kind: .copyText(workflow.previewText(query: query, clipboard: clipboard, context: context))
                ),
                LauncherActionItem(
                    id: "copy-workflow-runtime",
                    title: "Copy Workflow Runtime",
                    subtitle: workflow.runtimeDescription,
                    systemImage: "slider.horizontal.3",
                    kind: .copyText(workflow.runtimeDescription)
                ),
                LauncherActionItem(
                    id: "open-workflow-terminal",
                    title: "Open Workflow in Terminal",
                    subtitle: workflowTerminalCommand.truncatedForActionSubtitle(maxLength: 72),
                    systemImage: "terminal",
                    kind: .openTerminalCommand(workflowTerminalCommand)
                ),
                LauncherActionItem(
                    id: "copy-workflow-cli-command",
                    title: "Copy Workflow CLI Command",
                    subtitle: workflow.cliCommand(query: query),
                    systemImage: "terminal",
                    kind: .copyText(workflow.cliCommand(query: query))
                ),
            ])
        case .runAIPreset(let preset):
            let input = preset.input(query: query, clipboard: clipboard)
            actions.append(LauncherActionItem(
                id: "copy-instruction",
                title: "Copy Instruction",
                subtitle: preset.title,
                systemImage: "doc.on.doc",
                kind: .copyText(preset.instruction)
            ))
            if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let prompt = preset.prompt(input: input)
                actions.append(headlessTerminalAction(prompt: prompt, context: headlessContext))
                actions.append(interactiveDraftAction(prompt: prompt, context: headlessContext))
                if let workflow = LauncherWorkflowIndex.workflow(fromPrompt: prompt) {
                    actions.append(saveWorkflowAction(workflow))
                }
            }
        case .runPromptCommand(let promptCommand):
            let prompt = promptCommand.renderedPrompt(query: query, clipboard: clipboard, context: context)
            actions.append(LauncherActionItem(
                id: "copy-prompt",
                title: "Copy Rendered Prompt",
                subtitle: prompt.truncatedForActionSubtitle(maxLength: 72),
                systemImage: "doc.on.doc",
                kind: .copyText(prompt)
            ))
            if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                actions.append(headlessTerminalAction(prompt: prompt, context: headlessContext))
                actions.append(interactiveDraftAction(prompt: prompt, context: headlessContext))
                if let workflow = LauncherWorkflowIndex.workflow(fromPrompt: prompt) {
                    actions.append(saveWorkflowAction(workflow))
                }
            }
        case .applyAIProfile(let profile):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-profile-flags",
                    title: "Copy Profile Flags",
                    subtitle: profile.cliFlags,
                    systemImage: "terminal",
                    kind: .copyText(profile.cliFlags)
                ),
                LauncherActionItem(
                    id: "copy-headless-command",
                    title: "Copy Headless Command",
                    subtitle: "kwwk \(profile.cliFlags) -p \"<prompt>\"",
                    systemImage: "terminal",
                    kind: .copyText("kwwk \(profile.cliFlags) -p '<prompt>'")
                ),
            ])
        case .setDefaultModel(let model):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-model-id",
                    title: "Copy Model ID",
                    subtitle: model.id,
                    systemImage: "doc.on.doc",
                    kind: .copyText(model.id)
                ),
                LauncherActionItem(
                    id: "copy-model-flag",
                    title: "Copy Model Flag",
                    subtitle: "--model \(model.id)",
                    systemImage: "terminal",
                    kind: .copyText("--model \(KWWKShellCommand.quote(model.id))")
                ),
                LauncherActionItem(
                    id: "copy-headless-command",
                    title: "Copy Headless Command",
                    subtitle: "kwwk --model \(model.id) -p \"<prompt>\"",
                    systemImage: "terminal",
                    kind: .copyText(
                        "kwwk --model \(KWWKShellCommand.quote(model.id)) -p '<prompt>'"
                    )
                ),
            ])
        case .clearDefaultModel:
            actions.append(LauncherActionItem(
                id: "copy-default-command",
                title: "Copy Provider Default Command",
                subtitle: "kwwk -p \"<prompt>\"",
                systemImage: "terminal",
                kind: .copyText("kwwk -p '<prompt>'")
            ))
        case .setThinkingLevel(let level):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-thinking-flag",
                    title: "Copy Thinking Flag",
                    subtitle: "--thinking \(level.rawValue)",
                    systemImage: "terminal",
                    kind: .copyText("--thinking \(level.rawValue)")
                ),
                LauncherActionItem(
                    id: "copy-headless-command",
                    title: "Copy Headless Command",
                    subtitle: "kwwk --thinking \(level.rawValue) -p \"<prompt>\"",
                    systemImage: "terminal",
                    kind: .copyText("kwwk --thinking \(level.rawValue) -p '<prompt>'")
                ),
            ])
        case .enableContext1M:
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-context-flag",
                    title: "Copy Context Flag",
                    subtitle: "--context-1m",
                    systemImage: "terminal",
                    kind: .copyText("--context-1m")
                ),
                LauncherActionItem(
                    id: "copy-headless-command",
                    title: "Copy Headless Command",
                    subtitle: "kwwk --context-1m -p \"<prompt>\"",
                    systemImage: "terminal",
                    kind: .copyText("kwwk --context-1m -p '<prompt>'")
                ),
            ])
        case .disableContext1M:
            actions.append(LauncherActionItem(
                id: "copy-default-context-command",
                title: "Copy Normal Context Command",
                subtitle: "kwwk -p \"<prompt>\"",
                systemImage: "terminal",
                kind: .copyText("kwwk -p '<prompt>'")
            ))
        case .copyClipboardHistory(let record):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-text",
                    title: "Copy Text",
                    subtitle: record.subtitle.truncatedForActionSubtitle(maxLength: 72),
                    systemImage: "doc.on.doc",
                    kind: .copyText(record.text)
                ),
                LauncherActionItem(
                    id: "save-snippet",
                    title: "Save as Snippet",
                    subtitle: LauncherSnippetIndex.snippet(from: record).title,
                    systemImage: "plus.square.on.square",
                    kind: .saveSnippet(LauncherSnippetIndex.snippet(from: record))
                ),
            ])
        case .copyCalculatorResult(let result):
            let snippet = LauncherSnippetIndex.snippet(from: result)
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-result",
                    title: "Copy Result",
                    subtitle: result.formattedValue,
                    systemImage: "doc.on.doc",
                    kind: .copyText(result.formattedValue)
                ),
                LauncherActionItem(
                    id: "copy-expression",
                    title: "Copy Expression",
                    subtitle: result.expression,
                    systemImage: "function",
                    kind: .copyText(result.expression)
                ),
                LauncherActionItem(
                    id: "save-result-snippet",
                    title: "Save Result as Snippet",
                    subtitle: snippet.title,
                    systemImage: "text.quote",
                    kind: .saveSnippet(snippet)
                ),
            ])
        case .copyUnitConversionResult(let result):
            let snippet = LauncherSnippetIndex.snippet(from: result)
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-result",
                    title: "Copy Result",
                    subtitle: result.formattedOutput,
                    systemImage: "doc.on.doc",
                    kind: .copyText(result.formattedOutput)
                ),
                LauncherActionItem(
                    id: "copy-expression",
                    title: "Copy Expression",
                    subtitle: result.expression,
                    systemImage: "arrow.left.arrow.right",
                    kind: .copyText(result.expression)
                ),
                LauncherActionItem(
                    id: "save-result-snippet",
                    title: "Save Result as Snippet",
                    subtitle: snippet.title,
                    systemImage: "text.quote",
                    kind: .saveSnippet(snippet)
                ),
            ])
        case .copySnippet(let snippet):
            let text = snippet.renderedText(query: query, clipboard: clipboard, context: context)
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-snippet",
                    title: "Copy Rendered Snippet",
                    subtitle: text.truncatedForActionSubtitle(maxLength: 72),
                    systemImage: "doc.on.doc",
                    kind: .copyText(text)
                ),
                LauncherActionItem(
                    id: "copy-template",
                    title: "Copy Template",
                    subtitle: snippet.textTemplate.truncatedForActionSubtitle(maxLength: 72),
                    systemImage: "text.quote",
                    kind: .copyText(snippet.textTemplate)
                ),
            ])
        case .rerunAIHistory(let record):
            actions.append(contentsOf: historyActions(for: record, context: headlessContext))
        case .runRecentCommand(let commandId):
            actions.append(LauncherActionItem(
                id: "copy-command-id",
                title: "Copy Command ID",
                subtitle: commandId,
                systemImage: "doc.on.doc",
                kind: .copyText(commandId)
            ))
        case .runCommandAlias(let alias):
            actions.append(LauncherActionItem(
                id: "copy-target-command-id",
                title: "Copy Target Command ID",
                subtitle: alias.targetCommandId,
                systemImage: "doc.on.doc",
                kind: .copyText(alias.targetCommandId)
            ))
        case .copyCommand(let commandText):
            actions.append(contentsOf: [
                LauncherActionItem(
                    id: "copy-command",
                    title: "Copy Command",
                    subtitle: commandText,
                    systemImage: "doc.on.doc",
                    kind: .copyText(commandText)
                ),
                LauncherActionItem(
                    id: "open-terminal",
                    title: "Open in Terminal",
                    subtitle: commandText,
                    systemImage: "terminal",
                    kind: .openTerminalCommand(commandText)
                ),
            ])
        case .revealOAuthStore:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/oauth.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/oauth.json")
            ))
        case .revealAIHistoryFile, .reloadAIHistory:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/ai-history.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/ai-history.json")
            ))
        case .revealClipboardHistoryFile, .clearClipboardHistory:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/clipboard-history.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/clipboard-history.json")
            ))
        case .revealCLIContextsFolder, .reloadCLIContexts, .clearCLIContexts:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/context",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/context")
            ))
        case .revealScriptCommandsFolder, .reloadScriptCommands:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/commands",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/commands")
            ))
        case .revealWorkflowsFile, .reloadWorkflows:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/workflows.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/workflows.json")
            ))
        case .revealQuicklinksFile, .reloadQuicklinks:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/quicklinks.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/quicklinks.json")
            ))
        case .revealPromptCommandsFile, .reloadPromptCommands:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/prompts.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/prompts.json")
            ))
        case .saveCurrentAIProfile, .revealAIProfilesFile, .reloadAIProfiles:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/profiles.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/profiles.json")
            ))
        case .revealCommandAliasesFile, .reloadCommandAliases:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/aliases.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/aliases.json")
            ))
        case .revealSnippetsFile, .reloadSnippets:
            actions.append(LauncherActionItem(
                id: "copy-location",
                title: "Copy Location",
                subtitle: "~/.kwwk/launcher/snippets.json",
                systemImage: "doc.on.doc",
                kind: .copyText("~/.kwwk/launcher/snippets.json")
            ))
        default:
            break
        }

        return actions
    }

    public static func primaryTitle(for command: LauncherCommand) -> String {
        switch command.action {
        case .askAI, .askClipboard, .askPrompt, .askContext, .askCLIContext:
            return "Ask"
        case .runAIPreset:
            return "Run Preset"
        case .runPromptCommand:
            return "Run Prompt"
        case .applyAIProfile:
            return "Apply Profile"
        case .saveCurrentAIProfile:
            return "Save Profile"
        case .setDefaultModel:
            return "Use Model"
        case .clearDefaultModel:
            return "Clear"
        case .setThinkingLevel:
            return "Set Thinking"
        case .setSearchQuery:
            return "Search"
        case .enableContext1M:
            return "Enable"
        case .disableContext1M:
            return "Disable"
        case .captureClipboard:
            return "Capture"
        case .clearClipboardHistory:
            return "Clear"
        case .copyClipboardHistory:
            return "Copy"
        case .copyCalculatorResult:
            return "Copy"
        case .copyUnitConversionResult:
            return "Copy"
        case .copySnippet:
            return "Copy"
        case .rerunPrompt, .rerunAIHistory:
            return "Ask Again"
        case .runRecentCommand:
            return "Run Again"
        case .runCommandAlias:
            return "Run"
        case .openApplication:
            return "Open"
        case .openQuicklink:
            return "Open"
        case .openPath:
            return "Open"
        case .openWorkspaceFile:
            return "Open"
        case .openInteractiveCLIAt:
            return "Open CLI"
        case .runShellCommand:
            return "Run"
        case .runSystemCommand:
            return "Run"
        case .runWindowCommand:
            return "Move"
        case .runScript:
            return "Run Script"
        case .runWorkflow:
            return "Run Workflow"
        case .openInteractiveCLI:
            return "Open CLI"
        case .login:
            return "Login"
        case .copyCommand:
            return "Copy"
        case .copyWorkspacePath:
            return "Copy"
        case .revealOAuthStore, .revealAIHistoryFile, .revealClipboardHistoryFile, .revealCLIContextsFolder, .revealScriptCommandsFolder, .revealWorkflowsFile, .revealQuicklinksFile, .revealPromptCommandsFile, .revealAIProfilesFile, .revealCommandAliasesFile, .revealSnippetsFile:
            return "Reveal"
        case .revealWorkspace:
            return "Reveal"
        case .reloadAIHistory, .reloadCLIContexts, .reloadScriptCommands, .reloadWorkflows, .reloadQuicklinks, .reloadPromptCommands, .reloadAIProfiles, .reloadCommandAliases, .reloadSnippets:
            return "Reload"
        case .clearCLIContexts:
            return "Clear"
        }
    }

    private static func primarySystemImage(for command: LauncherCommand) -> String {
        switch command.action {
        case .askAI, .askClipboard, .askPrompt, .askContext, .askCLIContext, .runAIPreset, .runPromptCommand, .runWorkflow, .rerunPrompt, .rerunAIHistory:
            return "sparkles"
        case .applyAIProfile(let profile):
            return profile.systemImage
        case .saveCurrentAIProfile:
            return "square.and.arrow.down"
        case .setDefaultModel(let model):
            return model.supportsReasoning ? "brain.head.profile" : "cpu"
        case .clearDefaultModel:
            return "arrow.counterclockwise"
        case .setThinkingLevel:
            return "slider.horizontal.3"
        case .setSearchQuery:
            return command.systemImage
        case .enableContext1M:
            return "text.page.badge.magnifyingglass"
        case .disableContext1M:
            return "text.page.slash"
        case .captureClipboard, .copyClipboardHistory:
            return "doc.on.clipboard"
        case .copyCalculatorResult:
            return "function"
        case .copyUnitConversionResult:
            return "arrow.left.arrow.right"
        case .clearClipboardHistory:
            return "trash"
        case .copySnippet:
            return "text.quote"
        case .runRecentCommand:
            return "clock.arrow.circlepath"
        case .runCommandAlias(let alias):
            return alias.systemImage
        case .openApplication:
            return "arrow.up.forward.app"
        case .openQuicklink:
            return "link"
        case .openPath(let target):
            return target.systemImage
        case .openWorkspaceFile(let file):
            return file.systemImage
        case .openInteractiveCLIAt:
            return "terminal"
        case .runShellCommand:
            return "terminal"
        case .runSystemCommand(let command):
            return command.systemImage
        case .runWindowCommand(let command):
            return command.systemImage
        case .runScript:
            return "play"
        case .openInteractiveCLI, .login:
            return "terminal"
        case .copyCommand:
            return "doc.on.doc"
        case .copyWorkspacePath:
            return "doc.on.doc"
        case .revealOAuthStore, .revealAIHistoryFile, .revealClipboardHistoryFile, .revealCLIContextsFolder, .revealScriptCommandsFolder, .revealWorkflowsFile, .revealQuicklinksFile, .revealPromptCommandsFile, .revealAIProfilesFile, .revealCommandAliasesFile, .revealSnippetsFile:
            return "folder"
        case .revealWorkspace:
            return "folder"
        case .reloadAIHistory, .reloadCLIContexts, .reloadScriptCommands, .reloadWorkflows, .reloadQuicklinks, .reloadPromptCommands, .reloadAIProfiles, .reloadCommandAliases, .reloadSnippets:
            return "arrow.clockwise"
        case .clearCLIContexts:
            return "trash"
        }
    }

    private static func prompt(
        for command: LauncherCommand,
        query: String,
        clipboard: String,
        context: LauncherContextSnapshot
    ) -> String {
        var lines = [
            "Explain this launcher result and suggest the most useful next actions.",
            "",
            "Title: \(command.title)",
            "Category: \(command.category.rawValue)",
            "Description: \(command.subtitle)",
        ]

        switch command.action {
        case .askPrompt(let prompt):
            lines.append("Prompt: \(prompt)")
        case .askContext(let kind):
            lines.append("Context prompt: \(kind.displayName)")
        case .askCLIContext(let record):
            lines.append("Captured terminal context: \(record.title)")
            lines.append("Path: \(record.path)")
            if let prompt = record.askPrompt.boundedPromptContext(maxLength: 8_000) {
                lines.append(contentsOf: ["", "Captured context prompt:", prompt])
            }
        case .runAIPreset(let preset):
            lines.append("Preset input: \(preset.inputSource.displayName)")
            lines.append("Preset instruction: \(preset.instruction)")
            let input = preset.input(query: query, clipboard: clipboard)
            if let renderedInput = input.boundedPromptContext(maxLength: 8_000) {
                lines.append(contentsOf: ["", "Resolved preset input:", renderedInput])
                if let renderedPresetPrompt = preset.prompt(input: input).boundedPromptContext(maxLength: 8_000) {
                    lines.append(contentsOf: ["", "Rendered preset prompt:", renderedPresetPrompt])
                }
            }
        case .runPromptCommand(let promptCommand):
            lines.append("Prompt command template: \(promptCommand.promptTemplate)")
            if let renderedPrompt = promptCommand
                .renderedPrompt(query: query, clipboard: clipboard, context: context)
                .boundedPromptContext(maxLength: 8_000) {
                lines.append(contentsOf: ["", "Rendered prompt:", renderedPrompt])
            }
        case .applyAIProfile(let profile):
            lines.append("AI profile: \(profile.title)")
            lines.append("Model: \(profile.modelDisplayName)")
            lines.append("Thinking: \(profile.thinking.displayName)")
            lines.append("1M context: \(profile.context1m ? "enabled" : "disabled")")
        case .saveCurrentAIProfile:
            lines.append("Creates an AI profile from the current launcher model, thinking, and 1M context defaults.")
            lines.append("AI profiles file: ~/.kwwk/launcher/profiles.json")
        case .setDefaultModel(let model):
            lines.append("Model ID: \(model.id)")
            lines.append("Provider: \(model.provider)")
            lines.append("API: \(model.api)")
            lines.append("Reasoning: \(model.supportsReasoning ? "supported" : "not advertised")")
        case .clearDefaultModel:
            lines.append("Model override: provider default")
        case .setThinkingLevel(let level):
            lines.append("Thinking level: \(level.displayName)")
            lines.append("CLI flag: --thinking \(level.rawValue)")
        case .setSearchQuery(let searchQuery):
            lines.append("Search query: \(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))")
        case .enableContext1M:
            lines.append("Context mode: Anthropic 1M context enabled")
            lines.append("CLI flag: --context-1m")
        case .disableContext1M:
            lines.append("Context mode: normal provider context")
        case .copyClipboardHistory(let record):
            lines.append("Clipboard text: \(record.text)")
        case .copyCalculatorResult(let result):
            lines.append("Expression: \(result.expression)")
            lines.append("Result: \(result.formattedValue)")
        case .copyUnitConversionResult(let result):
            lines.append("Conversion: \(result.expression)")
            lines.append("Result: \(result.formattedOutput)")
        case .copySnippet(let snippet):
            lines.append("Snippet template: \(snippet.textTemplate)")
            if let renderedText = snippet
                .renderedText(query: query, clipboard: clipboard, context: context)
                .boundedPromptContext(maxLength: 8_000) {
                lines.append(contentsOf: ["", "Rendered snippet:", renderedText])
            }
        case .openApplication(let path):
            lines.append("Application path: \(path)")
        case .openQuicklink(let quicklink):
            lines.append("Quicklink URL: \(quicklink.urlTemplate)")
            lines.append("Rendered URL: \(quicklink.renderedURLString(query: query))")
        case .openPath(let target):
            lines.append("\(target.kindName): \(target.displayPath)")
            lines.append("Path: \(target.path)")
        case .openInteractiveCLIAt(let path):
            lines.append("Workspace path: \(path)")
        case .revealWorkspace(let path), .copyWorkspacePath(let path):
            lines.append("Workspace path: \(path)")
        case .runShellCommand(let commandText):
            lines.append("Shell command: \(commandText)")
        case .runSystemCommand(let command):
            lines.append("System command: \(command.title)")
            lines.append("Command ID: \(LauncherSystemCommandCatalog.commandPrefix)\(command.id)")
        case .runWindowCommand(let command):
            lines.append("Window command: \(command.title)")
            lines.append("Command ID: \(LauncherWindowCommandCatalog.commandPrefix)\(command.id)")
        case .openWorkspaceFile(let file):
            lines.append("Workspace file: \(file.relativePath)")
            lines.append("File path: \(file.path)")
        case .runScript(let script):
            lines.append("Script path: \(script.scriptPath)")
            lines.append("Query handling: \(script.argumentMode.rawValue)")
        case .runWorkflow(let workflow):
            lines.append("Workflow ID: \(workflow.id)")
            lines.append("Steps: \(workflow.steps.count)")
            lines.append(workflow.runtimeDescription)
            if let preview = workflow
                .previewText(query: query, clipboard: clipboard, context: context)
                .boundedPromptContext(maxLength: 8_000) {
                lines.append(contentsOf: ["", "Rendered workflow:", preview])
            }
        case .rerunPrompt(let prompt):
            lines.append("Original prompt: \(prompt)")
        case .rerunAIHistory(let record):
            lines.append("Original prompt: \(record.prompt)")
            lines.append("Exit code: \(record.exitCode)")
            if let model = record.model {
                lines.append("Model: \(model)")
            }
            if let workingDirectory = record.workingDirectory {
                lines.append("Working directory: \(workingDirectory)")
            }
            if let output = record.output.boundedPromptContext(maxLength: 8_000) {
                lines.append(contentsOf: ["", "Previous answer:", output])
            }
            if let errorOutput = record.errorOutput.boundedPromptContext(maxLength: 8_000) {
                lines.append(contentsOf: ["", "Previous error output:", errorOutput])
            }
        case .runRecentCommand(let commandId):
            lines.append("Original command ID: \(commandId)")
        case .runCommandAlias(let alias):
            lines.append("Target command ID: \(alias.targetCommandId)")
        case .copyCommand(let commandText):
            lines.append("Shell command: \(commandText)")
        case .revealAIHistoryFile, .reloadAIHistory:
            lines.append("AI history file: ~/.kwwk/launcher/ai-history.json")
        case .revealClipboardHistoryFile, .clearClipboardHistory:
            lines.append("Clipboard history file: ~/.kwwk/launcher/clipboard-history.json")
        case .revealCLIContextsFolder, .reloadCLIContexts, .clearCLIContexts:
            lines.append("Terminal contexts folder: ~/.kwwk/launcher/context")
        case .revealScriptCommandsFolder, .reloadScriptCommands:
            lines.append("Script commands folder: ~/.kwwk/launcher/commands")
        case .revealWorkflowsFile, .reloadWorkflows:
            lines.append("Workflows file: ~/.kwwk/launcher/workflows.json")
        case .revealQuicklinksFile, .reloadQuicklinks:
            lines.append("Quicklinks file: ~/.kwwk/launcher/quicklinks.json")
        case .revealPromptCommandsFile, .reloadPromptCommands:
            lines.append("AI prompt commands file: ~/.kwwk/launcher/prompts.json")
        case .revealAIProfilesFile, .reloadAIProfiles:
            lines.append("AI profiles file: ~/.kwwk/launcher/profiles.json")
        case .revealCommandAliasesFile, .reloadCommandAliases:
            lines.append("Command aliases file: ~/.kwwk/launcher/aliases.json")
        case .revealSnippetsFile, .reloadSnippets:
            lines.append("Snippets file: ~/.kwwk/launcher/snippets.json")
        default:
            break
        }

        return lines.joined(separator: "\n")
    }

    public static func launcherCommand(for command: LauncherCommand, query: String = "") -> String {
        switch command.action {
        case .setSearchQuery(let searchQuery):
            let trimmedSearchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedSearchQuery.isEmpty
                ? "kwwk launcher"
                : ["kwwk", "launcher", KWWKShellCommand.quote(trimmedSearchQuery)].joined(separator: " ")
        case .askPrompt(let prompt):
            return "kwwk launcher --ask \(KWWKShellCommand.quote(prompt))"
        case .runShellCommand(let commandText):
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
                "--",
                KWWKShellCommand.quote("$ \(commandText)"),
            ].joined(separator: " ")
        case .askAI, .askClipboard, .askContext, .runAIPreset:
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
            ].joined(separator: " ")
        case .askCLIContext:
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
            ].joined(separator: " ")
        case .applyAIProfile, .saveCurrentAIProfile, .setDefaultModel, .clearDefaultModel, .setThinkingLevel, .enableContext1M, .disableContext1M, .captureClipboard, .clearClipboardHistory, .copyClipboardHistory:
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
            ].joined(separator: " ")
        case .copyCalculatorResult(let result):
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
                "--",
                KWWKShellCommand.quote("=\(result.expression)"),
            ].joined(separator: " ")
        case .copyUnitConversionResult(let result):
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
                "--",
                KWWKShellCommand.quote(result.expression),
            ].joined(separator: " ")
        case .runPromptCommand(let promptCommand):
            let argument = promptCommand.argument(from: query)
            let queryArgument = argument.isEmpty ? "<query>" : argument
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
                "--",
                KWWKShellCommand.quote(queryArgument),
            ].joined(separator: " ")
        case .runWorkflow(let workflow):
            let argument = workflow.argument(from: query)
            let queryArgument = argument.isEmpty ? "<query>" : argument
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
                "--",
                KWWKShellCommand.quote(queryArgument),
            ].joined(separator: " ")
        case .runScript(let script):
            return LauncherScriptCommandExport.launcherCommand(for: script, query: query)
        case .copySnippet(let snippet):
            let argument = snippet.argument(from: query)
            let queryArgument = argument.isEmpty ? "<query>" : argument
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
                "--",
                KWWKShellCommand.quote(queryArgument),
            ].joined(separator: " ")
        case .runRecentCommand(let commandId):
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(commandId),
                "--run",
            ].joined(separator: " ")
        case .openQuicklink(let quicklink):
            if let replayQuery = LauncherWebCommandFactory.replayQuery(for: command) {
                return [
                    "kwwk",
                    "launcher",
                    "--command",
                    KWWKShellCommand.quote(command.id),
                    "--run",
                    "--",
                    KWWKShellCommand.quote(replayQuery),
                ].joined(separator: " ")
            }
            let argument = quicklink.argument(from: query)
            let queryArgument = argument.isEmpty ? "<query>" : argument
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
                "--",
                KWWKShellCommand.quote(queryArgument),
            ].joined(separator: " ")
        case .openPath(let target):
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
                "--",
                KWWKShellCommand.quote(target.path),
            ].joined(separator: " ")
        default:
            return [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(command.id),
                "--run",
            ].joined(separator: " ")
        }
    }

    public static func launcherURL(
        for command: LauncherCommand,
        query: String = "",
        workingDirectory: String? = nil
    ) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWorkingDirectory = workingDirectory?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        switch command.action {
        case .setSearchQuery(let searchQuery):
            return LauncherDeepLinkRequest(
                query: searchQuery,
                runImmediately: false,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .askPrompt(let prompt):
            return LauncherDeepLinkRequest(
                mode: .ask,
                query: prompt,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .askAI, .askClipboard, .askContext, .runAIPreset:
            return LauncherDeepLinkRequest(
                query: trimmedQuery,
                commandId: command.id,
                runImmediately: false,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .askCLIContext:
            return LauncherDeepLinkRequest(
                query: trimmedQuery,
                commandId: command.id,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .runShellCommand(let commandText):
            return LauncherDeepLinkRequest(
                query: "$ \(commandText)",
                commandId: command.id,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .copyCalculatorResult(let result):
            return LauncherDeepLinkRequest(
                query: "=\(result.expression)",
                commandId: command.id,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .copyUnitConversionResult(let result):
            return LauncherDeepLinkRequest(
                query: result.expression,
                commandId: command.id,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .runPromptCommand(let promptCommand):
            let argument = promptCommand.argument(from: trimmedQuery)
            return LauncherDeepLinkRequest(
                query: argument,
                commandId: command.id,
                runImmediately: !argument.isEmpty,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .runWorkflow(let workflow):
            let argument = workflow.argument(from: trimmedQuery)
            return LauncherDeepLinkRequest(
                query: argument,
                commandId: command.id,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .runScript(let script):
            let argument = trimmedQuery.isEmpty ? nil : trimmedQuery
            return LauncherDeepLinkRequest(
                query: argument ?? "",
                commandId: command.id,
                runImmediately: argument != nil || script.argumentMode == .none,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .copySnippet(let snippet):
            let argument = snippet.argument(from: trimmedQuery)
            return LauncherDeepLinkRequest(
                query: argument,
                commandId: command.id,
                runImmediately: !argument.isEmpty,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .openQuicklink(let quicklink):
            let argument = LauncherWebCommandFactory.replayQuery(for: command)
                ?? quicklink.argument(from: trimmedQuery)
            return LauncherDeepLinkRequest(
                query: argument,
                commandId: command.id,
                runImmediately: !argument.isEmpty,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .openPath(let target):
            return LauncherDeepLinkRequest(
                query: target.path,
                commandId: command.id,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        case .runRecentCommand(let commandId):
            return LauncherDeepLinkRequest(
                commandId: commandId,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        default:
            return LauncherDeepLinkRequest(
                commandId: command.id,
                runImmediately: true,
                workingDirectory: normalizedWorkingDirectory
            ).url.absoluteString
        }
    }

    public static func inspectCommand(for command: LauncherCommand, query: String = "") -> String {
        var parts = [
            "kwwk",
            "launcher",
            "--inspect-command",
            "--command",
            KWWKShellCommand.quote(command.id),
            "--json",
        ]

        if let queryArgument = inspectQuery(for: command, query: query) {
            parts += ["--", KWWKShellCommand.quote(queryArgument)]
        }

        return parts.joined(separator: " ")
    }

    private static func inspectQuery(for command: LauncherCommand, query: String) -> String? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            return trimmedQuery
        }

        switch command.action {
        case .askPrompt(let prompt):
            return prompt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        case .runShellCommand(let commandText):
            return "$ \(commandText)"
        case .openQuicklink:
            return LauncherWebCommandFactory.replayQuery(for: command)
        case .copyCalculatorResult(let result):
            return "=\(result.expression)"
        case .copyUnitConversionResult(let result):
            return result.expression
        case .openPath(let target):
            return target.path
        default:
            return nil
        }
    }

    private static func scriptReplayArgument(for script: LauncherScriptCommand, query: String) -> String? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            return trimmedQuery
        }
        return script.argumentMode == .none ? nil : "<query>"
    }

    private static func historyActions(
        for record: AIRunHistoryRecord,
        context: HeadlessTerminalActionContext
    ) -> [LauncherActionItem] {
        var actions = [
            LauncherActionItem(
                id: "copy-output",
                title: record.succeeded ? "Copy Answer" : "Copy Error",
                subtitle: record.previewText.truncatedForActionSubtitle(maxLength: 72),
                systemImage: "doc.on.doc",
                kind: .copyText(record.previewText)
            ),
            LauncherActionItem(
                id: "copy-prompt",
                title: "Copy Prompt",
                subtitle: record.prompt.truncatedForActionSubtitle(maxLength: 72),
                systemImage: "text.quote",
                kind: .copyText(record.prompt)
            ),
            LauncherActionItem(
                id: "save-prompt-command",
                title: "Save as Prompt Command",
                subtitle: LauncherPromptCommandIndex.promptCommand(from: record).title,
                systemImage: "plus.square.on.square",
                kind: .savePromptCommand(record)
            ),
        ]

        if let snippet = LauncherSnippetIndex.snippet(fromAIHistoryOutput: record) {
            actions.append(LauncherActionItem(
                id: "save-answer-snippet",
                title: record.succeeded ? "Save Answer as Snippet" : "Save Error as Snippet",
                subtitle: snippet.title,
                systemImage: "text.quote",
                kind: .saveSnippet(snippet)
            ))
        }

        actions.append(saveWorkflowAction(LauncherWorkflowIndex.workflow(from: record)))

        actions.append(interactiveDraftAction(
                prompt: record.prompt,
                context: context,
                model: record.model,
                workingDirectory: record.workingDirectory
        ))

        if !record.command.isEmpty {
            actions.append(LauncherActionItem(
                id: "copy-command",
                title: "Copy CLI Command",
                subtitle: record.command,
                systemImage: "terminal",
                kind: .copyText(record.command)
            ))
        }

        if !record.terminalReplayCommand.isEmpty {
            actions.append(LauncherActionItem(
                id: "open-terminal",
                title: "Open in Terminal",
                subtitle: record.terminalReplayCommand.truncatedForActionSubtitle(maxLength: 72),
                systemImage: "terminal",
                kind: .openTerminalCommand(record.terminalReplayCommand)
            ))
        }

        return actions
    }

    private static func workspaceActions(for path: String) -> [LauncherActionItem] {
        [
            LauncherActionItem(
                id: "reveal",
                title: "Reveal in Finder",
                subtitle: path,
                systemImage: "folder",
                kind: .revealPath(path)
            ),
            LauncherActionItem(
                id: "copy-path",
                title: "Copy Path",
                subtitle: path,
                systemImage: "doc.on.doc",
                kind: .copyText(path)
            ),
        ]
    }

    private static func headlessTerminalAction(
        prompt: String,
        context: HeadlessTerminalActionContext
    ) -> LauncherActionItem {
        let command = KWWKCLIInvocation.headlessTerminalCommand(
            prompt: prompt,
            executable: context.executable,
            thinking: context.thinking,
            model: context.model.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            context1m: context.context1m,
            workingDirectory: context.workingDirectory
        )
        return LauncherActionItem(
            id: "open-terminal",
            title: "Open in Terminal",
            subtitle: command.truncatedForActionSubtitle(maxLength: 72),
            systemImage: "terminal",
            kind: .openTerminalCommand(command)
        )
    }

    private static func interactiveDraftAction(
        prompt: String,
        context: HeadlessTerminalActionContext,
        model: String? = nil,
        workingDirectory: String? = nil
    ) -> LauncherActionItem {
        let command = KWWKCLIInvocation.interactiveDraftTerminalCommand(
            prompt: prompt,
            executable: context.executable,
            thinking: context.thinking,
            model: model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? context.model.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            context1m: context.context1m,
            workingDirectory: workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? context.workingDirectory
        )
        return LauncherActionItem(
            id: "open-cli-draft",
            title: "Open Draft in CLI",
            subtitle: command.truncatedForActionSubtitle(maxLength: 72),
            systemImage: "terminal",
            kind: .openTerminalCommand(command)
        )
    }

    private static func saveWorkflowAction(_ workflow: LauncherWorkflow) -> LauncherActionItem {
        LauncherActionItem(
            id: "save-workflow",
            title: "Save as Workflow",
            subtitle: "~/.kwwk/launcher/workflows.json",
            systemImage: "point.3.connected.trianglepath.dotted",
            kind: .saveWorkflow(workflow)
        )
    }
}

private extension String {
    func truncatedForActionSubtitle(maxLength: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<end]) + "..."
    }

    func boundedPromptContext(maxLength: Int) -> String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > maxLength else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<end]) + "\n\n[truncated]"
    }

    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct HeadlessTerminalActionContext {
    var executable: String
    var thinking: KWWKThinkingLevel
    var model: String
    var context1m: Bool
    var workingDirectory: String?
}
