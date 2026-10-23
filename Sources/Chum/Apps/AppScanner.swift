import AppKit
import Foundation
import ChumCore

struct AppChooserItem: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleURL: URL
    let bundleIdentifier: String?
    let icon: NSImage?

    var appShortcut: AppShortcut {
        AppShortcut(
            name: name,
            kind: .app,
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL
        )
    }
}

enum AppScanner {
    /// Posted when a refresh changed the cached app list (e.g. an app was
    /// installed or removed while Chum runs). Posted from a background queue.
    static let appsDidUpdate = Notification.Name("ChumAppsDidUpdate")

    private static let cacheQueue = DispatchQueue(label: "chum.appscanner.cache")
    private static var cached: [AppChooserItem] = []
    /// Reusable scan results keyed by bundle path, so a refresh only pays the
    /// expensive part (Bundle load + icon) for apps that are actually new.
    private static var entries: [String: AppChooserItem] = [:]
    private static var watchers: [DispatchSourceFileSystemObject] = []
    private static var pendingRefresh: DispatchWorkItem?

    static let directories: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
    ]

    static func cachedApps() -> [AppChooserItem] {
        cacheQueue.sync { cached }
    }

    static func refresh() {
        DispatchQueue.global(qos: .utility).async {
            scan(reusing: cacheQueue.sync { entries }, updatesCache: true)
        }
    }

    /// Watches the app directories so apps installed while Chum runs show up
    /// in the launcher without a relaunch — the same reason Spotlight always
    /// has new apps (a filesystem watcher), minus the system daemon. The
    /// launcher keeps serving from the cached list; the watcher only triggers
    /// background refreshes.
    static func startWatching() {
        cacheQueue.async {
            guard watchers.isEmpty else { return }
            for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
                let fd = open(directory.path, O_EVTONLY)
                guard fd >= 0 else { continue }
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd,
                    eventMask: .write,
                    queue: cacheQueue
                )
                source.setEventHandler { scheduleRefresh() }
                source.resume()
                watchers.append(source)
            }
        }
    }

    /// Debounced refresh: installing an app writes many events while the
    /// bundle copies; wait for the directory to settle before scanning so a
    /// half-copied .app is never picked up. Runs on cacheQueue (the watchers'
    /// queue), so the cache is read directly — a sync call here would
    /// deadlock.
    private static func scheduleRefresh() {
        pendingRefresh?.cancel()
        let snapshot = entries
        let work = DispatchWorkItem { scan(reusing: snapshot, updatesCache: true) }
        pendingRefresh = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    static func installedApps() -> [AppChooserItem] {
        scan(reusing: [:], updatesCache: false).items
    }

    /// Scans the app directories, reusing cached entries for paths that are
    /// already known. Updates the persistent cache (and posts
    /// `appsDidUpdate`) when `updatesCache` is set — one-shot
    /// `installedApps()` scans leave the cache untouched.
    @discardableResult
    private static func scan(reusing snapshot: [String: AppChooserItem], updatesCache: Bool) -> (items: [AppChooserItem], entries: [String: AppChooserItem]) {
        var seen = Set<String>()
        var items: [AppChooserItem] = []
        var newEntries: [String: AppChooserItem] = [:]

        func addApp(at url: URL) {
            let path = url.path
            guard !seen.contains(path) else { return }
            seen.insert(path)
            guard let item = snapshot[path] ?? makeItem(for: url) else { return }
            items.append(item)
            newEntries[path] = item
        }

        for directory in directories {
            guard FileManager.default.fileExists(atPath: directory.path),
                  let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsPackageDescendants, .skipsHiddenFiles],
                    errorHandler: nil
                  ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "app" else { continue }
                addApp(at: fileURL)
            }
        }

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let url = app.bundleURL else { continue }
            addApp(at: url)
        }

        let sorted = items.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if updatesCache {
            let changed = cacheQueue.sync {
                let changed = cached != sorted
                entries = newEntries
                cached = sorted
                return changed
            }
            if changed {
                NotificationCenter.default.post(name: appsDidUpdate, object: nil)
            }
        }
        return (sorted, newEntries)
    }

    private static func makeItem(for url: URL) -> AppChooserItem? {
        let bundle = Bundle(url: url)
        let bundleID = bundle?.bundleIdentifier

        let name = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
            ?? FileManager.default.displayName(atPath: url.path)

        let icon = downsizedIcon(forFile: url.path)
        return AppChooserItem(
            id: bundleID ?? url.path,
            name: name,
            bundleURL: url,
            bundleIdentifier: bundleID,
            icon: icon
        )
    }

    /// `NSWorkspace.icon` returns the app's full-size icon (up to 1024px).
    /// Rows render at 22pt, so downsample once at scan time instead of
    /// having every row draw scale a large representation on each render.
    private static func downsizedIcon(forFile path: String, size: CGFloat = 64) -> NSImage? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        guard icon.isValid, icon.size.width > size else { return icon }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size),
            pixelsHigh: Int(size),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return icon }
        rep.size = NSSize(width: size, height: size)

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            return icon
        }
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }
}
