import XCTest
import AppKit
@testable import Butterfly

final class InteractiveCheckInTests: XCTestCase {

    func testMoodCheckInContainsEveryClickableChoice() {
        let content = CheckInContent.make(style: .moodPicker)

        XCTAssertEqual(content.style, .moodPicker)
        XCTAssertFalse(content.question.isEmpty)
        XCTAssertEqual(content.choices.map(\.label), ["😄", "😌", "😐", "😩", "😔"])

        for choice in content.choices {
            XCTAssertFalse(choice.label.isEmpty)
            XCTAssertFalse(choice.replies.isEmpty, "\(choice.label) should have a reply")
            XCTAssertTrue(choice.replies.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
    }

    func testBubbleCreatesOneDistinctClickableFramePerChoice() {
        let content = CheckInContent.make(style: .moodPicker)
        let bubble = BubbleView(message: content.question, choiceLabels: content.choices.map(\.label))

        let frames = content.choices.indices.map { bubble.choiceFrame(at: $0) }

        XCTAssertEqual(frames.count, content.choices.count)
        XCTAssertTrue(frames.allSatisfy { bubble.bounds.contains($0) })

        for index in frames.indices {
            for otherIndex in frames.indices where index < otherIndex {
                let intersection = frames[index].intersection(frames[otherIndex])
                XCTAssertTrue(intersection.isNull || intersection.isEmpty)
            }
        }
    }

    func testChoiceButtonInvokesItsClickHandlerForEveryChoice() {
        for label in CheckInContent.make(style: .moodPicker).choices.map(\.label) {
            var clickedLabel: String?
            let window = ChoiceButtonWindow(
                frame: NSRect(x: 0, y: 0, width: 80, height: 32),
                title: label,
                style: .plainChip,
                dismissesOnClick: false
            ) {
                clickedLabel = label
            }
            defer { window.orderOut(nil) }

            guard let button = try? XCTUnwrap(window.contentView?.subviews.first as? NSButton) else {
                return XCTFail("Choice button was not installed for \(label)")
            }
            button.performClick(nil)
            XCTAssertEqual(clickedLabel, label)
            XCTAssertTrue(window.isVisible, "Selected choice (label) should remain visible while its reply is shown")
        }
    }

    func testEveryTestableVariantHasClickableContent() {
        for style in CheckInStyle.allCases {
            let content = CheckInContent.make(style: style)
            XCTAssertEqual(content.style, style)
            XCTAssertFalse(content.question.isEmpty)
            // Zero-tap styles (breathing, eye rest) ask nothing of the
            // user at all, so they deliberately carry no choices.
            if style.isZeroTap {
                XCTAssertTrue(content.choices.isEmpty)
            } else {
                XCTAssertFalse(content.choices.isEmpty)
                XCTAssertTrue(content.choices.allSatisfy { !$0.label.isEmpty && !$0.replies.isEmpty })
            }
        }
    }

    func testEnergyStageIndexCoversFullDragRangeInOrder() {
        XCTAssertEqual(CheckInContent.energyStageIndex(for: 0), 0)
        XCTAssertEqual(CheckInContent.energyStageIndex(for: 0.15), 0)
        XCTAssertEqual(CheckInContent.energyStageIndex(for: 0.25), 1)
        XCTAssertEqual(CheckInContent.energyStageIndex(for: 0.5), 2)
        XCTAssertEqual(CheckInContent.energyStageIndex(for: 0.75), 3)
        XCTAssertEqual(CheckInContent.energyStageIndex(for: 1), 4)

        let stages = CheckInContent.make(style: .energySlider).choices
        XCTAssertEqual(stages.count, 5)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            let index = CheckInContent.energyStageIndex(for: fraction)
            XCTAssertTrue(stages.indices.contains(index), "fraction \(fraction) produced out-of-range stage \(index)")
        }
    }

    func testEnergySliderReservesOneFullWidthDragStripNotFiveSlots() {
        let content = CheckInContent.make(style: .energySlider)
        let bubble = BubbleView(message: content.question, choiceLabels: [""], checkInStyle: content.style)
        let strip = bubble.choiceFrame(at: 0)
        XCTAssertGreaterThan(strip.width, 200, "the slider needs one wide drag strip, not a narrow single-choice slot")
    }

    func testIdleTimeUsesAnyInputEventTypeNotNull() {
        // .null (0) reports ~time-since-boot, which made every user look
        // permanently idle and silently blocked all scheduled visits.
        XCTAssertEqual(ActivityTracker.anyInputEventType.rawValue, UInt32.max)
        XCTAssertNotEqual(ActivityTracker.anyInputEventType, .null)
    }

    func testEyeRestMentionsSessionLengthOnlyAfterAnHour() {
        // Under an hour: never claims "N hours" of screen time.
        for _ in 0..<50 {
            let short = CheckInContent.eyeRestReset(activeSeconds: 20 * 60)
            XCTAssertEqual(short.style, .eyeRestReset)
            XCTAssertFalse(short.question.contains("hour"))
        }
        // Four hours in: the session-aware opener shows up (70% per visit,
        // so 50 draws all missing it would be a real bug, not bad luck).
        let long = (0..<50).map { _ in CheckInContent.eyeRestReset(activeSeconds: 4 * 3600).question }
        XCTAssertTrue(long.contains { $0.contains("4 hours") })
    }

    func testUpdatingBarAppearsInButtonSlotAndClearsOnFailure() {
        let bubble = BubbleView(message: "A new Butterfly (v9.9.9) is ready.", choiceLabels: ["Update Now"])
        func slidingBar() -> CALayer? {
            bubble.layer?.sublayers?.first { $0.sublayers?.first?.animation(forKey: "slide") != nil }
        }
        XCTAssertNil(slidingBar())

        bubble.showUpdating()
        let bar = try? XCTUnwrap(slidingBar())
        XCTAssertNotNil(bar, "an indeterminate bar should be animating")
        if let bar {
            // Sits inside the slot the Update Now button occupied, not
            // somewhere outside the card.
            XCTAssertTrue(bubble.choiceFrame(at: 0).contains(CGPoint(x: bar.frame.midX, y: bar.frame.midY)))
            XCTAssertTrue(bubble.bounds.contains(bar.frame))
        }

        bubble.showUpdateFailed("Update failed — try the menu.")
        XCTAssertNil(slidingBar(), "failure should stop the progress bar")
    }

    func testPressFeedbackNeverGrowsPastItsFrame() {
        // The update button spans nearly the whole card; anything above
        // 1.0 here is what pushed it outside the card on hover/click.
        XCTAssertEqual(ChoiceButtonWindow.Feedback.press.hoverScale, 1)
        XCTAssertEqual(ChoiceButtonWindow.Feedback.press.maxScale, 1)
    }

    func testChoiceLayoutsGiveHeartsRoomAndWrapTextChips() {
        let hearts = CheckInContent.make(style: .favoriteColor)
        let heartBubble = BubbleView(message: hearts.question, choiceLabels: hearts.choices.map(\.label), checkInStyle: hearts.style)
        XCTAssertGreaterThanOrEqual(heartBubble.frame.width, 360)
        XCTAssertTrue((0..<hearts.choices.count).allSatisfy { heartBubble.choiceFrame(at: $0).width >= 40 })

        let words = CheckInContent.make(style: .pickAWord)
        let wordBubble = BubbleView(message: words.question, choiceLabels: words.choices.map(\.label), checkInStyle: words.style)
        XCTAssertTrue((0..<words.choices.count).allSatisfy { wordBubble.choiceFrame(at: $0).width >= 58 })
        XCTAssertGreaterThan(wordBubble.frame.height, heartBubble.frame.height - 20)
    }
}
