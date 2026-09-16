import XCTest
import AppKit
@testable import Butterfly

final class InteractiveCheckInTests: XCTestCase {

    func testMoodCheckInContainsEveryClickableChoice() {
        let content = CheckInContent.random()

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
        let content = CheckInContent.random()
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
        for label in CheckInContent.random().choices.map(\.label) {
            var clickedLabel: String?
            let window = ChoiceButtonWindow(
                frame: NSRect(x: 0, y: 0, width: 80, height: 32),
                title: label,
                style: .plainChip
            ) {
                clickedLabel = label
            }
            defer { window.orderOut(nil) }

            guard let button = try? XCTUnwrap(window.contentView?.subviews.first as? NSButton) else {
                return XCTFail("Choice button was not installed for \(label)")
            }
            button.performClick(nil)
            XCTAssertEqual(clickedLabel, label)
        }
    }
}
