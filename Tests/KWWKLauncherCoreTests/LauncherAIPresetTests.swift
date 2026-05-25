import KWWKLauncherCore
import Testing

@Suite("Launcher AI presets")
struct LauncherAIPresetTests {
    @Test
    func buildsPromptFromInstructionAndInput() {
        let preset = LauncherAIPreset(
            id: "debug",
            title: "Debug Error",
            subtitle: "Diagnose failure",
            keywords: ["debug"],
            inputSource: .queryOrClipboard,
            instruction: "Find the root cause."
        )

        let prompt = preset.prompt(input: "  compiler failed  ")

        #expect(prompt == "Find the root cause.\n\nInput:\ncompiler failed")
    }

    @Test
    func exposesPresetCommandsInDefaultCatalog() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "ai-preset:debug-error" })

        #expect(command.title == "Debug Error")
        #expect(command.category == .ai)
        guard case .runAIPreset(let preset) = command.action else {
            Issue.record("Expected AI preset action")
            return
        }
        #expect(preset.inputSource == .queryOrClipboard)
    }

    @Test
    func findsPresetByIntent() {
        let results = LauncherCommandFilter.filter(LauncherCommandCatalog.defaults, query: "commit diff")

        #expect(results.first?.id == "ai-preset:commit-message")
    }

    @Test
    func extractsArgumentTextAfterPresetTrigger() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "ai-preset:shell-command" })
        guard case .runAIPreset(let preset) = command.action else {
            Issue.record("Expected AI preset action")
            return
        }

        let input = preset.input(query: "shell command list large files", clipboard: "ignored")

        #expect(input == "list large files")
    }

    @Test
    func queryOrClipboardPresetFallsBackToClipboardWhenTriggerHasNoArgument() throws {
        let command = try #require(LauncherCommandCatalog.defaults.first { $0.id == "ai-preset:debug-error" })
        guard case .runAIPreset(let preset) = command.action else {
            Issue.record("Expected AI preset action")
            return
        }

        let input = preset.input(query: "debug error", clipboard: "fatal: module failed")

        #expect(input == "fatal: module failed")
    }

    @Test
    func commandFilterKeepsPresetSelectedWhenQueryCarriesArguments() {
        let results = LauncherCommandFilter.filter(
            LauncherCommandCatalog.defaults,
            query: "shell command list large files"
        )

        #expect(results.first?.id == "ai-preset:shell-command")
    }
}
