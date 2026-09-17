import AppKit

/// Turns "when should a visit actually show something specific" from pure
/// randomness into a couple of real-world signals — the same basic idea
/// break-reminder apps like Stretchly/Time Out/Awareness use: system-wide
/// idle time via CGEventSourceSecondsSinceLastEventType, which needs no
/// Accessibility permission since it only reads an aggregate idle-seconds
/// counter, never individual keystrokes or clicks.
final class ActivityTracker {

    /// Below this many idle seconds, the user counts as "still here" for
    /// firing a scheduled visit — long enough not to misfire during a
    /// normal pause between keystrokes, short enough to actually skip an
    /// empty desk.
    static let idleThreshold: TimeInterval = 45

    /// An idle stretch at least this long counts as a break already
    /// taken — the continuous-use clock resets rather than treating a
    /// 10-minute coffee run as part of the same unbroken session.
    private static let sessionResetIdleThreshold: TimeInterval = 180

    private static let pollInterval: TimeInterval = 20

    /// The real 20-20-20 rule's own cadence — used to trigger the eye-rest
    /// check-in from actual continuous screen time, not a flat random
    /// chance shared with every other style.
    static let eyeRestInterval: TimeInterval = 20 * 60

    /// A much longer uninterrupted stretch gets its own, stronger nudge
    /// (Breathe With Me) once per stretch, rather than repeating every
    /// time the interval is crossed again.
    static let longSessionThreshold: TimeInterval = 3 * 60 * 60

    private(set) var continuousActiveSeconds: TimeInterval = 0
    private(set) var secondsSinceLastEyeRestPrompt: TimeInterval = 0
    private(set) var hasShownLongSessionNudgeThisSession = false
    private var timer: Timer?

    var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }

    var isIdle: Bool { idleSeconds >= Self.idleThreshold }

    func start() {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let idle = idleSeconds
        if idle >= Self.sessionResetIdleThreshold {
            continuousActiveSeconds = 0
            secondsSinceLastEyeRestPrompt = 0
            hasShownLongSessionNudgeThisSession = false
        } else if idle < Self.idleThreshold {
            continuousActiveSeconds += Self.pollInterval
            secondsSinceLastEyeRestPrompt += Self.pollInterval
        }
        // Between idleThreshold and sessionResetIdleThreshold — a short
        // pause, e.g. reading something — neither adds to nor resets
        // either clock.
    }

    func markEyeRestShown() { secondsSinceLastEyeRestPrompt = 0 }
    func markLongSessionNudgeShown() { hasShownLongSessionNudgeThisSession = true }
}
