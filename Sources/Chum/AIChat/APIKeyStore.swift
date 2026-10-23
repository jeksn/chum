import Foundation
import ChumCore

/// The AI Chat API key, stored as a local file with owner-only
/// permissions (600) in Application Support. NOT the Keychain: item ACLs
/// anchor to the creating binary's code signature, so with the
/// self-signed dev identity every rebuild looks like a different app and
/// macOS demanded the login password on every read. The app deliberately
/// never touches the Keychain — a leftover item from the brief Keychain
/// era (service "com.chum.app") is left for the user to remove in
/// Keychain Access if they care.
enum APIKeyStore {
    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Chum/aikey")
    }

    /// Reads the key from the file store, migrating the UserDefaults
    /// placeholder era once.
    static func read() -> String? {
        if let url = fileURL,
           let data = try? Data(contentsOf: url),
           let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }
        if let legacy = UserDefaults.standard.string(forKey: AppSettings.aiAPIKeyKey), !legacy.isEmpty {
            save(legacy)
            UserDefaults.standard.removeObject(forKey: AppSettings.aiAPIKeyKey)
            return legacy
        }
        return nil
    }

    static func save(_ key: String) {
        guard let url = fileURL, !key.isEmpty else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(key.utf8).write(to: url, options: .atomic)
        // Owner-only: the key stays readable by this user and nothing else.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func delete() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
