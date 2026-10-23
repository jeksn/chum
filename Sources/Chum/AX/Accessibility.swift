import ApplicationServices

enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func ensureTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static var systemSettingsURL: URL {
        URL(string: "x-apple.systemsettings:com.apple.preference.security?Privacy_Accessibility")!
    }

    static func openSystemSettings() {
        for urlString in [
            "x-apple.systemsettings:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ] where openURL([urlString]) {
            return
        }
        openURL(["-b", "com.apple.systempreferences"])
    }

    @discardableResult
    private static func openURL(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
