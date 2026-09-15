import Foundation

struct Config: Codable {
    var minMinutes: Int
    var maxMinutes: Int
    /// Quiet hours no longer mean total silence — they mean "gentle mode":
    /// messages during this window come from sleepMessages and only fire
    /// ~25% of the time a visit is scheduled, mostly staying silent
    /// otherwise, rather than a hard block. See randomMessage(at:).
    var quietHoursEnabled: Bool
    var quietHoursStart: Int
    var quietHoursEnd: Int
    var paused: Bool
    /// The "Always Pool" — eligible any hour outside quiet hours, mixed in
    /// ~35% of the time alongside whichever time-of-day pool applies.
    var messages: [String]
    var morningMessages: [String]    // 9:00–11:59
    var middayMessages: [String]     // 12:00–14:59
    var afternoonMessages: [String]  // 15:00–17:59
    var eveningMessages: [String]    // 18:00–20:59
    var lateNightMessages: [String]  // 21:00–23:59 and 0:00–0:59
    var sleepMessages: [String]      // used during quiet hours
    var mode: String            // "roaming" | "docked"
    var dockEdge: String        // "left" | "right" | "top" | "bottom"
    var pinnedAssetIndex: Int?  // nil = random each visit
    var customIntervalSeconds: Double?  // nil = use minMinutes...maxMinutes; set by the menu's interval slider
    var suppressDuringMeetings: Bool
    var meetingReminderEnabled: Bool
    var meetingReminderMinutes: Int
    var hasStarted: Bool
    /// Where the docked butterfly sits along its edge: the fraction (0...1)
    /// along screen height (left/right edges) or screen width (top/bottom
    /// edges), set by dragging it. nil = pick a random spot each time it
    /// parks, as before.
    var dockPositionFraction: Double?
    /// Index into ButterflySize.widths, set by the menu's size slider.
    var butterflySizeIndex: Int
    /// How long the message card stays fully visible before it starts
    /// disappearing, in seconds. Set by the menu's resting-time slider.
    var restingSeconds: Double

    static var `default`: Config {
        Config(
            minMinutes: 45,
            maxMinutes: 90,
            quietHoursEnabled: true,
            quietHoursStart: 22,
            quietHoursEnd: 10,
            paused: false,
            messages: [
                "Drink some water 💧",
                "A little water break for you",
                "Your body says thank you for water",
                "Sit up nice and tall for a sec",
                "Roll those shoulders back",
                "Unclench your jaw",
                "Shake your hands out for a moment",
                "Stretch your neck side to side",
                "Look away from the screen for 20 seconds",
                "Close your eyes for a few breaths",
                "Let your eyes rest on something far away",
                "Blink a few times on purpose",
                "You're doing so well",
                "Proud of how hard you're working",
                "You've got this, one step at a time",
                "Small breaks help you shine brighter ✨",
                "Take your time, you're not behind",
                "Just a little flutter to say hi 🦋",
                "Smile — you deserve it too",
                "Someone's proud of you right now",
                "You're more than your output today",
                "You don't need to prove it today, just show up",
                "You're allowed to be ambitious and tired",
                "Strong and soft can be the same person",
                "You're handling more than people realize",
                "Building this with you makes it feel possible",
                "Glad we're figuring this out together",
                "Founders forget to drink water too — sip time 💧",
                "Standing desk moment? Just for a sec",
                "How is your body feeling right now?",
                "Uncurl your fingers from the keyboard",
                "Take one slow sip and come back",
                "Look at something across the room",
                "Let your shoulders drop away from your ears",
                "A tiny reset before the next thing",
                "Open a window if the air feels stale",
                "Notice one good thing around you",
                "Let the sunlight find you for a minute",
                "Step away from the desk and come back softer",
            ],
            morningMessages: [
                "Good morning — let the day begin gently",
                "Before the first big thing: breathe",
                "Sunlight and water make a good team",
                "What is one small win for this morning?",
                "Let's make the next ten minutes easy",
                "Your brain is warming up; no rush",
                "A fresh page, not a performance",
                "Open the curtains if you can",
                "The work you're putting in adds up",
                "This is what building something looks like",
                "Every founder story has days like this",
                "You're building something from nothing — that's wild",
                "You didn't wait for permission. That's rare.",
                "Most people talk about ideas. You built one.",
                "Fresh start, same drive",
                "Morning momentum — here we go",
            ],
            middayMessages: [
                "Midday check: shoulders, jaw, water",
                "Give your eyes a view past the screen",
                "Lunch does not have to be earned",
                "A quiet minute can save the whole afternoon",
                "How is your energy, honestly?",
                "Go outside for three breaths if you can",
                "Refill your water before the next task",
                "The sun is high; you can pause too",
                "Have you eaten something today?",
                "A real lunch break sounds good right now",
                "Feed yourself, you've earned it",
                "Fuel the ambition — have you eaten?",
                "A real lunch break, founder 😉",
                "Your goals need you fed too",
                "Water = sharper focus. Quick sip?",
                "Halfway-ish — how's your energy?",
            ],
            afternoonMessages: [
                "The afternoon dip is not a personal failure",
                "Stand up and let your spine remember its shape",
                "Do the next small thing, not the whole day",
                "You can reset without starting over",
                "A little daylight might help",
                "Rest your wrists and shake out your hands",
                "You've been carrying a lot; soften your grip",
                "One calm breath before the next decision",
                "This is the part where you push through, gently",
                "A quick stretch might help right about now",
                "You're allowed to slow down for a minute",
                "A 20-second reset, then back to crushing it",
                "Best work comes from a clear head — breathe",
                "Recharge for 10 seconds, perform for hours",
                "Peak performance needs a hydrated brain 💧",
                "Ship it imperfect, iterate later",
                "Done today beats perfect never",
                "Uncertainty is the job description, not a sign you're failing",
                "No isn't the end, it's just data",
                "Breathe — the runway math can wait 20 seconds",
                "Desk-hunch check — shoulders back",
            ],
            eveningMessages: [
                "Evening check: what can wait until tomorrow?",
                "Close one loop, then let the rest be",
                "The light is changing; let yourself slow down",
                "You made it through another day",
                "Leave a little energy for yourself tonight",
                "A warm drink and a slower pace sound good",
                "You do not have to finish everything tonight",
                "Let the day end without grading yourself",
                "Almost through today — nice work",
                "Wrap-up time is close, hang in there",
                "However today went, you showed up for it",
                "Closing time soon — finish strong",
                "Today's effort counts, whatever's left undone",
                "You showed up hard today. That's the job.",
                "Whatever today threw at the company, we've got it",
                "Hard days don't erase how far you've already come",
            ],
            lateNightMessages: [
                "The screen can wait; your eyes have been working hard",
                "Late-night you deserves the same kindness as morning you",
                "If you are tired, that is information",
                "Save the last thought and rest",
                "Your future self would love ten quiet minutes",
                "Turn down the brightness and unclench your jaw",
                "The best idea can survive until tomorrow",
                "A bedtime is not a deadline you failed",
                "Still going? Don't forget water either way",
                "Late night — be extra gentle with yourself",
                "Whenever you stop tonight is enough",
                "Rest is productive too, even now",
                "Still at it? Impressive and also — water",
                "Late nights build empires, but rest builds you too",
                "The grind respects a bedtime eventually",
                "The company will survive you taking 10 seconds off",
                "Whatever's left on the list will be there tomorrow",
                "Closing the laptop tonight is still a win",
            ],
            sleepMessages: [
                "The tabs can stay open; you can close your eyes",
                "Let the room get quiet around you",
                "Rest is not falling behind",
                "Your body is asking softly; listen if you can",
                "Tomorrow can hold the next step",
                "No more solving for tonight",
                "A slow exhale, then let go",
                "You are allowed to disappear into sleep",
                "Suiii jaa 💤",
                "I know you're working hard — take a nap",
                "It's okay to close your eyes for a bit",
                "The world can wait, rest now",
                "Even founders need sleep",
                "Rest now, dream a little",
                "Ten minutes of rest counts too",
                "You can pick this back up tomorrow",
                "Whatever it is, it'll still be there when you wake up",

            ],
            mode: "roaming",
            dockEdge: "right",
            pinnedAssetIndex: nil,
            customIntervalSeconds: nil,
            suppressDuringMeetings: true,
            meetingReminderEnabled: false,
            meetingReminderMinutes: 15,
            hasStarted: false,
            dockPositionFraction: nil,
            butterflySizeIndex: ButterflySize.defaultIndex,
            restingSeconds: 5.0
        )
    }

    /// True during the configured quiet-hours window. This is no longer a
    /// hard block on visits — it switches randomMessage(at:) into "gentle
    /// mode" (sleepMessages, ~25% of the time, mostly silent otherwise)
    /// instead of stopping visits outright, so the butterfly can still show
    /// up overnight if the laptop is open, just far less often and more
    /// softly.
    func isQuietHour(at date: Date = Date()) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if quietHoursStart == quietHoursEnd { return false }
        if quietHoursStart < quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        } else {
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
    }

    func randomIntervalSeconds() -> TimeInterval {
        if let customIntervalSeconds { return customIntervalSeconds }
        let minSec = Double(minMinutes) * 60
        let maxSec = Double(maxMinutes) * 60
        return Double.random(in: minSec...maxSec)
    }

    /// Picks a message, or nil to mean "stay silent this cycle" (only
    /// possible during quiet hours, and only when not manually triggered).
    /// Outside quiet hours: 35% chance of the Always Pool, otherwise
    /// whichever time-of-day pool matches the current hour. During quiet
    /// hours: 25% chance of a sleepMessages pick (always, if manually
    /// triggered — "Show a butterfly now" shouldn't get silently
    /// swallowed by the dice roll), nil the rest of the time.
    func randomMessage(at date: Date = Date(), manualOverride: Bool = false) -> String? {
        if isQuietHour(at: date) {
            if !manualOverride {
                guard Double.random(in: 0..<1) < 0.25 else { return nil }
            }
            return sleepMessages.randomElement() ?? messages.randomElement() ?? "Rest now, dream a little"
        }
        if Double.random(in: 0..<1) < 0.35 {
            return messages.randomElement() ?? "You've got this"
        }
        let hour = Calendar.current.component(.hour, from: date)
        let pool: [String]
        switch hour {
        case 9...11: pool = morningMessages
        case 12...14: pool = middayMessages
        case 15...17: pool = afternoonMessages
        case 18...20: pool = eveningMessages
        default: pool = lateNightMessages // 21:00–23:59, 0:00–0:59
        }
        return pool.randomElement() ?? messages.randomElement() ?? "You've got this"
    }

    /// Adds new bundled messages to an existing config without replacing
    /// messages the user may have edited manually. This lets message updates
    /// reach users who already have a config.json from an earlier version.
    @discardableResult
    mutating func mergeBundledMessages() -> Bool {
        let bundled = Config.default
        var changed = false

        func merge(_ defaults: [String], into current: inout [String]) {
            for message in defaults where !current.contains(message) {
                current.append(message)
                changed = true
            }
        }

        merge(bundled.messages, into: &messages)
        merge(bundled.morningMessages, into: &morningMessages)
        merge(bundled.middayMessages, into: &middayMessages)
        merge(bundled.afternoonMessages, into: &afternoonMessages)
        merge(bundled.eveningMessages, into: &eveningMessages)
        merge(bundled.lateNightMessages, into: &lateNightMessages)
        merge(bundled.sleepMessages, into: &sleepMessages)
        return changed
    }
}

// Custom Codable conformance lives in an extension (rather than the primary
// declaration) specifically so the compiler-synthesized memberwise
// initializer above stays available — declaring init(from:) directly in the
// struct body would suppress it, requiring a hand-maintained duplicate init
// that grows every time a field is added.
extension Config {
    private enum CodingKeys: String, CodingKey {
        case minMinutes, maxMinutes, quietHoursEnabled, quietHoursStart, quietHoursEnd
        case paused, messages, mode, dockEdge, pinnedAssetIndex, customIntervalSeconds
        case suppressDuringMeetings, meetingReminderEnabled, meetingReminderMinutes
        case hasStarted, dockPositionFraction, butterflySizeIndex, restingSeconds
        case morningMessages, middayMessages, afternoonMessages, eveningMessages
        case lateNightMessages, sleepMessages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config.default
        self.init(
            minMinutes: try c.decode(Int.self, forKey: .minMinutes),
            maxMinutes: try c.decode(Int.self, forKey: .maxMinutes),
            quietHoursEnabled: try c.decode(Bool.self, forKey: .quietHoursEnabled),
            quietHoursStart: try c.decode(Int.self, forKey: .quietHoursStart),
            quietHoursEnd: try c.decode(Int.self, forKey: .quietHoursEnd),
            paused: try c.decode(Bool.self, forKey: .paused),
            messages: try c.decode([String].self, forKey: .messages),
            morningMessages: try c.decodeIfPresent([String].self, forKey: .morningMessages) ?? fallback.morningMessages,
            middayMessages: try c.decodeIfPresent([String].self, forKey: .middayMessages) ?? fallback.middayMessages,
            afternoonMessages: try c.decodeIfPresent([String].self, forKey: .afternoonMessages) ?? fallback.afternoonMessages,
            eveningMessages: try c.decodeIfPresent([String].self, forKey: .eveningMessages) ?? fallback.eveningMessages,
            lateNightMessages: try c.decodeIfPresent([String].self, forKey: .lateNightMessages) ?? fallback.lateNightMessages,
            sleepMessages: try c.decodeIfPresent([String].self, forKey: .sleepMessages) ?? fallback.sleepMessages,
            mode: try c.decodeIfPresent(String.self, forKey: .mode) ?? "roaming",
            dockEdge: try c.decodeIfPresent(String.self, forKey: .dockEdge) ?? "right",
            pinnedAssetIndex: try c.decodeIfPresent(Int.self, forKey: .pinnedAssetIndex),
            customIntervalSeconds: try c.decodeIfPresent(Double.self, forKey: .customIntervalSeconds),
            suppressDuringMeetings: try c.decodeIfPresent(Bool.self, forKey: .suppressDuringMeetings) ?? true,
            meetingReminderEnabled: try c.decodeIfPresent(Bool.self, forKey: .meetingReminderEnabled) ?? false,
            meetingReminderMinutes: try c.decodeIfPresent(Int.self, forKey: .meetingReminderMinutes) ?? 15,
            hasStarted: try c.decodeIfPresent(Bool.self, forKey: .hasStarted) ?? false,
            dockPositionFraction: try c.decodeIfPresent(Double.self, forKey: .dockPositionFraction),
            butterflySizeIndex: try c.decodeIfPresent(Int.self, forKey: .butterflySizeIndex) ?? ButterflySize.defaultIndex,
            restingSeconds: try c.decodeIfPresent(Double.self, forKey: .restingSeconds) ?? 5.0
        )
    }
}

enum ConfigStore {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LilButterfly", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              var config = try? JSONDecoder().decode(Config.self, from: data)
        else {
            let def = Config.default
            save(def)
            return def
        }
        if config.mergeBundledMessages() {
            save(config)
        }
        return config
    }

    static func save(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
