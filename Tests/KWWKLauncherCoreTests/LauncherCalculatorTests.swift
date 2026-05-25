import KWWKLauncherCore
import Testing

@Suite("Launcher calculator")
struct LauncherCalculatorTests {
    @Test
    func evaluatesOperatorPrecedence() throws {
        let result = try #require(LauncherCalculator.result(for: "=2 + 3 * 4"))

        #expect(result.expression == "2 + 3 * 4")
        #expect(result.formattedValue == "14")
    }

    @Test
    func evaluatesParenthesesUnaryAndDecimals() throws {
        let result = try #require(LauncherCalculator.result(for: "=(2.5 + 3.5) * -2"))

        #expect(result.formattedValue == "-12")
    }

    @Test
    func supportsFunctionsConstantsPowersAndRemainders() throws {
        let root = try #require(LauncherCalculator.result(for: "sqrt(144)"))
        let circle = try #require(LauncherCalculator.result(for: "=pi ^ 2"))
        let remainder = try #require(LauncherCalculator.result(for: "=17 % 5"))

        #expect(root.formattedValue == "12")
        #expect(circle.value > 9.86)
        #expect(circle.value < 9.87)
        #expect(remainder.formattedValue == "2")
    }

    @Test
    func rejectsPlainTextAndUnsafeExpressions() {
        #expect(LauncherCalculator.result(for: "summarize this repo") == nil)
        #expect(LauncherCalculator.result(for: "=2 / 0") == nil)
        #expect(LauncherCalculator.result(for: "=2 +") == nil)
        #expect(LauncherCalculator.result(for: "$ echo 2+2") == nil)
    }

    @Test
    func createsDynamicCalculatorCommand() throws {
        let command = try #require(LauncherCalculatorCommandFactory.commands(for: "=2+2").first)

        #expect(command.id == "calculator:2+2")
        #expect(command.title == "4")
        #expect(command.category == .calculator)
        #expect(command.action == .copyCalculatorResult(LauncherCalculatorResult(
            expression: "2+2",
            value: 4,
            formattedValue: "4"
        )))
    }

    @Test
    func calculatorCommandRanksBeforeFallbackCommands() {
        let query = "=2+2"
        let commands = LauncherCalculatorCommandFactory.commands(for: query)
            + LauncherDynamicCommandFactory.commands(for: query)
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "calculator:2+2")
    }

    @Test
    func scopedCalculatorQueryFiltersInsideCalculatorCategory() throws {
        let query = "@calculator 2 + 2"
        let command = try #require(LauncherCalculatorCommandFactory.commands(for: query).first)
        let commands = [command] + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(command.id == "calculator:2 + 2")
        #expect(results.first?.id == "calculator:2 + 2")
        #expect(results.allSatisfy { $0.category == .calculator })
    }

    @Test
    func calculatorActionsCopyResultExpressionAndBridgeCommand() throws {
        let command = try #require(LauncherCalculatorCommandFactory.commands(for: "=2+2").first)

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Copy")
        #expect(actions.first { $0.id == "copy-result" }?.kind == .copyText("4"))
        #expect(actions.first { $0.id == "copy-expression" }?.kind == .copyText("2+2"))
        #expect(actions.first { $0.id == "save-result-snippet" }?.kind == .saveSnippet(
            LauncherSnippetIndex.snippet(from: LauncherCalculatorResult(
                expression: "2+2",
                value: 4,
                formattedValue: "4"
            ))
        ))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command calculator:2+2 --run -- =2+2"
        ))
    }
}
