import Foundation

/// One interactive visit style. The choice-row styles share the same
/// BubbleView/ChoiceButtonWindow plumbing, so adding content does not need
/// another overlay implementation.
enum CheckInStyle: String, CaseIterable {
    case moodPicker
    case smilePrompt
    case favoriteColor
    case gratitudeTap
    case pickAWord
    case energySlider
    case breatheWithMe
    case eyeRestReset
    case blinkBreak

    var displayName: String {
        switch self {
        case .moodPicker: return "Mood Picker"
        case .smilePrompt: return "Smile Prompt"
        case .favoriteColor: return "Favorite Color Hearts"
        case .gratitudeTap: return "Gratitude Tap"
        case .pickAWord: return "Pick a Word"
        case .energySlider: return "Energy Slider"
        case .breatheWithMe: return "Breathe With Me"
        case .eyeRestReset: return "20-20-20 Eye Rest"
        case .blinkBreak: return "Blink Break"
        }
    }

    /// True for the styles that ask nothing of the user at all — no chip,
    /// no drag, nothing to pick. They still reserve BubbleView's one
    /// full-width strip (for a breathing circle / countdown ring / blink
    /// cycle), just like the slider does, but never build a
    /// ChoiceButtonWindow or log a CheckInStore pick, since there's no
    /// pick to log.
    var isZeroTap: Bool { self == .breatheWithMe || self == .eyeRestReset || self == .blinkBreak }

    /// Styles whose interactive surface is one continuous strip rather
    /// than a row of N labeled slots — the slider drags across it, the
    /// zero-tap styles just animate inside it.
    var needsSingleReservedStrip: Bool { self == .energySlider || isZeroTap }
}

struct CheckInChoice {
    let label: String
    let replies: [String]
}

struct CheckInContent {
    let style: CheckInStyle
    let question: String
    let choices: [CheckInChoice]

    static func random() -> CheckInContent {
        make(style: CheckInStyle.allCases.randomElement()!)
    }

    static func make(style: CheckInStyle) -> CheckInContent {
        switch style {
        case .moodPicker: return moodPicker()
        case .smilePrompt: return smilePrompt()
        case .favoriteColor: return favoriteColor()
        case .gratitudeTap: return gratitudeTap()
        case .pickAWord: return pickAWord()
        case .energySlider: return energySlider()
        case .breatheWithMe: return breatheWithMe()
        case .eyeRestReset: return eyeRestReset()
        case .blinkBreak: return blinkBreak()
        }
    }

    private static func moodPicker() -> CheckInContent {
        let choices = [
            CheckInChoice(label: "😄", replies: ["Love that energy — hold onto it 💛", "That's wonderful to hear.", "Ride that wave a little longer."]),
            CheckInChoice(label: "😌", replies: ["That's a lovely place to be.", "Savor this calm, you've earned it.", "Glad you found a moment like this."]),
            CheckInChoice(label: "😐", replies: ["Steady is underrated.", "Some days are just days. That's fine too.", "Neutral counts. Not every day needs a headline."]),
            CheckInChoice(label: "😩", replies: ["That sounds like a lot right now — it's okay to feel stretched thin.", "Makes sense you're stressed. You're carrying a lot.", "Take one slow breath before you go back to it."]),
            CheckInChoice(label: "😔", replies: ["That's okay — you don't have to be fine all the time.", "Sending you a little extra care right now.", "Rough moments pass. I'm still here."]),
        ]
        return CheckInContent(style: .moodPicker, question: ["How are you feeling right now?", "What's today been like, mood-wise?"].randomElement()!, choices: choices)
    }

    private static func smilePrompt() -> CheckInContent {
        CheckInContent(style: .smilePrompt, question: ["Smile for me? 🦋", "Bet I can get a smile out of you"].randomElement()!, choices: [
            CheckInChoice(label: "Okay, smiled 😊", replies: ["I knew you had one in there.", "That looks good on you."]),
            CheckInChoice(label: "Did it 😄", replies: ["Perfect. Keep a little of that warmth with you.", "A tiny bright moment counts."]),
        ])
    }

    private static func favoriteColor() -> CheckInContent {
        CheckInContent(style: .favoriteColor, question: "Pick your color today", choices: [
            CheckInChoice(label: "❤️", replies: ["Your drive is something special."]),
            CheckInChoice(label: "🧡", replies: ["Your ambition is worth celebrating."]),
            CheckInChoice(label: "💛", replies: ["You are building beautiful momentum."]),
            CheckInChoice(label: "💚", replies: ["Growth can be quiet and still be real."]),
            CheckInChoice(label: "💙", replies: ["Your discipline is carrying you forward."]),
            CheckInChoice(label: "💜", replies: ["Your vision gives today meaning."]),
            CheckInChoice(label: "🤍", replies: ["Clarity can be a form of rest."]),
        ])
    }

    private static func gratitudeTap() -> CheckInContent {
        let choices = [
            ("💬 A good conversation", "Connection is a good thing to carry with you."),
            ("😴 A little nap", "Rest is productive in its own gentle way."),
            ("📖 A good book", "I hope you make room for more moments like that."),
            ("🧘 A quiet moment", "Small pockets of peace matter."),
            ("✅ Something I finished", "Progress deserves to be noticed."),
        ].shuffled().map { CheckInChoice(label: $0.0, replies: [$0.1]) }
        return CheckInContent(style: .gratitudeTap, question: "One good thing about today?", choices: choices)
    }

    /// The 5-stage emoji morph the slider drags through. `choices` here are
    /// content (what the live emoji/message swap to at each stage), not
    /// separate tap targets — EnergySliderWindow is one continuous drag
    /// surface, and the overlay picks the current entry via
    /// `energyStageIndex(for:)` as the thumb moves.
    private static func energySlider() -> CheckInContent {
        CheckInContent(style: .energySlider, question: ["How's your energy right now?", "Where's your battery at?"].randomElement()!, choices: [
            CheckInChoice(label: "😴", replies: ["Running on empty is worth listening to.", "Low is real — even five quiet minutes counts as something."]),
            CheckInChoice(label: "🥱", replies: ["Go easy on yourself for this next stretch.", "A little rest now saves a lot more later."]),
            CheckInChoice(label: "🙂", replies: ["Steady is a good place to build from.", "That's a sustainable pace — keep it."]),
            CheckInChoice(label: "😄", replies: ["That's a great gear to be in.", "Ride it, but remember to coast later too."]),
            CheckInChoice(label: "⚡", replies: ["Look at you, fully charged — go make something of it.", "That kind of energy is worth using well."]),
        ])
    }

    /// Maps a continuous 0...1 drag position onto one of the slider's 5
    /// discrete emoji/message stages.
    static func energyStageIndex(for fraction: Double) -> Int {
        min(4, max(0, Int(fraction * 5)))
    }

    /// Zero-tap — no choices to pick from, just a single guided breath
    /// while the butterfly's own flutter visibly slows to match (see
    /// BubbleView.startBreathing and ButterflyView.setFlutterRate).
    private static func breatheWithMe() -> CheckInContent {
        CheckInContent(style: .breatheWithMe, question: ["Let's take a slow breath together 🦋", "One slow breath, together?"].randomElement()!, choices: [])
    }

    static let breathingClosingLines = ["Nice, well done.", "That's a good reset. 🦋", "Feel that? Carry it with you."]
    static func randomBreathingClosingLine() -> String { breathingClosingLines.randomElement()! }

    /// Also zero-tap — states the well-known ergonomic rule (every ~20
    /// minutes, look at something 20 feet away for 20 seconds) and paces
    /// the actual 20 seconds with a countdown ring, rather than just
    /// naming the rule and leaving the user to self-time it.
    private static func eyeRestReset() -> CheckInContent {
        CheckInContent(style: .eyeRestReset, question: eyeRestOpeners.randomElement()!, choices: [])
    }

    /// The same visit, but opened with a line that knows how long the
    /// user has actually been at the screen (from ActivityTracker's real
    /// continuous-use clock) once that's been a while — so a fourth-hour
    /// reminder reads differently from a first one instead of repeating.
    static func eyeRestReset(activeSeconds: TimeInterval) -> CheckInContent {
        let hours = Int(activeSeconds / 3600)
        guard hours >= 1 else { return eyeRestReset() }
        let timeSpent = hours == 1 ? "an hour" : "\(hours) hours"
        let sessionAware = [
            "\(timeSpent) of screen — your eyes filed a complaint 👀",
            "\(timeSpent) straight. Your eyes would like a word",
            "You've been staring for \(timeSpent). Quick reset?",
            "\(timeSpent) in. Time to look at literally anything else",
            "\(timeSpent) of focus — impressive. Now unfocus for 20s",
        ]
        // Mostly session-aware once it's been a long stretch, but still
        // mixed with the general pool so it doesn't become formulaic.
        let question = Double.random(in: 0..<1) < 0.7 ? sessionAware.randomElement()! : eyeRestOpeners.randomElement()!
        return CheckInContent(style: .eyeRestReset, question: question, choices: [])
    }

    private static let eyeRestOpeners = [
        // gentle
        "Time for a 20-20-20 reset 👀",
        "Give your eyes a 20-second break",
        "Every 20 minutes, 20 feet, 20 seconds — eye doctors' actual rule",
        "Your focus muscles have been locked close up for a while",
        "Let your eyes stop pulling focus for a moment",
        "Your eyes have been on sprint mode — let them jog",
        // playful
        "Your eyeballs called. They want a vacation 🏝️",
        "Plot twist: the most important thing is far away",
        "Quick eye workout. No gym membership needed",
        "The screen will still be here. Promise 🦋",
        "Pixels are great. Distant things are greater",
        "Eye yoga time 🧘 — nothing to stretch but focus",
        "Your eyes deserve a window seat for 20 seconds",
        "Hey, pretend you're a lighthouse keeper for a sec",
    ]

    /// Picked once per visit, then shown with the live countdown number —
    /// so the 20 seconds don't always read the same way either.
    static let eyeRestCountdownPhrases = [
        "Look 20 feet away…",
        "Find something far away…",
        "Gaze out a window…",
        "Look at the far wall…",
        "Stare at the horizon 🌅…",
        "Find the farthest thing…",
        "Pirate mode: scan the sea 🏴‍☠️…",
        "Look past the screen…",
    ]
    static func randomEyeRestCountdownPhrase() -> String { eyeRestCountdownPhrases.randomElement()! }

    static let eyeRestClosingLines = [
        "Welcome back 👀",
        "Nice, that's a good reset.",
        "Your eyes say thank you.",
        "Real relief for your focus muscles.",
        "A few seconds, real recovery.",
        "Eyes: refreshed. Pixels: still here 😄",
        "Your eyes just high-fived you.",
        "Vacation over. Back to it, gently.",
        "Ahh. Much better, right?",
    ]
    static func randomEyeRestClosingLine() -> String { eyeRestClosingLines.randomElement()! }

    /// Zero-tap, distinct from the 20-20-20 reset: screens cut blink rate
    /// from a normal 15-20/min down to roughly 5-7/min, which is a tear
    /// film/dry-eye problem, not a focus-muscle one — the 20-20-20 break
    /// doesn't address it at all. Deliberately much shorter/lower-friction
    /// than that full reset, so it can run on its own, more frequent
    /// cadence without feeling like a second big interruption.
    private static func blinkBreak() -> CheckInContent {
        CheckInContent(style: .blinkBreak, question: [
            "Quick blink break 👀",
            "Your blink rate drops a lot on screens — let's fix that",
            "A few slow blinks for you",
        ].randomElement()!, choices: [])
    }

    static let blinkBreakClosingLines = ["Nice, that helps more than it seems.", "Good — your eyes needed that.", "A little moisture goes a long way 👀"]
    static func randomBlinkBreakClosingLine() -> String { blinkBreakClosingLines.randomElement()! }

    private static func pickAWord() -> CheckInContent {
        CheckInContent(style: .pickAWord, question: "Which word feels closest right now?", choices: [
            CheckInChoice(label: "🎯 Focused", replies: ["That focus is yours — use it kindly."]),
            CheckInChoice(label: "😵‍💫 Overwhelmed", replies: ["You don't have to carry everything at once."]),
            CheckInChoice(label: "🌱 Hopeful", replies: ["That little spark is worth protecting."]),
            CheckInChoice(label: "😊 Content", replies: ["Contentment is a beautiful place to pause."]),
            CheckInChoice(label: "🌀 Restless", replies: ["You can slow down without falling behind."]),
        ])
    }
}
