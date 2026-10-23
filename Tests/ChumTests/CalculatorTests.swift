import ChumCore

enum CalculatorTests {
    static func runAll(_ t: TestRunner) {
        runMathTests(t)
        runUnitTests(t)
        runCurrencyTests(t)
        runFormattingTests(t)
    }

    private static func runMathTests(_ t: TestRunner) {
        t.run("Calculator.simpleMath") {
            t.check(MathEvaluator.evaluate("2+2") == 4, "2+2 should be 4")
            t.check(MathEvaluator.evaluate("(12+8)*2.5") == 50, "parenthesized math should be 50")
            t.check(MathEvaluator.evaluate("2^10 / 4") == 256, "exponent/division should be 256")
        }

        t.run("Calculator.precedence") {
            t.check(MathEvaluator.evaluate("2+3*4") == 14, "multiplication binds tighter")
            t.check(MathEvaluator.evaluate("10-2/2") == 9, "division binds tighter")
            t.check(MathEvaluator.evaluate("2^3^2") == 512, "exponent is right-associative")
            t.check(MathEvaluator.evaluate("1,000+0") == 1000, "comma separators are stripped")
        }

        t.run("Calculator.unaryAndSymbols") {
            t.check(MathEvaluator.evaluate("-5+3") == -2, "leading unary minus")
            t.check(MathEvaluator.evaluate("2*-3") == -6, "unary minus after operator")
            t.check(MathEvaluator.evaluate("-(2+3)") == -5, "unary minus with parens")
            t.check(MathEvaluator.evaluate("3×4") == 12, "× tolerated")
            t.check(MathEvaluator.evaluate("10÷4") == 2.5, "÷ tolerated")
        }

        t.run("Calculator.invalidMath") {
            t.check(MathEvaluator.evaluate("5/0") == nil, "division by zero")
            t.check(MathEvaluator.evaluate("2+") == nil, "trailing operator")
            t.check(MathEvaluator.evaluate("(2+3") == nil, "unclosed paren")
            t.check(MathEvaluator.evaluate("left half") == nil, "words are not math")
            t.check(MathEvaluator.evaluate("42") == nil, "bare numbers are not calculations")
            t.check(MathEvaluator.evaluate("1.2.3+1") == nil, "malformed number")
        }
    }

    private static func runUnitTests(_ t: TestRunner) {
        t.run("Calculator.unitConversions") {
            let km = Calculator.parse(query: "5 km to miles")
            guard case .units(_, let value, let label)? = km else {
                t.check(false, "5 km to miles should parse")
                return
            }
            t.check(abs(value - 3.106856) < 0.000001, "5 km = 3.106856 mi, got \(value)")
            t.check(label == "mi", "output label should be mi")

            let lb = Calculator.parse(query: "100 kg in lb")
            guard case .units(_, let value, _)? = lb else {
                t.check(false, "100 kg in lb should parse")
                return
            }
            t.check(abs(value - 220.462262) < 0.000001, "100 kg = 220.462262 lb, got \(value)")
        }

        t.run("Calculator.temperature") {
            let frozen = Calculator.parse(query: "0 c to f")
            guard case .units(_, let value, _)? = frozen else {
                t.check(false, "0 c to f should parse")
                return
            }
            t.check(value == 32, "0 °C = 32 °F, got \(value)")

            let boiling = Calculator.parse(query: "100 c to f")
            guard case .units(_, let value, _)? = boiling else {
                t.check(false, "100 c to f should parse")
                return
            }
            t.check(value == 212, "100 °C = 212 °F, got \(value)")

            let warm = Calculator.parse(query: "72 f to c")
            guard case .units(_, let value, _)? = warm else {
                t.check(false, "72 f to c should parse")
                return
            }
            t.check(abs(value - 22.222222) < 0.000001, "72 °F = 22.222222 °C, got \(value)")
        }

        t.run("Calculator.bareUnitsFollowPreference") {
            // Metric preferred → bare imperial units convert to metric.
            guard case .units(_, let value, let label)? = Calculator.parse(query: "72 f", preferredUnits: "metric") else {
                t.check(false, "72 f with metric preference should parse")
                return
            }
            t.check(label == "°C", "output is celsius, got \(label)")
            t.check(abs(value - 22.222222) < 0.000001, "72 f = 22.222222 °C, got \(value)")

            // Imperial preferred → bare metric units convert to imperial.
            guard case .units(_, let value, _)? = Calculator.parse(query: "5 km", preferredUnits: "imperial") else {
                t.check(false, "5 km with imperial preference should parse")
                return
            }
            t.check(abs(value - 3.106856) < 0.000001, "5 km = 3.106856 mi, got \(value)")

            // Same system → no row.
            t.check(Calculator.parse(query: "5 km", preferredUnits: "metric") == nil, "same-system bare units produce no row")
        }

        t.run("Calculator.invalidUnits") {
            t.check(Calculator.parse(query: "5 parsecs to mi") == nil, "unknown unit")
            t.check(Calculator.parse(query: "5 kg to mi") == nil, "cross-dimension conversion")
            t.check(Calculator.parse(query: "km to") == nil, "missing target")
        }
    }

    private static func runCurrencyTests(_ t: TestRunner) {
        let table: Calculator.RatesTable = (base: "USD", date: "2026-09-30", rates: ["EUR": 0.92, "GBP": 0.78, "JPY": 150])

        t.run("Calculator.currencyConversion") {
            guard case .currency(_, "USD", "EUR", let value, let date)? =
                Calculator.parse(query: "10 usd to eur", rates: table, baseCurrency: "USD") else {
                t.check(false, "10 usd to eur should parse")
                return
            }
            t.check(abs(value - 9.2) < 0.000001, "10 USD = 9.20 EUR, got \(value)")
            t.check(date == "2026-09-30", "rate date carried through")

            guard case .currency(_, "EUR", "USD", let value, _)? =
                Calculator.parse(query: "10 eur to usd", rates: table, baseCurrency: "USD") else {
                t.check(false, "10 eur to usd should parse")
                return
            }
            t.check(abs(value - 10.869565) < 0.000001, "10 EUR = 10.869565 USD, got \(value)")
        }

        t.run("Calculator.bareAmountToBase") {
            guard case .currency(_, "EUR", "USD", let value, _)? =
                Calculator.parse(query: "25 eur", rates: table, baseCurrency: "USD") else {
                t.check(false, "25 eur should parse to base")
                return
            }
            t.check(abs(value - 27.173913) < 0.000001, "25 EUR = 27.173913 USD, got \(value)")
        }

        t.run("Calculator.currencySymbolsAndNoRates") {
            guard case .currency(_, _, "EUR", let value, _)? =
                Calculator.parse(query: "10$ to eur", rates: table, baseCurrency: "USD") else {
                t.check(false, "$ symbol should parse as USD")
                return
            }
            t.check(abs(value - 9.2) < 0.000001, "10$ = 9.20 EUR, got \(value)")

            t.check(Calculator.parse(query: "10 usd to eur", rates: nil, baseCurrency: "USD") == nil, "no rates → no row")
            t.check(Calculator.parse(query: "10 usd to usd", rates: table, baseCurrency: "USD") == nil, "same currency → no row")
        }
    }

    private static func runFormattingTests(_ t: TestRunner) {
        t.run("Calculator.displays") {
            guard case .math = Calculator.parse(query: "2+2") else {
                t.check(false, "2+2 should parse as math")
                return
            }
            let math = Calculator.parse(query: "2+2")!
            t.check(math.display == "= 4", "math display, got \(math.display)")
            t.check(math.clipboardValue == "4", "clipboard value, got \(math.clipboardValue)")

            guard case .currency(_, "USD", "EUR", let value, _)? =
                Calculator.parse(query: "10 usd to eur", rates: (base: "USD", date: nil, rates: ["EUR": 0.92]), baseCurrency: "USD") else {
                t.check(false, "10 usd to eur should parse")
                return
            }
            t.check(abs(value - 9.2) < 0.000001, "currency value, got \(value)")
            let currency = Calculator.parse(query: "10 usd to eur", rates: (base: "USD", date: nil, rates: ["EUR": 0.92]), baseCurrency: "USD")!
            t.check(currency.display == "= 9.20 EUR", "currency display, got \(currency.display)")
            t.check(currency.clipboardValue == "9.2", "currency clipboard trims zeros, got \(currency.clipboardValue)")
        }
    }
}
