import Foundation

enum ConfigMigration {
    static func migrateIfNeeded() {
        let fm = FileManager.default
        guard let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        let oldDir = supportDir.appendingPathComponent("Chum", isDirectory: true)
        let newDir = supportDir.appendingPathComponent("Chum", isDirectory: true)

        guard fm.fileExists(atPath: oldDir.path),
              !fm.fileExists(atPath: newDir.path) else { return }

        do {
            try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try fm.copyItem(at: oldDir, to: newDir)
        } catch {
            NSLog("ConfigMigration: failed to copy \(oldDir.path) → \(newDir.path): \(error)")
        }
    }
}
