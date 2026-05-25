import Foundation

public struct LauncherUnitConversionResult: Sendable, Hashable {
    public var expression: String
    public var inputValue: Double
    public var inputUnit: String
    public var outputValue: Double
    public var outputUnit: String
    public var formattedInput: String
    public var formattedOutput: String

    public init(
        expression: String,
        inputValue: Double,
        inputUnit: String,
        outputValue: Double,
        outputUnit: String,
        formattedInput: String,
        formattedOutput: String
    ) {
        self.expression = expression
        self.inputValue = inputValue
        self.inputUnit = inputUnit
        self.outputValue = outputValue
        self.outputUnit = outputUnit
        self.formattedInput = formattedInput
        self.formattedOutput = formattedOutput
    }

    public var displayText: String {
        "\(formattedInput) = \(formattedOutput)"
    }
}

public enum LauncherUnitConverter {
    public static func result(for query: String) -> LauncherUnitConversionResult? {
        let text = LauncherCommandFilter.scopedQuery(from: query)
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("$"), !text.hasPrefix("!"), !text.hasPrefix("?") else {
            return nil
        }

        let expression = text.hasPrefix("=")
            ? String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            : text
        guard let request = ConversionRequest.parse(expression) else { return nil }
        guard request.from.dimension == request.to.dimension else { return nil }
        guard let outputValue = request.from.convert(request.value, to: request.to), outputValue.isFinite else {
            return nil
        }

        let formattedInputValue = LauncherCalculator.formattedValue(for: request.value)
        let formattedOutputValue = LauncherCalculator.formattedValue(for: outputValue)
        let normalizedExpression = "\(formattedInputValue) \(request.from.symbol) to \(request.to.symbol)"
        return LauncherUnitConversionResult(
            expression: normalizedExpression,
            inputValue: request.value,
            inputUnit: request.from.symbol,
            outputValue: outputValue,
            outputUnit: request.to.symbol,
            formattedInput: "\(formattedInputValue) \(request.from.symbol)",
            formattedOutput: "\(formattedOutputValue) \(request.to.symbol)"
        )
    }
}

public enum LauncherUnitConversionCommandFactory {
    public static let commandPrefix = "convert:"

    public static func commands(for query: String) -> [LauncherCommand] {
        guard let result = LauncherUnitConverter.result(for: query) else { return [] }
        return [
            LauncherCommand(
                id: "\(commandPrefix)\(result.expression)",
                title: result.formattedOutput,
                subtitle: result.displayText,
                systemImage: "arrow.left.arrow.right",
                category: .calculator,
                keywords: [
                    "convert",
                    "conversion",
                    "unit",
                    "units",
                    result.expression,
                    result.inputUnit,
                    result.outputUnit,
                    result.formattedInput,
                    result.formattedOutput,
                ],
                action: .copyUnitConversionResult(result)
            ),
        ]
    }
}

private struct ConversionRequest {
    var value: Double
    var from: LauncherUnitDefinition
    var to: LauncherUnitDefinition

    static func parse(_ expression: String) -> ConversionRequest? {
        let normalized = expression
            .lowercased()
            .replacingOccurrences(of: "->", with: " to ")
            .replacingOccurrences(of: " into ", with: " to ")
        let tokens = normalized
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard let separatorIndex = tokens.firstIndex(where: { ["to", "in", "as", "="].contains($0) }),
              separatorIndex > tokens.startIndex,
              separatorIndex < tokens.index(before: tokens.endIndex)
        else {
            return nil
        }

        let leftTokens = Array(tokens[..<separatorIndex])
        let rightTokens = Array(tokens[tokens.index(after: separatorIndex)...])
        guard let left = parseLeftSide(leftTokens),
              let to = LauncherUnitDefinition.lookup(rightTokens.joined(separator: " "))
        else {
            return nil
        }

        return ConversionRequest(value: left.value, from: left.unit, to: to)
    }

    private static func parseLeftSide(_ tokens: [String]) -> (value: Double, unit: LauncherUnitDefinition)? {
        guard !tokens.isEmpty else { return nil }
        if tokens.count == 1 {
            guard let split = splitNumberAndUnit(tokens[0]),
                  let unit = LauncherUnitDefinition.lookup(split.unit)
            else {
                return nil
            }
            return (split.value, unit)
        }

        guard let value = Double(tokens[0]),
              let unit = LauncherUnitDefinition.lookup(tokens.dropFirst().joined(separator: " "))
        else {
            return nil
        }
        return (value, unit)
    }

    private static func splitNumberAndUnit(_ token: String) -> (value: Double, unit: String)? {
        var end = token.startIndex
        var sawDigit = false
        var sawDecimalPoint = false
        var sawSign = false

        while end < token.endIndex {
            let character = token[end]
            if character.isNumber {
                sawDigit = true
                end = token.index(after: end)
            } else if character == ".", !sawDecimalPoint {
                sawDecimalPoint = true
                end = token.index(after: end)
            } else if (character == "+" || character == "-"), !sawSign, !sawDigit, !sawDecimalPoint {
                sawSign = true
                end = token.index(after: end)
            } else {
                break
            }
        }

        guard sawDigit, end > token.startIndex, end < token.endIndex else { return nil }
        guard let value = Double(String(token[..<end])) else { return nil }
        return (value, String(token[end...]))
    }
}

private enum LauncherUnitDimension: Sendable {
    case data
    case length
    case mass
    case temperature
}

private struct LauncherUnitDefinition: Sendable {
    var symbol: String
    var dimension: LauncherUnitDimension
    var baseFactor: Double?
    var toBaseTemperature: (@Sendable (Double) -> Double)?
    var fromBaseTemperature: (@Sendable (Double) -> Double)?
    var aliases: [String]

    func convert(_ value: Double, to target: LauncherUnitDefinition) -> Double? {
        guard dimension == target.dimension else { return nil }
        switch dimension {
        case .temperature:
            guard let toBaseTemperature, let targetFromBase = target.fromBaseTemperature else { return nil }
            return targetFromBase(toBaseTemperature(value))
        case .data, .length, .mass:
            guard let baseFactor, let targetFactor = target.baseFactor else { return nil }
            return value * baseFactor / targetFactor
        }
    }

    static func lookup(_ rawValue: String) -> LauncherUnitDefinition? {
        let key = normalized(rawValue)
        return all.first { unit in
            unit.aliases.contains(key)
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func linear(
        _ symbol: String,
        dimension: LauncherUnitDimension,
        baseFactor: Double,
        aliases: [String]
    ) -> LauncherUnitDefinition {
        LauncherUnitDefinition(
            symbol: symbol,
            dimension: dimension,
            baseFactor: baseFactor,
            toBaseTemperature: nil,
            fromBaseTemperature: nil,
            aliases: aliases.map(normalized)
        )
    }

    private static func temperature(
        _ symbol: String,
        aliases: [String],
        toBase: @escaping @Sendable (Double) -> Double,
        fromBase: @escaping @Sendable (Double) -> Double
    ) -> LauncherUnitDefinition {
        LauncherUnitDefinition(
            symbol: symbol,
            dimension: .temperature,
            baseFactor: nil,
            toBaseTemperature: toBase,
            fromBaseTemperature: fromBase,
            aliases: aliases.map(normalized)
        )
    }

    private static let all: [LauncherUnitDefinition] = [
        linear("mm", dimension: .length, baseFactor: 0.001, aliases: ["mm", "millimeter", "millimeters"]),
        linear("cm", dimension: .length, baseFactor: 0.01, aliases: ["cm", "centimeter", "centimeters"]),
        linear("m", dimension: .length, baseFactor: 1, aliases: ["m", "meter", "meters", "metre", "metres"]),
        linear("km", dimension: .length, baseFactor: 1_000, aliases: ["km", "kilometer", "kilometers", "kilometre", "kilometres"]),
        linear("in", dimension: .length, baseFactor: 0.0254, aliases: ["in", "inch", "inches"]),
        linear("ft", dimension: .length, baseFactor: 0.3048, aliases: ["ft", "foot", "feet"]),
        linear("yd", dimension: .length, baseFactor: 0.9144, aliases: ["yd", "yard", "yards"]),
        linear("mi", dimension: .length, baseFactor: 1_609.344, aliases: ["mi", "mile", "miles"]),

        linear("mg", dimension: .mass, baseFactor: 0.001, aliases: ["mg", "milligram", "milligrams"]),
        linear("g", dimension: .mass, baseFactor: 1, aliases: ["g", "gram", "grams"]),
        linear("kg", dimension: .mass, baseFactor: 1_000, aliases: ["kg", "kilogram", "kilograms"]),
        linear("oz", dimension: .mass, baseFactor: 28.349523125, aliases: ["oz", "ounce", "ounces"]),
        linear("lb", dimension: .mass, baseFactor: 453.59237, aliases: ["lb", "lbs", "pound", "pounds"]),

        linear("B", dimension: .data, baseFactor: 1, aliases: ["b", "byte", "bytes"]),
        linear("KB", dimension: .data, baseFactor: 1_000, aliases: ["kb", "kilobyte", "kilobytes"]),
        linear("MB", dimension: .data, baseFactor: 1_000_000, aliases: ["mb", "megabyte", "megabytes"]),
        linear("GB", dimension: .data, baseFactor: 1_000_000_000, aliases: ["gb", "gigabyte", "gigabytes"]),
        linear("KiB", dimension: .data, baseFactor: 1_024, aliases: ["kib", "kibibyte", "kibibytes"]),
        linear("MiB", dimension: .data, baseFactor: 1_048_576, aliases: ["mib", "mebibyte", "mebibytes"]),
        linear("GiB", dimension: .data, baseFactor: 1_073_741_824, aliases: ["gib", "gibibyte", "gibibytes"]),

        temperature("C", aliases: ["c", "celsius", "centigrade"]) { $0 } fromBase: { $0 },
        temperature("F", aliases: ["f", "fahrenheit"]) { ($0 - 32) * 5 / 9 } fromBase: { $0 * 9 / 5 + 32 },
        temperature("K", aliases: ["k", "kelvin"]) { $0 - 273.15 } fromBase: { $0 + 273.15 },
    ]
}
