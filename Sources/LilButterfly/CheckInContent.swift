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

    var displayName: String {
        switch self {
        case .moodPicker: return "Mood Picker"
        case .smilePrompt: return "Smile Prompt"
        case .favoriteColor: return "Favorite Color Hearts"
        case .gratitudeTap: return "Gratitude Tap"
        case .pickAWord: return "Pick a Word"
        }
    }
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
