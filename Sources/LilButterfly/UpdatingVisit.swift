import AppKit

extension Notification.Name {
    /// Posted by AppDelegate when a self-update ends without relaunching
    /// (failed, or fell back to opening the download page). `object` is
    /// the line the updating card should show before it leaves.
    static let butterflyUpdateDidNotRelaunch = Notification.Name("ButterflyUpdateDidNotRelaunch")
    /// Posted once the new version is installed. `object` is a
    /// RelaunchHandle: the card plays its completion + exit, then calls
    /// `relaunch()` (AppDelegate also calls it after a short fallback, in
    /// case no card is showing to do it).
    static let butterflyUpdateWillRelaunch = Notification.Name("ButterflyUpdateWillRelaunch")
}

final class RelaunchHandle {
    /// "Restarting Butterfly…" for a real update; a preview says so
    /// honestly instead, since nothing actually restarts.
    let completionLine: String
    let relaunch: () -> Void
    init(completionLine: String, relaunch: @escaping () -> Void) {
        self.completionLine = completionLine
        self.relaunch = relaunch
    }
}

/// What happens to an update card once Update Now is tapped — shared by
/// ScreenOverlay and DockedOverlay so all three Update Now buttons behave
/// the same. Motion, in order:
///   1. press (button dips to 95%)          0.22s
///   2. button fades, text crossfades to "Updating Butterfly…",
///      indeterminate bar fades in, wings flutter faster
///   3. held for at least `minimumUpdatingTime` even if the install is
///      instant, so step 2 never just flashes by
///   4. completion: bar fills to the end, text crossfades to
///      "Restarting Butterfly…", wings settle — held `completionHold`
///   5. card fades out, then the new version is opened and this one quits
/// Previously the card left the instant Update Now was tapped and the app
/// quit seconds later mid-frame — it read as simply vanishing.
enum UpdatingVisit {
    static let minimumUpdatingTime: TimeInterval = 1.6
    static let completionHold: TimeInterval = 1.0
    /// Matches BubbleView.fadeOutDuration plus a beat, so the card is
    /// fully gone before the process ends.
    static let exitBeforeRelaunch: TimeInterval = 0.5

    /// Returns observer tokens; the caller removes them in leaveNow.
    static func begin(
        bubble: BubbleView,
        butterfly: ButterflyView,
        buttonWindows: [NSPanel],
        leave: @escaping () -> Void
    ) -> [NSObjectProtocol] {
        let startedAt = Date()
        butterfly.setFlutterRate(1.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            buttonWindows.forEach { $0.fadeOutAndOrderOut(duration: 0.2) }
            bubble.showUpdating()
        }
        // Safety net: if the install somehow hangs, don't hold the card
        // open forever — the update keeps going in the background and the
        // menu still shows "Updating…".
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { leave() }

        let failed = NotificationCenter.default.addObserver(forName: .butterflyUpdateDidNotRelaunch, object: nil, queue: .main) { note in
            let wait = max(0, 0.6 - Date().timeIntervalSince(startedAt))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                bubble.showUpdateFailed(note.object as? String ?? "Update failed — try the menu.")
                butterfly.setFlutterRate(1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { leave() }
            }
        }
        let installed = NotificationCenter.default.addObserver(forName: .butterflyUpdateWillRelaunch, object: nil, queue: .main) { note in
            guard let handle = note.object as? RelaunchHandle else { return }
            let wait = max(0, minimumUpdatingTime - Date().timeIntervalSince(startedAt))
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                bubble.showUpdateComplete(handle.completionLine)
                butterfly.setFlutterRate(1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + completionHold) {
                    leave()
                    DispatchQueue.main.asyncAfter(deadline: .now() + exitBeforeRelaunch) { handle.relaunch() }
                }
            }
        }
        return [failed, installed]
    }
}
