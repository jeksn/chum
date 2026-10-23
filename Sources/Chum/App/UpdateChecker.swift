import AppKit
import Foundation
import ChumCore

enum UpdateChecker {
    private static let repo = "jeksn/chum"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func checkForUpdates() {
        Task {
            let release = await fetchLatestRelease()
            await MainActor.run { present(release) }
        }
    }

    static func checkForUpdatesOnLaunch() {
        Task {
            let release = await fetchLatestRelease()
            await MainActor.run { presentUpdateIfAvailable(release) }
        }
    }

    private static func presentUpdateIfAvailable(_ release: Release?) {
        guard let release, VersionCompare.isNewer(release.version, than: currentVersion) else { return }
        let alert = NSAlert()
        alert.messageText = "Chum \(release.version) is available"
        alert.informativeText = "You are running version \(currentVersion)."
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if let dmgURL = release.dmgURL {
                downloadAndInstall(dmgURL, version: release.version)
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    private struct Release {
        let version: String
        let pageURL: URL
        let dmgURL: URL?
    }

    private static func fetchLatestRelease() async -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard
            let (data, _) = try? await URLSession.shared.data(for: request),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String,
            let htmlURL = json["html_url"] as? String
        else { return nil }

        let dmgURL = (json["assets"] as? [[String: Any]])?
            .compactMap { asset -> URL? in
                guard let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                      let url = asset["browser_download_url"] as? String else { return nil }
                return URL(string: url)
            }
            .first

        return Release(version: tag, pageURL: URL(string: htmlURL)!, dmgURL: dmgURL)
    }

    private static func present(_ release: Release?) {
        guard let release else {
            showAlert(
                title: "Could not check for updates",
                message: "The latest release could not be fetched. Check your internet connection and try again."
            )
            return
        }

        guard VersionCompare.isNewer(release.version, than: currentVersion) else {
            showAlert(
                title: "You're up to date",
                message: "Chum \(currentVersion) is the latest version."
            )
            return
        }

        let alert = NSAlert()
        alert.messageText = "Chum \(release.version) is available"
        alert.informativeText = "You are running version \(currentVersion)."
        alert.addButton(withTitle: "Download and Install")
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if let dmgURL = release.dmgURL {
                downloadAndInstall(dmgURL, version: release.version)
            } else {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    private static func downloadAndInstall(_ dmgURL: URL, version: String) {
        HUD.show("Downloading update…")
        Task {
            do {
                let (downloaded, _) = try await URLSession.shared.download(from: dmgURL)
                let dmgDestination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Chum-\(version).dmg")
                try? FileManager.default.removeItem(at: dmgDestination)
                try FileManager.default.moveItem(at: downloaded, to: dmgDestination)

                await MainActor.run {
                    HUD.show("Installing update…")
                }
                try install(dmg: dmgDestination)
                await MainActor.run {
                    relaunch()
                }
            } catch {
                await MainActor.run {
                    HUD.show("Update failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private static func install(dmg: URL) throws {
        let output = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", dmg.path])
        guard let mountPoint = output
            .split(separator: "\n")
            .reversed()
            .first(where: { $0.contains("/Volumes/") })?
            .components(separatedBy: "\t")
            .last
        else {
            throw UpdateError.mountFailed
        }
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint, "-force"])
        }

        let source = URL(fileURLWithPath: mountPoint).appendingPathComponent("Chum.app")
        let destination = URL(fileURLWithPath: "/Applications/Chum.app")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "sleep 1; pkill -x Chum; sleep 0.5; open /Applications/Chum.app"]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed(executable)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

enum UpdateError: LocalizedError {
    case mountFailed
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .mountFailed: return "Could not mount the update disk image"
        case .commandFailed(let command): return "Failed to run \(command)"
        }
    }
}
