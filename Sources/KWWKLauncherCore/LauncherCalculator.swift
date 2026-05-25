import Foundation

public struct LauncherCalculatorResult: Sendable, Hashable {
    public var expression: String
    public var value: Double
    public var formattedValue: String

    public init(expression: String, value: Double, formattedValue: String) {
        self.expression = expression
        self.value = value
        self.formattedValue = formattedValue
    }

    public var displayText: String {
        "\(expression) = \(formattedValue)"
    }
}

public enum LauncherCalculator {
    public static func result(for query: String) -> LauncherCalculatorResult? {
        let text = LauncherCommandFilter.scopedQuery(from: query)
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("$"), !text.hasPrefix("!"), !text.hasPrefix("?") else {
            return nil
        }

        let hasExplicitPrefix = text.hasPrefix("=")
        let expression = hasExplicitPrefix
            ? String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            : text
        guard !expression.isEmpty else { return nil }
        guard hasExplicitPrefix || looksLikeMathExpression(expression) else { return nil }

        var parser = LauncherCalculatorParser(expression)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return LauncherCalculatorResult(
            expression: expression,
            value: value,
            formattedValue: formattedValue(for: value)
        )
    }

    public static func formattedValue(for value: Double) -> String {
        let normalized = abs(value) < 1e-12 ? 0 : value
        let rounded = normalized.rounded()
        let tolerance = max(1e-10, abs(normalized) * 1e-12)
        if abs(normalized - rounded) <= tolerance,
           rounded >= Double(Int64.min),
           rounded <= Double(Int64.max) {
            return "\(Int64(rounded))"
        }

        return String(format: "%.12g", normalized)
            .replacingOccurrences(of: "e+", with: "e")
    }

    private static func looksLikeMathExpression(_ expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("sqrt(") || lowercased.hasPrefix("abs(") {
            return true
        }

        var sawOperand = false
        var sawBinaryOperator = false
        var previousTokenWasOperand = false

        for character in lowercased {
            if character.isWhitespace || character == "." {
                continue
            }
            if character.isNumber || character.isLetter || character == ")" {
                sawOperand = true
                previousTokenWasOperand = true
                continue
            }
            if "+*/%^".contains(character) {
                sawBinaryOperator = true
                previousTokenWasOperand = false
                continue
            }
            if character == "-" {
                if previousTokenWasOperand {
                    sawBinaryOperator = true
                }
                previousTokenWasOperand = false
                continue
            }
            if character == "(" {
                previousTokenWasOperand = false
                continue
            }
            return false
        }

        return sawOperand && sawBinaryOperator
    }
}

public enum LauncherCalculatorCommandFactory {
    public static let commandPrefix = "calculator:"

    public static func commands(for query: String) -> [LauncherCommand] {
        guard let result = LauncherCalculator.result(for: query) else { return [] }
        return [
            LauncherCommand(
                id: commandId(for: result),
                title: result.formattedValue,
                subtitle: result.displayText,
                systemImage: "function",
                category: .calculator,
                keywords: ["calculator", "calc", "math", "equals", result.expression, "=\(result.expression)", result.formattedValue],
                action: .copyCalculatorResult(result)
            ),
        ]
    }

    public static func commandId(for result: LauncherCalculatorResult) -> LauncherCommand.ID {
        "\(commandPrefix)\(result.expression)"
    }
}

private struct LauncherCalculatorParser {
    private let characters: [Character]
    private var index = 0

    init(_ expression: String) {
        characters = Array(expression)
    }

    mutating func parse() -> Double? {
        guard let value = parseExpression() else { return nil }
        skipWhitespace()
        guard index == characters.count else { return nil }
        return value.isFinite ? value : nil
    }

    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }

        while true {
            skipWhitespace()
            if consume("+") {
                guard let rhs = parseTerm() else { return nil }
                value += rhs
            } else if consume("-") {
                guard let rhs = parseTerm() else { return nil }
                value -= rhs
            } else {
                return finite(value)
            }
        }
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parsePower() else { return nil }

        while true {
            skipWhitespace()
            if consume("*") {
                guard let rhs = parsePower() else { return nil }
                value *= rhs
            } else if consume("/") {
                guard let rhs = parsePower(), rhs != 0 else { return nil }
                value /= rhs
            } else if consume("%") {
                guard let rhs = parsePower(), rhs != 0 else { return nil }
                value = value.truncatingRemainder(dividingBy: rhs)
            } else {
                return finite(value)
            }
        }
    }

    private mutating func parsePower() -> Double? {
        guard var value = parseUnary() else { return nil }
        skipWhitespace()
        if consume("^") {
            guard let exponent = parsePower() else { return nil }
            value = Foundation.pow(value, exponent)
        }
        return finite(value)
    }

    private mutating func parseUnary() -> Double? {
        skipWhitespace()
        if consume("+") {
            return parseUnary()
        }
        if consume("-") {
            guard let value = parseUnary() else { return nil }
            return finite(-value)
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Double? {
        skipWhitespace()
        if consume("(") {
            guard let value = parseExpression() else { return nil }
            skipWhitespace()
            guard consume(")") else { return nil }
            return finite(value)
        }

        if let number = parseNumber() {
            return number
        }

        guard let identifier = parseIdentifier() else { return nil }
        switch identifier.lowercased() {
        case "pi":
            return Double.pi
        case "e":
            return 2.718281828459045
        case "sqrt":
            guard let value = parseFunctionArgument(), value >= 0 else { return nil }
            return finite(Foundation.sqrt(value))
        case "abs":
            guard let value = parseFunctionArgument() else { return nil }
            return finite(abs(value))
        default:
            return nil
        }
    }

    private mutating func parseFunctionArgument() -> Double? {
        skipWhitespace()
        guard consume("(") else { return nil }
        guard let value = parseExpression() else { return nil }
        skipWhitespace()
        guard consume(")") else { return nil }
        return finite(value)
    }

    private mutating func parseNumber() -> Double? {
        let start = index
        var sawDigit = false
        var sawDecimalPoint = false

        while index < characters.count {
            let character = characters[index]
            if character.isNumber {
                sawDigit = true
                index += 1
            } else if character == ".", !sawDecimalPoint {
                sawDecimalPoint = true
                index += 1
            } else {
                break
            }
        }

        guard sawDigit else {
            index = start
            return nil
        }
        return Double(String(characters[start..<index]))
    }

    private mutating func parseIdentifier() -> String? {
        let start = index
        while index < characters.count, characters[index].isLetter {
            index += 1
        }
        guard start != index else { return nil }
        return String(characters[start..<index])
    }

    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace {
            index += 1
        }
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard index < characters.count, characters[index] == character else { return false }
        index += 1
        return true
    }

    private func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }
}
