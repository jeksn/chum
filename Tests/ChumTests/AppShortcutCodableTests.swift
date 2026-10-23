import Foundation
import ChumCore

enum AppShortcutCodableTests {
    static func runAll(_ t: TestRunner) {
        t.run("AppShortcut.appRoundTrip") {
            let shortcut = AppShortcut(
                name: "Safari",
                kind: .app,
                bundleIdentifier: "com.apple.Safari",
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app")
            )
            let data = try JSONEncoder().encode(shortcut)
            let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)
            t.check(decoded == shortcut, "round trip mismatch")
        }

        t.run("AppShortcut.urlRoundTrip") {
            let shortcut = AppShortcut(
                name: "Obsidian",
                kind: .url,
                urlString: "obsidian://open?vault=Main&file=Work/Todo"
            )
            let data = try JSONEncoder().encode(shortcut)
            let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)
            t.check(decoded == shortcut, "round trip mismatch")
            t.check(decoded.url != nil, "url should be non-nil")
        }

        t.run("AppShortcut.folderRoundTrip") {
            let shortcut = AppShortcut(
                name: "Downloads",
                kind: .folder,
                folderURL: URL(fileURLWithPath: "/Users/jeksn/Downloads")
            )
            let data = try JSONEncoder().encode(shortcut)
            let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)
            t.check(decoded == shortcut, "round trip mismatch")
            t.check(decoded.folderURL != nil, "folderURL should be non-nil")
        }

        t.run("AppShortcut.nilBundleURLRoundTrip") {
            let shortcut = AppShortcut(
                name: "Custom",
                kind: .app,
                bundleIdentifier: "com.example.custom",
                bundleURL: nil
            )
            let data = try JSONEncoder().encode(shortcut)
            let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)
            t.check(decoded == shortcut, "round trip mismatch")
            t.check(decoded.bundleURL == nil, "bundleURL should be nil")
        }

        t.run("AppShortcut.encodingShape") {
            let shortcut = AppShortcut(
                name: "Finder",
                kind: .app,
                bundleIdentifier: "com.apple.finder",
                bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            )
            let data = try JSONEncoder().encode(shortcut)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            t.check(json?["name"] as? String == "Finder", "name mismatch")
            t.check(json?["kind"] as? String == "app", "kind mismatch")
            t.check(json?["bundleIdentifier"] as? String == "com.apple.finder", "bundleIdentifier mismatch")
            t.check(json?["bundleURL"] as? String == "file:///System/Library/CoreServices/Finder.app/", "bundleURL mismatch")
        }

        t.run("AppShortcut.decodesMissingFields") {
            let json = #"{"name": "Test"}"#
            let decoded = try JSONDecoder().decode(AppShortcut.self, from: Data(json.utf8))
            t.check(decoded.name == "Test", "name mismatch")
            t.check(decoded.kind == .app, "kind should default to app")
            t.check(decoded.bundleIdentifier == nil, "bundleIdentifier should default to nil")
            t.check(decoded.bundleURL == nil, "bundleURL should default to nil")
            t.check(decoded.urlString == nil, "urlString should default to nil")
            t.check(decoded.folderURL == nil, "folderURL should default to nil")
            t.check(decoded.showInMenuBar == false, "showInMenuBar should default to false")
            t.check(decoded.id != UUID(), "id should be generated")
        }

        t.run("AppShortcut.showInMenuBarRoundTrip") {
            let shortcut = AppShortcut(
                name: "Pinned",
                kind: .url,
                urlString: "https://example.com",
                showInMenuBar: true
            )
            let data = try JSONEncoder().encode(shortcut)
            let decoded = try JSONDecoder().decode(AppShortcut.self, from: data)
            t.check(decoded == shortcut, "round trip mismatch")
            t.check(decoded.showInMenuBar, "showInMenuBar should round-trip as true")
        }

        t.run("AppShortcut.legacyIsURLMigration") {
            let json = #"{"name": "Old URL", "isURL": true, "urlString": "https://example.com"}"#
            let decoded = try JSONDecoder().decode(AppShortcut.self, from: Data(json.utf8))
            t.check(decoded.name == "Old URL", "name mismatch")
            t.check(decoded.kind == .url, "legacy isURL should become url kind")
            t.check(decoded.urlString == "https://example.com", "urlString mismatch")
        }

        t.run("AppShortcut.validity") {
            let withID = AppShortcut(name: "A", kind: .app, bundleIdentifier: "com.a", bundleURL: nil)
            t.check(withID.isValid, "shortcut with bundle identifier should be valid")

            let withURL = AppShortcut(name: "B", kind: .app, bundleIdentifier: nil, bundleURL: URL(fileURLWithPath: "/B.app"))
            t.check(withURL.isValid, "shortcut with bundle URL should be valid")

            let empty = AppShortcut(name: "C", kind: .app, bundleIdentifier: "", bundleURL: nil)
            t.check(!empty.isValid, "shortcut with empty identifier and no URL should be invalid")

            let link = AppShortcut(name: "D", kind: .url, urlString: "https://example.com")
            t.check(link.isValid, "URL shortcut should be valid")

            let badLink = AppShortcut(name: "E", kind: .url, urlString: "")
            t.check(!badLink.isValid, "empty URL should be invalid")

            let folder = AppShortcut(name: "F", kind: .folder, folderURL: URL(fileURLWithPath: "/Users"))
            t.check(folder.isValid, "folder shortcut should be valid")

            let noFolder = AppShortcut(name: "G", kind: .folder)
            t.check(!noFolder.isValid, "folder shortcut without folder should be invalid")
        }
    }
}
