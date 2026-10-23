import ChumCore
import AppKit

final class CommandApplier {
    static let shared = CommandApplier()

    private let restoreStore = RestoreStore.shared

    private var lastCycleCommandID: UUID?
    private var halfCycleStep = 0

    /// When half cycling is on, consecutive applications of the same command
    /// advance the step (1/2 → 1/3 → 2/3); any other command resets it.
    private func effectiveCommand(for command: WindowCommand) -> WindowCommand {
        guard AppSettings.cycleHalves, command.halfCycleAxis != nil else { return command }
        if lastCycleCommandID == command.id {
            halfCycleStep = (halfCycleStep + 1) % WindowCommand.halfCycleFractions.count
        } else {
            halfCycleStep = 0
            lastCycleCommandID = command.id
        }
        return command.cycledHalf(atStep: halfCycleStep)
    }

    func apply(_ command: WindowCommand, target: WindowRef? = nil) {
        guard Accessibility.ensureTrusted(prompt: true) else {
            HUD.show("Enable Accessibility in System Settings")
            return
        }
        guard let target = target ?? WindowManipulator.frontmostWindow() else {
            HUD.show("No focused window")
            return
        }
        guard let currentFrame = WindowManipulator.frame(of: target.window) else {
            HUD.show("Could not read window geometry")
            return
        }

        if command.id == WindowAction.nextDisplay.commandID {
            moveToNextDisplay(target: target, currentFrame: currentFrame)
            return
        }

        guard let screen = WindowManipulator.screen(containing: currentFrame) else {
            HUD.show("Could not detect display")
            return
        }

        let usable = LayoutEngine.usableArea(in: screen.visibleFrame, gap: CGFloat(AppSettings.gap))
        let effective = effectiveCommand(for: command)
        let request = LayoutEngine.Request(
            usableArea: usable,
            currentFrame: currentFrame,
            width: effective.width,
            height: effective.height,
            anchor: effective.anchor,
            offsetX: effective.offsetX,
            offsetY: effective.offsetY,
            interGap: CGFloat(AppSettings.gap)
        )
        let newFrame = LayoutEngine.frame(for: request)

        restoreStore.record(key: target.restoreKey, frame: currentFrame)

        switch WindowManipulator.setFrame(target, to: newFrame) {
        case .applied:
            break
        case .adjusted(let actual):
            // The app kept a different size than requested (minimum window
            // size, etc.). Re-anchor the actual size so the anchored edge
            // lands where the layout put it — otherwise a right-anchored
            // window keeps the position computed for the wider request and
            // hangs off the screen edge. No interGap here: the gap was spent
            // in the original request.
            let corrected = LayoutEngine.frame(for: LayoutEngine.Request(
                usableArea: usable,
                currentFrame: actual,
                width: .points(actual.width),
                height: .points(actual.height),
                anchor: effective.anchor,
                offsetX: effective.offsetX,
                offsetY: effective.offsetY
            ))
            WindowManipulator.setFrame(target, to: corrected)
            HUD.show("App limited the window size")
        case .failed(let error):
            HUD.show("Could not resize window (\(error.rawValue))")
        }
    }

    private func moveToNextDisplay(target: WindowRef, currentFrame: CGRect) {
        guard let currentScreen = WindowManipulator.screen(containing: currentFrame) else {
            HUD.show("Could not detect display")
            return
        }
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            HUD.show("Only one display connected")
            return
        }
        guard let currentIndex = screens.firstIndex(of: currentScreen) else {
            HUD.show("Could not detect display")
            return
        }
        let nextScreen = screens[(currentIndex + 1) % screens.count]
        let currentUsable = LayoutEngine.usableArea(in: currentScreen.visibleFrame, gap: CGFloat(AppSettings.gap))
        let nextUsable = LayoutEngine.usableArea(in: nextScreen.visibleFrame, gap: CGFloat(AppSettings.gap))
        let newFrame = LayoutEngine.frameForNextDisplay(
            currentFrame: currentFrame,
            currentUsable: currentUsable,
            nextUsable: nextUsable
        )

        restoreStore.record(key: target.restoreKey, frame: currentFrame)

        switch WindowManipulator.setFrame(target, to: newFrame) {
        case .applied: break
        case .adjusted: HUD.show("App limited the window size")
        case .failed(let error): HUD.show("Could not move window (\(error.rawValue))")
        }
    }

    func restore(target: WindowRef? = nil) {
        guard Accessibility.ensureTrusted(prompt: true) else {
            HUD.show("Enable Accessibility in System Settings")
            return
        }
        guard let target = target ?? WindowManipulator.frontmostWindow() else {
            HUD.show("No focused window")
            return
        }
        guard let currentFrame = WindowManipulator.frame(of: target.window) else {
            HUD.show("Could not read window geometry")
            return
        }
        guard let previousFrame = restoreStore.frame(for: target.restoreKey) else {
            HUD.show("Nothing to restore")
            return
        }

        restoreStore.record(key: target.restoreKey, frame: currentFrame)

        switch WindowManipulator.setFrame(target, to: previousFrame) {
        case .applied: break
        case .adjusted: HUD.show("App limited the window size")
        case .failed(let error): HUD.show("Could not restore window (\(error.rawValue))")
        }
    }
}
