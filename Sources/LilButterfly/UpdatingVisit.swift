import AppKit

extension Notification.Name {
    /// Posted by AppDelegate when a self-update ends without relaunching
    /// (failed, or fell back to opening the download page). `object` is
    /// the line the updating card should show before it leaves.
    static let butterflyUpdateDidNotRelaunch = Notification.Name("ButterflyUpdateDidNotRelaunch")
}

/// What happens to an update card once Update Now is tapped — shared by
/// ScreenOverlay and DockedOverlay so all three Update Now buttons behave
/// the same. The card stays up showing an indeterminate bar until the new
/// version relaunches (success terminates this process, so there's
/// nothing to clean up), or a failure notice arrives.
enum UpdatingVisit {
    /// Returns the observer token; the caller removes it in leaveNow.
    static func begin(
        bubble: BubbleView,
        butterfly: ButterflyView,
        buttonWindows: [NSPanel],
        leave: @escaping () -> Void
    ) -> NSObjectProtocol {
        // A little more urgency in the wings while it works.
        butterfly.setFlutterRate(1.4)
        // Let the button's press animation finish before it fades away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            buttonWindows.forEach { $0.fadeOutAndOrderOut(duration: 0.2) }
            bubble.showUpdating()
        }
        // Safety net: if the install somehow hangs, don't hold the card
        // open forever — the update keeps going in the background and the
        // menu still shows "Updating…".
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { leave() }
        return NotificationCenter.default.addObserver(forName: .butterflyUpdateDidNotRelaunch, object: nil, queue: .main) { note in
            bubble.showUpdateFailed(note.object as? String ?? "Update failed — try the menu.")
            butterfly.setFlutterRate(1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { leave() }
        }
    }
}
