import Foundation

/// A launcher calculation result — math, unit conversion, or currency
/// conversion. Produced by `Calculator.parse`, rendered by the launcher's
/// Calculator section; Enter copies `clipboardValue`.
public enum Calculation {
    case math(expression: String, value: Double)
    case units(input: String, value: Double, outputLabel: String)
    case currency(amount: Double, from: String, to: String, value: Double, rateDate: String?)

    public var display: String {
        switch self {
        case .math(_, let value):
            return "= " + Self.format(value)
        case .units(_, let value, let outputLabel):
            return "= " + Self.format(value) + " " + outputLabel
        case .currency(_, _, let to, let value, _):
            return "= " + Self.format(value, decimals: 2, minimumDecimals: 2) + " " + to
        }
    }

    public var subtitle: String {
        switch self {
        case .math(let expression, _):
            return expression
        case .units(let input, _, _):
            return input
        case .currency(_, let from, let to, _, let rateDate):
            let base = "\(from) → \(to)"
            guard let rateDate else { return base }
            return base + " · rates from " + rateDate
        }
    }

    public var clipboardValue: String {
        switch self {
        case .math(_, let value):
            return Self.format(value)
        case .units(_, let value, _):
            return Self.format(value)
        case .currency(_, _, _, let value, _):
            return Self.format(value, decimals: 2)
        }
    }

    /// Grouped number, trailing zeros trimmed, decimals capped. Fixed to a
    /// dot decimal separator so copied values stay machine-friendly.
    static func format(_ value: Double, decimals: Int = 6, minimumDecimals: Int = 0) -> String {
        guard value.isFinite, !value.isNaN else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.maximumFractionDigits = decimals
        formatter.minimumFractionDigits = minimumDecimals
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Parses launcher queries into calculations. Pure and dependency-free:
/// currency math takes the rates table as a parameter, so no I/O happens
/// here. Parse failure must stay cheap — most queries don't parse.
public enum Calculator {
    /// An exchange-rate table relative to `base`: 1 base = `rates[X]` of
    /// currency X, fetched on the given date.
    public typealias RatesTable = (base: String, date: String?, rates: [String: Double])

    public static func parse(
        query: String,
        rates: @autoclosure () -> RatesTable? = nil,
        baseCurrency: String = "USD",
        preferredUnits: String = "metric"
    ) -> Calculation? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let math = MathEvaluator.evaluate(trimmed) {
            return .math(expression: trimmed, value: math)
        }
        if let units = parseUnits(trimmed, preferredUnits: preferredUnits) {
            return units
        }
        if let currency = parseCurrency(trimmed, rates: rates, baseCurrency: baseCurrency) {
            return currency
        }
        return nil
    }

    // MARK: - Units

    private struct UnitDef {
        let factor: Double
        let label: String
    }

    /// factor converts 1 unit → the dimension's base (m, kg, °C, L, km/h).
    private static let lengthUnits: [String: UnitDef] = [
        "km": UnitDef(factor: 1000, label: "km"),
        "kilometer": UnitDef(factor: 1000, label: "km"),
        "kilometers": UnitDef(factor: 1000, label: "km"),
        "m": UnitDef(factor: 1, label: "m"),
        "meter": UnitDef(factor: 1, label: "m"),
        "meters": UnitDef(factor: 1, label: "m"),
        "cm": UnitDef(factor: 0.01, label: "cm"),
        "mm": UnitDef(factor: 0.001, label: "mm"),
        "mi": UnitDef(factor: 1609.344, label: "mi"),
        "mile": UnitDef(factor: 1609.344, label: "mi"),
        "miles": UnitDef(factor: 1609.344, label: "mi"),
        "ft": UnitDef(factor: 0.3048, label: "ft"),
        "foot": UnitDef(factor: 0.3048, label: "ft"),
        "feet": UnitDef(factor: 0.3048, label: "ft"),
        "in": UnitDef(factor: 0.0254, label: "in"),
        "inch": UnitDef(factor: 0.0254, label: "in"),
        "inches": UnitDef(factor: 0.0254, label: "in"),
        "yd": UnitDef(factor: 0.9144, label: "yd"),
        "yard": UnitDef(factor: 0.9144, label: "yd"),
        "yards": UnitDef(factor: 0.9144, label: "yd"),
    ]

    private static let massUnits: [String: UnitDef] = [
        "kg": UnitDef(factor: 1, label: "kg"),
        "kilogram": UnitDef(factor: 1, label: "kg"),
        "kilograms": UnitDef(factor: 1, label: "kg"),
        "g": UnitDef(factor: 0.001, label: "g"),
        "gram": UnitDef(factor: 0.001, label: "g"),
        "grams": UnitDef(factor: 0.001, label: "g"),
        "lb": UnitDef(factor: 0.45359237, label: "lb"),
        "lbs": UnitDef(factor: 0.45359237, label: "lb"),
        "pound": UnitDef(factor: 0.45359237, label: "lb"),
        "pounds": UnitDef(factor: 0.45359237, label: "lb"),
        "oz": UnitDef(factor: 0.028349523125, label: "oz"),
        "ounce": UnitDef(factor: 0.028349523125, label: "oz"),
        "ounces": UnitDef(factor: 0.028349523125, label: "oz"),
    ]

    private static let volumeUnits: [String: UnitDef] = [
        "l": UnitDef(factor: 1, label: "L"),
        "liter": UnitDef(factor: 1, label: "L"),
        "liters": UnitDef(factor: 1, label: "L"),
        "litre": UnitDef(factor: 1, label: "L"),
        "litres": UnitDef(factor: 1, label: "L"),
        "ml": UnitDef(factor: 0.001, label: "mL"),
        "gal": UnitDef(factor: 3.785411784, label: "gal"),
        "gallon": UnitDef(factor: 3.785411784, label: "gal"),
        "gallons": UnitDef(factor: 3.785411784, label: "gal"),
        "qt": UnitDef(factor: 0.946352946, label: "qt"),
        "quart": UnitDef(factor: 0.946352946, label: "qt"),
        "quarts": UnitDef(factor: 0.946352946, label: "qt"),
        "floz": UnitDef(factor: 0.0295735295625, label: "fl oz"),
    ]

    /// Base km/h.
    private static let speedUnits: [String: UnitDef] = [
        "kmh": UnitDef(factor: 1, label: "km/h"),
        "kph": UnitDef(factor: 1, label: "km/h"),
        "mph": UnitDef(factor: 1.609344, label: "mph"),
        "kn": UnitDef(factor: 1.852, label: "kn"),
        "knot": UnitDef(factor: 1.852, label: "kn"),
        "knots": UnitDef(factor: 1.852, label: "kn"),
    ]

    /// Temperature is affine, not ratio — handled separately.
    private static let temperatureUnits: Set<String> = ["c", "f", "k", "celsius", "fahrenheit", "kelvin"]

    /// Metric ↔ imperial counterparts for bare-unit queries, guided by the
    /// preferred unit system setting.
    private static let counterpart: [String: String] = [
        "km": "mi", "mi": "km",
        "m": "ft", "ft": "m",
        "cm": "in", "in": "cm",
        "kg": "lb", "lb": "kg",
        "c": "f", "f": "c",
        "l": "gal", "gal": "l",
        "kmh": "mph", "mph": "kmh",
    ]

    /// Unit tokens on the imperial/US customary side of the counterpart pairs.
    private static let imperialUnits: Set<String> = ["mi", "ft", "in", "lb", "f", "gal", "mph"]

    private static func parseUnits(_ query: String, preferredUnits: String) -> Calculation? {
        let normalized = query.lowercased()
            .replacingOccurrences(of: "°", with: " ")
            .replacingOccurrences(of: "fl oz", with: "floz")
            .replacingOccurrences(of: "km/h", with: "kmh")

        // Split on a conversion separator. " in " is both a separator and the
        // inch unit, so if the first split fails to parse, try the last one
        // ("5 in in cm").
        for separator in [" to ", " in "] {
            guard let range = normalized.range(of: separator) else { continue }
            if let result = convertQuery(left: String(normalized[..<range.lowerBound]),
                                         right: String(normalized[range.upperBound...]),
                                         input: query) {
                return result
            }
            if let lastRange = normalized.range(of: separator, options: .backwards),
               lastRange != range,
               let result = convertQuery(left: String(normalized[..<lastRange.lowerBound]),
                                         right: String(normalized[lastRange.upperBound...]),
                                         input: query) {
                return result
            }
            return nil
        }

        // No separator: bare "72 f" converts to the counterpart unit only
        // when it crosses the preferred system ("5 km" with Imperial
        // preferred → miles); same-system bare units produce no row.
        let (amount, unitToken) = splitAmountAndUnit(normalized)
        guard let unitToken else { return nil }
        // Temperature lives outside the unit tables (affine, not ratio), so
        // resolve the canonical label for both table and temperature units.
        guard let canonical = canonicalUnitLabel(unitToken),
              let counterpart = counterpart[canonical] else { return nil }
        let unitIsImperial = imperialUnits.contains(canonical)
        guard unitIsImperial != (preferredUnits == "imperial") else { return nil }
        guard let value = convert(value: amount, from: unitToken, to: counterpart) else { return nil }
        return .units(input: query, value: value, outputLabel: outputLabel(for: counterpart))
    }

    /// Canonical short key for a unit token ("fahrenheit" → "f"), shared by
    /// the unit tables and the temperature set.
    private static func canonicalUnitLabel(_ token: String) -> String? {
        if let def = unitDef(token) { return def.label.lowercased() }
        switch token {
        case "c", "celsius": return "c"
        case "f", "fahrenheit": return "f"
        case "k", "kelvin": return "k"
        default: return nil
        }
    }

    /// Display label for a unit token, with degree signs for temperatures.
    private static func outputLabel(for token: String) -> String {
        switch token {
        case "c", "celsius": return "°C"
        case "f", "fahrenheit": return "°F"
        case "k", "kelvin": return "K"
        default: return unitDef(token)?.label ?? token
        }
    }

    /// "<number> <unit>" → "<unit>"; both sides must be single unit tokens
    /// after the leading amount (multi-word forms are pre-normalized).
    private static func convertQuery(left: String, right: String, input: String) -> Calculation? {
        let (amount, fromToken) = splitAmountAndUnit(left)
        guard let fromToken else { return nil }
        let rightTokens = right.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
        guard rightTokens.count == 1 else { return nil }
        let toToken = String(rightTokens[0])
        guard let value = convert(value: amount, from: fromToken, to: toToken) else { return nil }
        return .units(input: input, value: value, outputLabel: outputLabel(for: toToken))
    }

    /// Converts between any two known units (including temperature). Nil for
    /// unknown units or mismatched dimensions.
    static func convert(value: Double, from: String, to: String) -> Double? {
        let fromToken = from.trimmingCharacters(in: .whitespaces)
        let toToken = to.trimmingCharacters(in: .whitespaces)

        if temperatureUnits.contains(fromToken) || temperatureUnits.contains(toToken) {
            guard let celsius = toCelsius(value, from: fromToken),
                  let target = fromCelsius(celsius, to: toToken) else { return nil }
            return target
        }

        guard let fromDef = unitDef(fromToken), let toDef = unitDef(toToken),
              dimension(fromToken) == dimension(toToken) else { return nil }
        return value * fromDef.factor / toDef.factor
    }

    private static func toCelsius(_ value: Double, from token: String) -> Double? {
        switch token {
        case "c", "celsius": return value
        case "f", "fahrenheit": return (value - 32) * 5 / 9
        case "k", "kelvin": return value - 273.15
        default: return nil
        }
    }

    private static func fromCelsius(_ value: Double, to token: String) -> Double? {
        switch token {
        case "c", "celsius": return value
        case "f", "fahrenheit": return value * 9 / 5 + 32
        case "k", "kelvin": return value + 273.15
        default: return nil
        }
    }

    private static func unitDef(_ token: String) -> UnitDef? {
        lengthUnits[token] ?? massUnits[token] ?? volumeUnits[token] ?? speedUnits[token]
    }

    private static func dimension(_ token: String) -> Int {
        if lengthUnits[token] != nil { return 0 }
        if massUnits[token] != nil { return 1 }
        if volumeUnits[token] != nil { return 2 }
        if speedUnits[token] != nil { return 3 }
        return -1
    }

    /// Splits "5 km" / "5km" / "km" into (amount, unit). Missing amount → 1;
    /// a token that is only a number has no unit half.
    private static func splitAmountAndUnit(_ text: String) -> (Double, String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let components = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if components.count == 2, let amount = number(components[0]) {
            return (amount, String(components[1]))
        }
        if components.count == 1 {
            let token = String(components[0])
            if let amount = leadingNumber(token) {
                let unit = token.drop(while: { $0.isNumber || $0 == "." || $0 == "," })
                return unit.isEmpty ? (amount, nil) : (amount, String(unit))
            }
            return (1, token)
        }
        return (1, nil)
    }

    private static func number(_ text: some StringProtocol) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }

    private static func leadingNumber(_ text: String) -> Double? {
        let allowed = text.prefix { $0.isNumber || $0 == "." || $0 == "," }
        guard !allowed.isEmpty else { return nil }
        return number(allowed)
    }

    // MARK: - Currency

    /// ISO codes frankfurter (ECB) serves; used for the Settings picker and
    /// to recognize currency tokens in queries.
    public static let supportedCurrencies = [
        "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP",
        "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR",
        "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    private static func parseCurrency(_ query: String, rates: () -> RatesTable?, baseCurrency: String) -> Calculation? {
        // Cheap pre-check: a currency query always contains a 3-letter ISO
        // token or a currency symbol, so non-currency queries never touch
        // the rates provider (which may trigger a network fetch).
        let upper = query.uppercased()
        let looksLikeCurrency = supportedCurrencies.contains { upper.contains($0) }
            || query.contains("$") || query.contains("€") || query.contains("£") || query.contains("¥")
        guard looksLikeCurrency else { return nil }

        guard let table = rates() else { return nil }
        var rates = table.rates
        rates[table.base] = 1
        let base = baseCurrency.uppercased()
        guard rates[base] != nil else { return nil }

        let normalized = query.lowercased()
            .replacingOccurrences(of: "$", with: " usd ")
            .replacingOccurrences(of: "€", with: " eur ")
            .replacingOccurrences(of: "£", with: " gbp ")
            .replacingOccurrences(of: "¥", with: " jpy ")

        for separator in [" to ", " in "] {
            guard let range = normalized.range(of: separator) else { continue }
            let left = String(normalized[..<range.lowerBound])
            let right = String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            let (amount, from) = splitAmountAndUnit(left)
            guard let from, let to = right.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init),
                  let fromRate = rates[from.uppercased()], let toRate = rates[to.uppercased()],
                  from.uppercased() != to.uppercased() else { return nil }
            let value = amount / fromRate * toRate
            return .currency(amount: amount, from: from.uppercased(), to: to.uppercased(), value: value, rateDate: table.date)
        }

        // Bare amount ("25 eur") converts to the base currency.
        let (amount, token) = splitAmountAndUnit(normalized)
        guard let token, let fromRate = rates[token.uppercased()],
              token.uppercased() != base else { return nil }
        let value = amount / fromRate
        return .currency(amount: amount, from: token.uppercased(), to: base, value: value, rateDate: table.date)
    }
}

/// Recursive-descent expression parser: `+ - * / % ^ ( )`, unary ±, decimals.
/// `×÷` and the Unicode minus are tolerated. Nil for anything it can't fully
/// parse (including division by zero); bare numbers are rejected so queries
/// like "42" don't produce calculator rows.
public enum MathEvaluator {
    public static func evaluate(_ input: String) -> Double? {
        guard let tokens = tokenize(input), hasOperator(tokens) else { return nil }
        var parser = Parser(tokens)
        guard let value = parser.expression(), parser.remaining == 0 else { return nil }
        return value.isFinite && !value.isNaN ? value : nil
    }

    private enum Token {
        case number(Double)
        case op(Character)
        case open
        case close
    }

    private static func hasOperator(_ tokens: [Token]) -> Bool {
        tokens.contains { token in
            if case .op = token { return true }
            return false
        }
    }

    private static func tokenize(_ input: String) -> [Token]? {
        var tokens: [Token] = []
        var number = ""

        func flushNumber() -> Bool {
            // Commas are digit separators ("1,000" → 1000); a number must
            // hold at most one decimal point and at least one digit.
            guard !number.isEmpty else { return true }
            let cleaned = number.replacingOccurrences(of: ",", with: "")
            guard cleaned.contains(where: { $0.isNumber }), cleaned.filter({ $0 == "." }).count <= 1,
                  let value = Double(cleaned) else { return false }
            tokens.append(.number(value))
            number = ""
            return true
        }

        for char in input {
            switch char {
            case " ", "\t":
                guard flushNumber() else { return nil }
            case "0"..."9", ".", ",":
                number.append(char)
            case "+", "-", "*", "/", "%", "^", "(", ")":
                guard flushNumber() else { return nil }
                switch char {
                case "(": tokens.append(.open)
                case ")": tokens.append(.close)
                default: tokens.append(.op(char))
                }
            case "×":
                guard flushNumber() else { return nil }
                tokens.append(.op("*"))
            case "÷":
                guard flushNumber() else { return nil }
                tokens.append(.op("/"))
            case "−":
                guard flushNumber() else { return nil }
                tokens.append(.op("-"))
            default:
                return nil
            }
        }
        guard flushNumber() else { return nil }
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var remaining: Int { tokens.count - index }

        init(_ tokens: [Token]) {
            self.tokens = tokens
        }

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while case .op(let op)? = peek(), op == "+" || op == "-" {
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while case .op(let op)? = peek(), op == "*" || op == "/" || op == "%" {
                index += 1
                guard let rhs = power() else { return nil }
                switch op {
                case "*":
                    value *= rhs
                case "/":
                    guard rhs != 0 else { return nil }
                    value /= rhs
                default:
                    guard rhs != 0 else { return nil }
                    value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        /// Exponent binds tighter than * / % and is right-associative
        /// (2^3^2 = 512).
        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if case .op("^")? = peek() {
                index += 1
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func unary() -> Double? {
            if case .op(let op)? = peek(), op == "+" || op == "-" {
                index += 1
                guard let value = unary() else { return nil }
                return op == "-" ? -value : value
            }
            return primary()
        }

        mutating func primary() -> Double? {
            if case .number(let value)? = peek() {
                index += 1
                return value
            }
            if case .open? = peek() {
                index += 1
                guard let value = expression() else { return nil }
                guard case .close? = peek() else { return nil }
                index += 1
                return value
            }
            return nil
        }

        private func peek() -> Token? {
            guard index < tokens.count else { return nil }
            return tokens[index]
        }
    }
}
