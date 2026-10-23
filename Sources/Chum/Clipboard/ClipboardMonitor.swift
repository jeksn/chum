import AppKit
import Foundation
import ChumCore

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private let stateLock = NSLock()
    private var captureSuspended = false

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Pauses history capture while another component (snippet expansion)
    /// temporarily takes over the pasteboard.
    func suspendCapture() {
        stateLock.lock()
        captureSuspended = true
        stateLock.unlock()
    }

    /// Resumes capture and swallows the changeCount delta produced during the
    /// suspension so neither the override nor the restored content is
    /// re-captured into the history.
    func resumeCapture() {
        stateLock.lock()
        captureSuspended = false
        lastChangeCount = NSPasteboard.general.changeCount
        stateLock.unlock()
    }

    private var isCaptureSuspended: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return captureSuspended
    }

    func start() {
        guard AppSettings.clipboardEnabled else { return }
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard !isCaptureSuspended else { return }
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        stateLock.lock()
        let changed = currentCount != lastChangeCount
        if changed { lastChangeCount = currentCount }
        stateLock.unlock()
        guard changed else { return }

        if let item = readItem(from: pasteboard) {
            DispatchQueue.main.async {
                ClipboardStore.shared.add(item)
            }
        }
    }

    private func readItem(from pasteboard: NSPasteboard) -> ClipboardItem? {
        let types = pasteboard.types ?? []

        if types.contains(.fileURL) {
            if let url = pasteboard.string(forType: .fileURL).flatMap(URL.init(fileURLWithPath:)) {
                let urlString = url.absoluteString
                return ClipboardItem(kind: .fileURL, fileURLString: urlString)
            }
        }

        if types.contains(.tiff) || types.contains(.png) {
            if let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
                return ClipboardItem(kind: .image, imageData: data)
            }
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return ClipboardItem(kind: .text, textContent: text)
        }

        return nil
    }
}
