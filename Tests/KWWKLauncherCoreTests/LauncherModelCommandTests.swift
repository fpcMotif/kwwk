import KWWKLauncherCore
import Testing

@Suite("Launcher model commands")
struct LauncherModelCommandTests {
    @Test
    func curatedModelsBecomeSearchableLauncherCommands() throws {
        let commands = LauncherModelCommandCatalog.commands()
        let gpt = try #require(commands.first { $0.id == "model:gpt-5.4" })

        #expect(commands.first?.id == "model:provider-default")
        #expect(gpt.title == "Use GPT-5.4")
        #expect(gpt.category == .model)
        #expect(gpt.keywords.contains("codex"))
        #expect(gpt.action == .setDefaultModel(LauncherModelCommand(
            id: "gpt-5.4",
            name: "GPT-5.4",
            provider: "OpenAI",
            api: "Responses",
            supportsReasoning: true,
            keywords: ["openai", "codex", "responses", "reasoning", "gpt"]
        )))
    }

    @Test
    func modelScopeFiltersInsideModelCategory() throws {
        let results = LauncherCommandFilter.filter(
            LauncherCommandCatalog.defaults,
            query: "@models claude"
        )

        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .model })
        #expect(results.first?.id == "model:claude-haiku-4-5-20251001")
    }

    @Test
    func modelActionsExposeIdsFlagsAndReplayableLauncherCommands() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "model:gpt-5.4" })
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Use Model")
        #expect(actions.first { $0.id == "copy-model-id" }?.kind == .copyText("gpt-5.4"))
        #expect(actions.first { $0.id == "copy-model-flag" }?.kind == .copyText("--model gpt-5.4"))
        #expect(actions.first { $0.id == "copy-headless-command" }?.kind == .copyText(
            "kwwk --model gpt-5.4 -p '<prompt>'"
        ))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command model:gpt-5.4 --run"
        ))
    }

    @Test
    func clearModelCommandUsesProviderDefault() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "model:provider-default" })
        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(command.action == .clearDefaultModel)
        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Clear")
        #expect(actions.first { $0.id == "copy-default-command" }?.kind == .copyText("kwwk -p '<prompt>'"))
        #expect(LauncherModelCommandCatalog.modelId(for: command.id) == nil)
    }
}
