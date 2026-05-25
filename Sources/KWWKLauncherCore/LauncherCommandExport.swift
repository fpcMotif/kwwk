import Foundation

public struct LauncherCommandExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var category: String
    public var title: String
    public var subtitle: String
    public var launcherCommand: String
    public var launcherURL: String

    public init(command: LauncherCommand, query: String = "", workingDirectory: String? = nil) {
        id = command.id
        category = command.category.rawValue
        title = command.title
        subtitle = command.subtitle
        launcherCommand = LauncherActionCatalog.launcherCommand(for: command, query: query)
        launcherURL = LauncherActionCatalog.launcherURL(
            for: command,
            query: query,
            workingDirectory: workingDirectory
        )
    }
}

public struct LauncherActionExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: String
    public var value: String?
    public var launcherCommand: String?
    public var launcherURL: String?

    public init(
        action: LauncherActionItem,
        launcherCommand: String? = nil,
        launcherURL: String? = nil
    ) {
        id = action.id
        title = action.title
        subtitle = action.subtitle
        self.launcherCommand = launcherCommand
        self.launcherURL = launcherURL

        switch action.kind {
        case .runPrimary:
            kind = "runPrimary"
            value = nil
        case .toggleFavorite:
            kind = "toggleFavorite"
            value = nil
        case .askKWWK(let prompt):
            kind = "askKWWK"
            value = prompt
        case .copyText(let text):
            kind = "copyText"
            value = text
        case .openTerminalCommand(let command):
            kind = "openTerminalCommand"
            value = command
        case .revealPath(let path):
            kind = "revealPath"
            value = path
        case .trashPath(let path):
            kind = "trashPath"
            value = path
        case .savePromptCommand(let record):
            kind = "savePromptCommand"
            value = record.prompt
        case .savePromptTemplate(let prompt):
            kind = "savePromptCommand"
            value = prompt.promptTemplate
        case .saveSnippet(let snippet):
            kind = "saveSnippet"
            value = snippet.textTemplate
        case .saveQuicklink(let quicklink):
            kind = "saveQuicklink"
            value = quicklink.urlTemplate
        case .saveCommandAlias(let alias):
            kind = "saveCommandAlias"
            value = alias.targetCommandId
        case .saveScriptCommand(let draft):
            kind = "saveScriptCommand"
            value = draft.commandText
        case .saveWorkflow(let workflow):
            kind = "saveWorkflow"
            value = workflow.cliCommand()
        }
    }
}

public struct LauncherCommandDetailExportRecord: Codable, Sendable, Hashable {
    public var id: String
    public var category: String
    public var title: String
    public var subtitle: String
    public var primaryActionTitle: String
    public var preview: String
    public var launcherCommand: String
    public var launcherURL: String
    public var featuredActions: [LauncherActionExportRecord]

    public init(
        command: LauncherCommand,
        preview: String,
        featuredActions: [LauncherActionItem],
        query: String = "",
        workingDirectory: String? = nil
    ) {
        id = command.id
        category = command.category.rawValue
        title = command.title
        subtitle = command.subtitle
        primaryActionTitle = LauncherActionCatalog.primaryTitle(for: command)
        self.preview = preview
        launcherCommand = LauncherActionCatalog.launcherCommand(for: command, query: query)
        launcherURL = LauncherActionCatalog.launcherURL(
            for: command,
            query: query,
            workingDirectory: workingDirectory
        )
        self.featuredActions = LauncherActionExport.records(
            for: featuredActions,
            command: command,
            query: query,
            workingDirectory: workingDirectory
        )
    }
}

public enum LauncherCommandExport {
    public static func records(
        for commands: [LauncherCommand],
        query: String = "",
        workingDirectory: String? = nil
    ) -> [LauncherCommandExportRecord] {
        commands
            .map {
                LauncherCommandExportRecord(
                    command: $0,
                    query: query,
                    workingDirectory: workingDirectory
                )
            }
            .sorted { lhs, rhs in
                if lhs.category != rhs.category {
                    return lhs.category.localizedStandardCompare(rhs.category) == .orderedAscending
                }
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            }
    }

    public static func table(for commands: [LauncherCommand]) -> String {
        let rows = records(for: commands)
        guard !rows.isEmpty else { return "" }
        return rows
            .map { "\($0.id)\t\($0.category)\t\($0.title)\t\($0.subtitle)" }
            .joined(separator: "\n")
    }

    public static func json(
        for commands: [LauncherCommand],
        query: String = "",
        workingDirectory: String? = nil
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(
            for: commands,
            query: query,
            workingDirectory: workingDirectory
        ))
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

public enum LauncherCommandDetailExport {
    public static func text(for record: LauncherCommandDetailExportRecord) -> String {
        var lines = [
            "id: \(record.id)",
            "category: \(record.category)",
            "title: \(record.title)",
            "subtitle: \(record.subtitle)",
            "primary: \(record.primaryActionTitle)",
            "launcherCommand: \(record.launcherCommand)",
            "launcherURL: \(record.launcherURL)",
            "",
            "preview:",
            record.preview,
        ]

        if !record.featuredActions.isEmpty {
            lines += [
                "",
                "featuredActions:",
            ]
            lines += record.featuredActions.map { action in
                let launcherCommand = action.launcherCommand.map { " -> \($0)" } ?? ""
                return "- \(action.id): \(action.title) [\(action.kind)]\(launcherCommand)"
            }
        }

        return lines.joined(separator: "\n")
    }

    public static func json(for record: LauncherCommandDetailExportRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

public enum LauncherActionExport {
    public static func records(for actions: [LauncherActionItem]) -> [LauncherActionExportRecord] {
        actions.map { LauncherActionExportRecord(action: $0) }
    }

    public static func records(
        for actions: [LauncherActionItem],
        command: LauncherCommand,
        query: String = "",
        workingDirectory: String? = nil
    ) -> [LauncherActionExportRecord] {
        actions.map { action in
            LauncherActionExportRecord(
                action: action,
                launcherCommand: launcherCommand(for: action, command: command, query: query),
                launcherURL: launcherURL(
                    for: action,
                    command: command,
                    query: query,
                    workingDirectory: workingDirectory
                )
            )
        }
    }

    public static func table(for actions: [LauncherActionItem]) -> String {
        let rows = records(for: actions)
        guard !rows.isEmpty else { return "" }
        return rows
            .map { "\($0.id)\t\($0.kind)\t\($0.title)\t\($0.subtitle)" }
            .joined(separator: "\n")
    }

    public static func table(
        for actions: [LauncherActionItem],
        command: LauncherCommand,
        query: String = "",
        workingDirectory: String? = nil
    ) -> String {
        let rows = records(
            for: actions,
            command: command,
            query: query,
            workingDirectory: workingDirectory
        )
        guard !rows.isEmpty else { return "" }
        return rows
            .map {
                "\($0.id)\t\($0.kind)\t\($0.title)\t\($0.subtitle)\t\($0.launcherCommand ?? "")"
            }
            .joined(separator: "\n")
    }

    public static func json(for actions: [LauncherActionItem]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(for: actions))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    public static func json(
        for actions: [LauncherActionItem],
        command: LauncherCommand,
        query: String = "",
        workingDirectory: String? = nil
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records(
            for: actions,
            command: command,
            query: query,
            workingDirectory: workingDirectory
        ))
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func launcherCommand(
        for action: LauncherActionItem,
        command: LauncherCommand,
        query: String
    ) -> String {
        var parts = [
            "kwwk",
            "launcher",
            "--command",
            KWWKShellCommand.quote(command.id),
            "--action",
            KWWKShellCommand.quote(action.id),
            "--run",
        ]
        if let argument = replayArgument(for: command, query: query) {
            parts += ["--", KWWKShellCommand.quote(argument)]
        }
        return parts.joined(separator: " ")
    }

    private static func launcherURL(
        for action: LauncherActionItem,
        command: LauncherCommand,
        query: String,
        workingDirectory: String?
    ) -> String {
        var deepLinkQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if deepLinkQuery.isEmpty, let argument = replayArgument(for: command, query: query) {
            deepLinkQuery = argument
        }

        return LauncherDeepLinkRequest(
            query: deepLinkQuery,
            commandId: command.id,
            actionId: action.id,
            runImmediately: true,
            workingDirectory: workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ).url.absoluteString
    }

    private static func replayArgument(for command: LauncherCommand, query: String) -> String? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch command.action {
        case .askAI, .askContext, .runAIPreset:
            return trimmedQuery.isEmpty ? nil : trimmedQuery
        case .askCLIContext:
            return nil
        case .askPrompt(let prompt):
            let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedPrompt.isEmpty ? nil : trimmedPrompt
        case .runShellCommand(let commandText):
            return "$ \(commandText)"
        case .copyCalculatorResult(let result):
            return "=\(result.expression)"
        case .copyUnitConversionResult(let result):
            return result.expression
        case .runPromptCommand(let promptCommand):
            let argument = promptCommand.argument(from: trimmedQuery)
            return argument.isEmpty ? "<query>" : argument
        case .runWorkflow(let workflow):
            let argument = workflow.argument(from: trimmedQuery)
            return argument.isEmpty ? "<query>" : argument
        case .runScript(let script):
            if !trimmedQuery.isEmpty {
                return trimmedQuery
            }
            return script.argumentMode == .none ? nil : "<query>"
        case .copySnippet(let snippet):
            let argument = snippet.argument(from: trimmedQuery)
            return argument.isEmpty ? "<query>" : argument
        case .openQuicklink(let quicklink):
            if let replayQuery = LauncherWebCommandFactory.replayQuery(for: command) {
                return replayQuery
            }
            let argument = quicklink.argument(from: trimmedQuery)
            return argument.isEmpty ? "<query>" : argument
        case .openPath(let target):
            return target.path
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
