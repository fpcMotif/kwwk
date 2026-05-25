import Foundation

public enum LauncherResidentCommandCatalog {
    public static func commands(
        aiHistory: AIRunHistory = AIRunHistoryStore.load(),
        clipboardHistory: LauncherClipboardHistory = LauncherClipboardHistoryStore.load(),
        aiProfiles: [LauncherAIProfile] = LauncherAIProfileIndex.load(),
        promptCommands: [LauncherPromptCommand] = LauncherPromptCommandIndex.load(),
        workflows: [LauncherWorkflow] = LauncherWorkflowIndex.load(),
        cliContexts: [LauncherCLIContextRecord] = LauncherCLIContextIndex.scan(),
        quicklinks: [LauncherQuicklink] = LauncherQuicklinkIndex.load(),
        snippets: [LauncherSnippet] = LauncherSnippetIndex.load(),
        scripts: [LauncherScriptCommand] = LauncherScriptCommandIndex.scan(
            roots: LauncherScriptCommandIndex.defaultRoots()
        ),
        applications: [IndexedApplication] = ApplicationIndex.scan(roots: ApplicationIndex.defaultRoots()),
        aliases: [LauncherCommandAlias] = LauncherCommandAliasIndex.load()
    ) -> [LauncherCommand] {
        var commands = LauncherCommandCatalog.defaults
        commands += AIRunHistoryCommandFactory.commands(for: aiHistory)
        commands += LauncherClipboardHistoryCommandFactory.commands(for: clipboardHistory)
        commands += LauncherAIProfileCatalog.commands(
            for: aiProfiles,
            reservedCommandIds: LauncherAIProfileCatalog.defaultCommandIds
        )
        commands += LauncherPromptCommandIndex.commands(for: promptCommands)
        commands += LauncherWorkflowIndex.commands(for: workflows)
        commands += LauncherCLIContextIndex.commands(for: cliContexts)
        commands += LauncherQuicklinkIndex.commands(for: quicklinks)
        commands += LauncherSnippetIndex.commands(for: snippets)
        commands += LauncherScriptCommandIndex.commands(for: scripts)
        commands += ApplicationIndex.commands(for: applications)
        commands += LauncherCommandAliasIndex.commands(
            for: aliases,
            availableCommands: commands
        )
        return commands
    }
}
