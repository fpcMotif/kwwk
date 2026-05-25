import KWWKLauncherCore
import Testing

@Suite("Launcher AI setting commands")
struct LauncherAISettingCommandTests {
    @Test
    func thinkingLevelsBecomePaletteCommands() throws {
        let commands = LauncherAISettingCommandCatalog.thinkingCommands()
        let high = try #require(commands.first { $0.id == "thinking:high" })

        #expect(commands.count == KWWKThinkingLevel.allCases.count)
        #expect(high.title == "Set Thinking High")
        #expect(high.subtitle == "--thinking high")
        #expect(high.category == .model)
        #expect(high.keywords.contains("reasoning"))
        #expect(high.action == .setThinkingLevel(.high))
        #expect(LauncherAISettingCommandCatalog.thinkingLevel(for: high.id) == .high)
    }

    @Test
    func contextCommandsToggleLongContextMode() throws {
        let commands = LauncherAISettingCommandCatalog.contextCommands()
        let enable = try #require(commands.first { $0.id == LauncherAISettingCommandCatalog.context1MEnableCommandId })
        let disable = try #require(commands.first { $0.id == LauncherAISettingCommandCatalog.context1MDisableCommandId })

        #expect(enable.title == "Enable 1M Context")
        #expect(enable.action == .enableContext1M)
        #expect(disable.title == "Disable 1M Context")
        #expect(disable.action == .disableContext1M)
    }

    @Test
    func modelScopeIncludesThinkingAndContextCommands() throws {
        let results = LauncherCommandFilter.filter(
            LauncherCommandCatalog.defaults,
            query: "@models thinking high"
        )

        #expect(results.first?.id == "thinking:high")
        #expect(results.allSatisfy { $0.category == .model })
    }

    @Test
    func actionCatalogExportsFlagsAndReplayableLauncherCommands() throws {
        let thinking = try #require(LauncherCommandCatalog.defaults.first { $0.id == "thinking:xhigh" })
        let enableContext = try #require(LauncherCommandCatalog.defaults.first { $0.id == "context-1m:enable" })
        let disableContext = try #require(LauncherCommandCatalog.defaults.first { $0.id == "context-1m:disable" })

        #expect(LauncherActionCatalog.primaryTitle(for: thinking) == "Set Thinking")
        #expect(LauncherActionCatalog.actions(for: thinking, isFavorite: false)
            .first { $0.id == "copy-thinking-flag" }?.kind == .copyText("--thinking xhigh"))
        #expect(LauncherActionCatalog.actions(for: thinking, isFavorite: false)
            .first { $0.id == "copy-launcher-command" }?.kind == .copyText(
                "kwwk launcher --command thinking:xhigh --run"
            ))

        #expect(LauncherActionCatalog.primaryTitle(for: enableContext) == "Enable")
        #expect(LauncherActionCatalog.actions(for: enableContext, isFavorite: false)
            .first { $0.id == "copy-context-flag" }?.kind == .copyText("--context-1m"))
        #expect(LauncherActionCatalog.actions(for: enableContext, isFavorite: false)
            .first { $0.id == "copy-launcher-command" }?.kind == .copyText(
                "kwwk launcher --command context-1m:enable --run"
            ))

        #expect(LauncherActionCatalog.primaryTitle(for: disableContext) == "Disable")
        #expect(LauncherActionCatalog.actions(for: disableContext, isFavorite: false)
            .first { $0.id == "copy-default-context-command" }?.kind == .copyText("kwwk -p '<prompt>'"))
    }
}
