import AppKit

/// Detects meeting apps locally without reading browser tabs, recording audio,
/// or sending anything over the network. A browser-based Google Meet session
/// can still be handled with Pause because Chrome/Safari do not expose the
/// active tab safely without Accessibility permission.
enum MeetingDetector {
    private static let meetingBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.google.meet",
    ]

    private static let meetingNames = ["Zoom", "Zoom.us", "Microsoft Teams", "Google Meet"]

    static var isMeetingAppActive: Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if let bundleID = app.bundleIdentifier, meetingBundleIDs.contains(bundleID) { return true }
        guard let name = app.localizedName else { return false }
        return meetingNames.contains { name.localizedCaseInsensitiveCompare($0) == .orderedSame }
    }
}
