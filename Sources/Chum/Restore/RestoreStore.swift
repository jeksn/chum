import Foundation

final class RestoreStore {
    static let shared = RestoreStore()

    private var frames = [String: CGRect]()

    func record(key: String, frame: CGRect) {
        frames[key] = frame
    }

    func frame(for key: String) -> CGRect? {
        frames[key]
    }
}
