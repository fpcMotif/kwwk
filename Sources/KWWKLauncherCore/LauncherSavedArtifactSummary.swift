import Foundation

public enum LauncherSavedArtifactSummary {
    public static func text(
        promptCommand: LauncherPromptCommand,
        path: URL = LauncherPromptCommandIndex.defaultURL()
    ) -> String {
        let export = LauncherPromptCommandExportRecord(promptCommand: promptCommand)
        let command = LauncherPromptCommandIndex.commands(for: [promptCommand]).first
        return summary(
            title: export.title,
            path: path,
            commandId: export.commandId,
            launcherCommand: export.launcherCommand,
            launcherURL: command.map { LauncherActionCatalog.launcherURL(for: $0) }
        )
    }

    public static func text(
        snippet: LauncherSnippet,
        path: URL = LauncherSnippetIndex.defaultURL()
    ) -> String {
        let export = LauncherSnippetExportRecord(snippet: snippet)
        let command = LauncherSnippetIndex.commands(for: [snippet]).first
        return summary(
            title: export.title,
            path: path,
            commandId: export.commandId,
            launcherCommand: export.launcherCommand,
            launcherURL: command.map { LauncherActionCatalog.launcherURL(for: $0) }
        )
    }

    public static func text(
        quicklink: LauncherQuicklink,
        path: URL = LauncherQuicklinkIndex.defaultURL()
    ) -> String {
        let export = LauncherQuicklinkExportRecord(quicklink: quicklink)
        let command = LauncherQuicklinkIndex.commands(for: [quicklink]).first
        return summary(
            title: export.title,
            path: path,
            commandId: export.commandId,
            launcherCommand: export.launcherCommand,
            launcherURL: command.map { LauncherActionCatalog.launcherURL(for: $0) }
        )
    }

    public static func text(
        alias: LauncherCommandAlias,
        path: URL = LauncherCommandAliasIndex.defaultURL()
    ) -> String {
        let export = LauncherCommandAliasExportRecord(alias: alias)
        let command = LauncherCommand(
            id: export.commandId,
            title: alias.title,
            subtitle: alias.subtitle.isEmpty ? alias.targetCommandId : alias.subtitle,
            systemImage: alias.systemImage,
            category: .alias,
            keywords: alias.keywords,
            action: .runCommandAlias(alias)
        )
        return summary(
            title: export.title,
            path: path,
            commandId: export.commandId,
            launcherCommand: export.launcherCommand,
            launcherURL: LauncherActionCatalog.launcherURL(for: command)
        )
    }

    public static func text(
        script: LauncherScriptCommand,
        path: URL
    ) -> String {
        let export = LauncherScriptCommandExportRecord(script: script)
        let command = LauncherScriptCommandIndex.commands(for: [script]).first
        return summary(
            title: export.title,
            path: path,
            commandId: export.commandId,
            launcherCommand: export.launcherCommand,
            launcherURL: command.map { LauncherActionCatalog.launcherURL(for: $0) }
        )
    }

    public static func text(
        workflow: LauncherWorkflow,
        path: URL = LauncherWorkflowIndex.defaultURL()
    ) -> String {
        let commandId = "workflow:\(workflow.id)"
        let command = LauncherWorkflowIndex.commands(for: [workflow]).first
        let launcherCommand = command.map { LauncherActionCatalog.launcherCommand(for: $0) }
            ?? [
                "kwwk",
                "launcher",
                "--command",
                KWWKShellCommand.quote(commandId),
                "--run",
                "--",
                KWWKShellCommand.quote("<query>"),
            ].joined(separator: " ")

        return summary(
            title: workflow.title,
            path: path,
            commandId: commandId,
            launcherCommand: launcherCommand,
            launcherURL: command.map { LauncherActionCatalog.launcherURL(for: $0) },
            extraFields: [("CLI command", workflow.cliCommand())]
        )
    }

    private static func summary(
        title: String,
        path: URL,
        commandId: String,
        launcherCommand: String,
        launcherURL: String? = nil,
        extraFields: [(String, String)] = []
    ) -> String {
        var lines = [
            title,
            "",
            "Saved to:",
            path.standardizedFileURL.path,
            "",
            "Command ID:",
            commandId,
            "",
            "Launcher command:",
            launcherCommand,
        ]
        if let launcherURL {
            lines += [
                "",
                "Launcher URL:",
                launcherURL,
            ]
        }

        for (label, value) in extraFields {
            lines += [
                "",
                "\(label):",
                value,
            ]
        }

        return lines.joined(separator: "\n")
    }
}
