import Foundation

public enum LauncherCommandPreview {
    public static func text(
        for command: LauncherCommand,
        query: String = "",
        clipboard: String = "",
        context: LauncherContextSnapshot = LauncherContextSnapshot(),
        workingDirectory: String? = nil,
        availableCommands: [LauncherCommand] = [],
        targetApplicationName: String? = nil
    ) -> String {
        let prompt = LauncherCommandFilter.promptText(from: query)

        switch command.action {
        case .runRecentCommand(let commandId):
            if let original = availableCommands.first(where: { $0.id == commandId }) {
                return [
                    original.title,
                    "",
                    original.subtitle,
                    "",
                    original.keywords.joined(separator: "  "),
                ].joined(separator: "\n")
            }
        case .runCommandAlias(let alias):
            if let target = availableCommands.first(where: { $0.id == alias.targetCommandId }) {
                return [
                    target.title,
                    "",
                    target.subtitle,
                    "",
                    "Alias target: \(alias.targetCommandId)",
                ].joined(separator: "\n")
            }
        case .runScript(let script):
            var preview = script.previewText
            if script.workingDirectory == nil, let workingDirectory {
                preview += "\n\nRuns in active workspace:\n\(workingDirectory)"
            }
            return preview
        case .openQuicklink(let quicklink):
            return quicklink.previewText(query: prompt)
        case .runAIPreset(let preset):
            return preset.previewText
        case .runPromptCommand(let promptCommand):
            return promptCommand.previewText(query: prompt, clipboard: clipboard, context: context)
        case .runWorkflow(let workflow):
            return workflow.previewText(query: prompt, clipboard: clipboard, context: context)
        case .applyAIProfile(let profile):
            return [
                profile.title,
                "",
                "Model: \(profile.modelDisplayName)",
                "Thinking: \(profile.thinking.displayName)",
                "1M context: \(profile.context1m ? "enabled" : "disabled")",
            ].joined(separator: "\n")
        case .setDefaultModel(let model):
            return [
                model.name,
                "",
                "Model ID: \(model.id)",
                "Provider: \(model.provider)",
                "API: \(model.api)",
            ].joined(separator: "\n")
        case .clearDefaultModel:
            return "Clear the launcher model override and let the active provider choose its default model."
        case .setThinkingLevel(let level):
            return "Thinking: \(level.displayName)\n\nSets the default --thinking \(level.rawValue) flag for launcher AI runs."
        case .setSearchQuery(let searchQuery):
            let trimmedSearchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command.subtitle)\n\nQuery: \(trimmedSearchQuery)"
        case .enableContext1M:
            return "1M context enabled\n\nAdds --context-1m to launcher AI runs."
        case .disableContext1M:
            return "Normal context\n\nRemoves --context-1m from launcher AI runs."
        case .copyClipboardHistory(let record):
            return record.previewText
        case .copyCalculatorResult(let result):
            return "\(result.expression)\n\n= \(result.formattedValue)"
        case .copyUnitConversionResult(let result):
            return "\(result.expression)\n\n= \(result.formattedOutput)"
        case .copySnippet(let snippet):
            return snippet.previewText(query: prompt, clipboard: clipboard, context: context)
        case .askPrompt(let prompt):
            return prompt
        case .askContext(let kind):
            return LauncherContextPromptBuilder.preview(for: kind, context: context)
        case .askCLIContext(let record):
            return record.previewText
        case .openWorkspaceFile(let file):
            return file.previewText
        case .openPath(let target):
            return target.previewText
        case .runShellCommand(let commandText):
            return KWWKShellCommand.terminalCommand(commandText, workingDirectory: workingDirectory)
        case .runSystemCommand(let systemCommand):
            return "\(systemCommand.title)\n\n\(systemCommand.subtitle)\n\nCategory: System"
        case .runWindowCommand(let windowCommand):
            let target = targetApplicationName?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "the previous app"
            return "\(windowCommand.title)\n\n\(windowCommand.subtitle)\n\nTarget: \(target)"
        case .rerunAIHistory(let record):
            let result = record.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = record.model.map { "\($0)\n" } ?? ""
            return "\(record.prompt)\n\n\(model)\(result)"
        default:
            break
        }

        return "\(command.subtitle)\n\n\(command.keywords.joined(separator: "  "))"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
