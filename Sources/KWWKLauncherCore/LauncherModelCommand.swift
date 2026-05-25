import Foundation

public struct LauncherModelCommand: Codable, Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var provider: String
    public var api: String
    public var supportsReasoning: Bool
    public var keywords: [String]

    public init(
        id: String,
        name: String,
        provider: String,
        api: String,
        supportsReasoning: Bool,
        keywords: [String] = []
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.api = api
        self.supportsReasoning = supportsReasoning
        self.keywords = keywords
    }
}

public enum LauncherModelCommandCatalog {
    public static let commandPrefix = "model:"

    public static let curatedModels: [LauncherModelCommand] = [
        LauncherModelCommand(
            id: "gpt-5.4",
            name: "GPT-5.4",
            provider: "OpenAI",
            api: "Responses",
            supportsReasoning: true,
            keywords: ["openai", "codex", "responses", "reasoning", "gpt"]
        ),
        LauncherModelCommand(
            id: "gpt-5",
            name: "GPT-5",
            provider: "OpenAI",
            api: "Responses",
            supportsReasoning: true,
            keywords: ["openai", "responses", "reasoning", "gpt"]
        ),
        LauncherModelCommand(
            id: "gpt-4.1",
            name: "GPT-4.1",
            provider: "OpenAI",
            api: "Chat Completions",
            supportsReasoning: false,
            keywords: ["openai", "chat", "completions", "gpt"]
        ),
        LauncherModelCommand(
            id: "claude-sonnet-4-5-20250929",
            name: "Claude Sonnet 4.5",
            provider: "Anthropic",
            api: "Messages",
            supportsReasoning: true,
            keywords: ["anthropic", "claude", "sonnet", "reasoning"]
        ),
        LauncherModelCommand(
            id: "claude-haiku-4-5-20251001",
            name: "Claude Haiku 4.5",
            provider: "Anthropic",
            api: "Messages",
            supportsReasoning: false,
            keywords: ["anthropic", "claude", "haiku", "fast"]
        ),
        LauncherModelCommand(
            id: "gemini-2.5-pro",
            name: "Gemini 2.5 Pro",
            provider: "Google",
            api: "Generative AI",
            supportsReasoning: true,
            keywords: ["google", "gemini", "reasoning"]
        ),
        LauncherModelCommand(
            id: "gemini-2.5-flash",
            name: "Gemini 2.5 Flash",
            provider: "Google",
            api: "Generative AI",
            supportsReasoning: true,
            keywords: ["google", "gemini", "flash", "fast"]
        ),
    ]

    public static func commands(models: [LauncherModelCommand] = curatedModels) -> [LauncherCommand] {
        [clearCommand()] + models.map(command(for:))
    }

    public static func command(for model: LauncherModelCommand) -> LauncherCommand {
        LauncherCommand(
            id: "\(commandPrefix)\(model.id)",
            title: "Use \(model.name)",
            subtitle: "\(model.provider) \(model.api) - \(model.id)",
            systemImage: model.supportsReasoning ? "brain.head.profile" : "cpu",
            category: .model,
            keywords: keywordSet(values: [
                "ai",
                "model",
                "models",
                "provider",
                "select",
                "default",
                model.id,
                model.name,
                model.provider,
                model.api,
            ] + model.keywords),
            action: .setDefaultModel(model)
        )
    }

    public static func clearCommand() -> LauncherCommand {
        LauncherCommand(
            id: "model:provider-default",
            title: "Use Provider Default Model",
            subtitle: "Clear the launcher model override",
            systemImage: "arrow.counterclockwise",
            category: .model,
            keywords: ["ai", "model", "models", "provider", "default", "clear", "reset", "override"],
            action: .clearDefaultModel
        )
    }

    public static func modelId(for commandId: LauncherCommand.ID) -> String? {
        guard commandId.hasPrefix(commandPrefix) else { return nil }
        let id = String(commandId.dropFirst(commandPrefix.count))
        return id == "provider-default" ? nil : id
    }

    private static func keywordSet(values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}
