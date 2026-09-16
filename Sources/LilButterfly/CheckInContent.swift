import Foundation

/// One occasional interactive visit style, in place of a plain kind
/// message. Content pools are hand-curated and stored here, not fetched —
/// the whole feature works fully offline. New styles are added by adding a
/// new case here plus a builder function; nothing outside this file needs
/// to change, since ScreenOverlay/DockedOverlay/AppDelegate only ever
/// consume whatever CheckInContent.random() returns.
enum CheckInStyle: String {
    case moodPicker
}

struct CheckInChoice {
    /// What's drawn on the button — an emoji for moodPicker, a word or
    /// color swatch for future styles.
    let label: String
    /// One is picked at random when this choice is tapped, so answering
    /// the same way twice doesn't show the identical sentence back.
    let replies: [String]
}

struct CheckInContent {
    let style: CheckInStyle
    let question: String
    let choices: [CheckInChoice]

    static func random() -> CheckInContent {
        moodPicker()
    }

    /// Spans the Yale Mood Meter's energy×pleasantness quadrants (happy,
    /// calm, neutral, stressed, down) rather than a flat good→bad line, and
    /// replies follow validation-therapy phrasing — acknowledge the feeling
    /// as legitimate rather than rushing to fix it.
    private static func moodPicker() -> CheckInContent {
        let questions = [
            "How are you feeling right now?",
            "What's today been like, mood-wise?",
        ]
        let choices = [
            CheckInChoice(label: "😄", replies: [
                "Love that energy — hold onto it 💛",
                "That's wonderful to hear.",
                "Ride that wave a little longer.",
            ]),
            CheckInChoice(label: "😌", replies: [
                "That's a lovely place to be.",
                "Savor this calm, you've earned it.",
                "Glad you found a moment like this.",
            ]),
            CheckInChoice(label: "😐", replies: [
                "Steady is underrated.",
                "Some days are just days. That's fine too.",
                "Neutral counts. Not every day needs a headline.",
            ]),
            CheckInChoice(label: "😩", replies: [
                "That sounds like a lot right now — it's okay to feel stretched thin.",
                "Makes sense you're stressed. You're carrying a lot.",
                "Take one slow breath before you go back to it.",
            ]),
            CheckInChoice(label: "😔", replies: [
                "That's okay — you don't have to be fine all the time.",
                "Sending you a little extra care right now.",
                "Rough moments pass. I'm still here.",
            ]),
        ]
        return CheckInContent(style: .moodPicker, question: questions.randomElement()!, choices: choices)
    }
}
