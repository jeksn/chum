import Foundation

final class TestRunner {
    private(set) var failures = [String]()
    private(set) var passCount = 0
    private var currentTest = ""

    func run(_ name: String, _ body: () throws -> Void) {
        currentTest = name
        let failuresBefore = failures.count
        do {
            try body()
        } catch {
            failures.append("\(name): threw \(error)")
            print("FAIL \(name) (threw \(error))")
            return
        }
        if failures.count > failuresBefore {
            print("FAIL \(name)")
        } else {
            passCount += 1
            print("PASS \(name)")
        }
    }

    func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures.append("\(currentTest): \(message)")
            print("  check failed: \(message)")
        }
    }

    func expectThrows(_ message: String, _ body: () throws -> Void) {
        do {
            try body()
            check(false, message)
        } catch {
        }
    }

    var summary: String {
        let total = passCount + failures.count
        return "\(total) tests, \(passCount) passed, \(failures.count) failed"
    }

    var exitCode: Int32 {
        failures.isEmpty ? 0 : 1
    }
}
