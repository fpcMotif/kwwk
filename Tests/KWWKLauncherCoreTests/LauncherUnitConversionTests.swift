import KWWKLauncherCore
import Testing

@Suite("Launcher unit conversion")
struct LauncherUnitConversionTests {
    @Test
    func convertsLengthWithSpacedUnits() throws {
        let result = try #require(LauncherUnitConverter.result(for: "10 km to m"))

        #expect(result.expression == "10 km to m")
        #expect(result.formattedInput == "10 km")
        #expect(result.formattedOutput == "10000 m")
    }

    @Test
    func convertsCompactLengthAndImperialAliases() throws {
        let result = try #require(LauncherUnitConverter.result(for: "12in to ft"))

        #expect(result.expression == "12 in to ft")
        #expect(result.formattedOutput == "1 ft")
    }

    @Test
    func convertsMassTemperatureAndDataUnits() throws {
        let pounds = try #require(LauncherUnitConverter.result(for: "1 lb to kg"))
        let temperature = try #require(LauncherUnitConverter.result(for: "32 f to c"))
        let data = try #require(LauncherUnitConverter.result(for: "1 MiB to KB"))

        #expect(pounds.outputValue > 0.453)
        #expect(pounds.outputValue < 0.454)
        #expect(temperature.formattedOutput == "0 C")
        #expect(data.formattedOutput == "1048.576 KB")
    }

    @Test
    func rejectsPlainTextAndIncompatibleDimensions() {
        #expect(LauncherUnitConverter.result(for: "summarize this repo") == nil)
        #expect(LauncherUnitConverter.result(for: "10 km to kg") == nil)
        #expect(LauncherUnitConverter.result(for: "10 km") == nil)
        #expect(LauncherUnitConverter.result(for: "$ 10 km to m") == nil)
    }

    @Test
    func createsDynamicConversionCommand() throws {
        let command = try #require(LauncherUnitConversionCommandFactory.commands(for: "10 km to m").first)

        #expect(command.id == "convert:10 km to m")
        #expect(command.title == "10000 m")
        #expect(command.category == .calculator)
        #expect(command.action == .copyUnitConversionResult(LauncherUnitConversionResult(
            expression: "10 km to m",
            inputValue: 10,
            inputUnit: "km",
            outputValue: 10_000,
            outputUnit: "m",
            formattedInput: "10 km",
            formattedOutput: "10000 m"
        )))
    }

    @Test
    func conversionRanksBeforeDynamicAskCommand() {
        let query = "10 km to m"
        let commands = LauncherUnitConversionCommandFactory.commands(for: query)
            + LauncherDynamicCommandFactory.commands(for: query)
            + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "convert:10 km to m")
    }

    @Test
    func scopedConversionFiltersInsideCalculatorCategory() throws {
        let query = "@calculator 10 km to m"
        let command = try #require(LauncherUnitConversionCommandFactory.commands(for: query).first)
        let commands = [command] + LauncherCommandCatalog.defaults

        let results = LauncherCommandFilter.filter(commands, query: query)

        #expect(results.first?.id == "convert:10 km to m")
        #expect(results.allSatisfy { $0.category == .calculator })
    }

    @Test
    func conversionActionsCopyResultExpressionAndBridgeCommand() throws {
        let command = try #require(LauncherUnitConversionCommandFactory.commands(for: "10 km to m").first)

        let actions = LauncherActionCatalog.actions(for: command, isFavorite: false)

        #expect(LauncherActionCatalog.primaryTitle(for: command) == "Copy")
        #expect(actions.first { $0.id == "copy-result" }?.kind == .copyText("10000 m"))
        #expect(actions.first { $0.id == "copy-expression" }?.kind == .copyText("10 km to m"))
        #expect(actions.first { $0.id == "save-result-snippet" }?.kind == .saveSnippet(
            LauncherSnippetIndex.snippet(from: LauncherUnitConversionResult(
                expression: "10 km to m",
                inputValue: 10,
                inputUnit: "km",
                outputValue: 10_000,
                outputUnit: "m",
                formattedInput: "10 km",
                formattedOutput: "10000 m"
            ))
        ))
        #expect(actions.first { $0.id == "copy-launcher-command" }?.kind == .copyText(
            "kwwk launcher --command 'convert:10 km to m' --run -- '10 km to m'"
        ))
    }
}
