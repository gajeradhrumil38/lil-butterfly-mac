import AppKit
import CoreGraphics

/// Polls for the frontmost app's topmost on-screen window and reports its
/// frame (in AppKit's bottom-left-origin screen coordinates) whenever it
/// changes — lets a docked butterfly follow whichever window the user is
/// actually working in, instead of a fixed screen edge.
///
/// Uses CGWindowListCopyWindowInfo, which reports window bounds without
/// needing Accessibility or Screen Recording permission — only a window's
/// *title* is gated behind Screen Recording on recent macOS; bounds are
/// not, since they reveal nothing about the window's content.
final class WindowTracker {
    private var timer: Timer?
    private var lastFrame: CGRect?
    var onFrameChange: ((CGRect?) -> Void)?

    func start(interval: TimeInterval = 0.4) {
        stop()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastFrame = nil
    }

    private func poll() {
        let frame = Self.frontmostWindowFrame()
        guard frame != lastFrame else { return }
        lastFrame = frame
        onFrameChange?(frame)
    }

    /// The frontmost app's own topmost normal window, converted from
    /// Quartz's top-left-origin screen coordinates to AppKit's
    /// bottom-left-origin ones. nil when there's no such window (e.g. the
    /// desktop itself is focused, or the frontmost app has no on-screen
    /// windows) — the caller falls back to a fixed spot in that case.
    private static func frontmostWindowFrame() -> CGRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let mainScreenHeight = NSScreen.screens.first?.frame.height,
              let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        // CGWindowListCopyWindowInfo lists windows front-to-back, so the
        // first one owned by the frontmost app and sitting at the normal
        // window layer (0 — above that is menus/panels/etc., which aren't
        // "the window" in any useful sense here) is that app's topmost
        // real window.
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == frontApp.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { continue }
            return CGRect(x: x, y: mainScreenHeight - y - height, width: width, height: height)
        }
        return nil
    }
}
