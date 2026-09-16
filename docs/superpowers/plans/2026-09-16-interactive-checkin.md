# Interactive Check-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and prove a reusable "tappable choice row inside the message card" mechanism, then ship the first interactive check-in style (mood picker) end to end — the remaining 6 styles from the spec follow as fast-follow plans reusing this same mechanism with just new content pools.

**Architecture:** Generalize the update-reminder button (`UpdateActionButtonWindow` → `ChoiceButtonWindow`, `BubbleView.actionButtonFrame` → `choiceFrame(at:)`) into a mechanism that supports N choices instead of 1, storing them as `[ChoiceButtonWindow]` in both overlays instead of a single optional — the same "one small window draws and handles its own click" fix that solved the earlier duplicate-(x) bug, applied uniformly instead of one-off per style. A new `CheckInContent` enum holds hand-written content pools (no network, no API), and a new `CheckInStore` quietly logs picks locally.

**Tech Stack:** Swift, AppKit (NSPanel/NSButton/NSTextView), Swift Package Manager. No test framework in this codebase — verification is manual (`swift build` / `swift run` + `osascript` menu triggers + log/crash checks), matching how every other feature in this project has been verified.

---

## Important: this plan touches shipped, working code first

Tasks 1–5 refactor the *existing*, already-shipped update-reminder feature before any new feature code is added. This is deliberate risk sequencing: prove the generalized mechanism still produces byte-for-byte the same behavior (same button look, same click routing, same close-button precedence) before building anything new on top of it. Do not skip the regression checkpoint in Task 5.

---

### Task 1: Generalize the button window

**Files:**
- Create: `Sources/LilButterfly/ChoiceButtonWindow.swift`
- Delete: `Sources/LilButterfly/UpdateActionButtonWindow.swift`

- [ ] **Step 1: Create the generalized window**

```swift
import AppKit

/// A small window that draws exactly one visible, tappable control and
/// handles its own click — the fix that solved an earlier bug where an
/// invisible full-card tap region and the close mark's separately-drawn (x)
/// visually conflicted. Every interactive element in a bubble body (the
/// update button, and every check-in choice) is one of these: what's drawn
/// and what's clickable are always the same window, never split into two.
final class ChoiceButtonWindow: NSPanel {

    /// Visual style for the button's own content — lets the same window
    /// type render either the update reminder's filled accent capsule or a
    /// plain emoji/word chip with no background of its own.
    struct Style {
        var backgroundColor: NSColor
        var textColor: NSColor
        var font: NSFont
        var cornerRadius: CGFloat
        var hasBackground: Bool

        /// The update reminder's existing look, unchanged.
        static let accentCapsule = Style(
            backgroundColor: .controlAccentColor,
            textColor: .white,
            font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            cornerRadius: 14,
            hasBackground: true
        )

        /// Just the label, no fill — for emoji and word choices sitting in
        /// a row of several.
        static let plainChip = Style(
            backgroundColor: .clear,
            textColor: .white,
            font: NSFont.systemFont(ofSize: 18, weight: .regular),
            cornerRadius: 0,
            hasBackground: false
        )
    }

    private let onClick: () -> Void

    init(frame: NSRect, title: String, style: Style = .accentCapsule, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = style.hasBackground
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        let button = NSButton(frame: NSRect(origin: .zero, size: frame.size))
        button.title = title
        button.isBordered = false
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: style.font, .foregroundColor: style.textColor]
        )
        button.wantsLayer = true
        button.layer?.cornerRadius = style.cornerRadius
        button.layer?.backgroundColor = style.hasBackground ? style.backgroundColor.cgColor : nil
        button.autoresizingMask = [.width, .height]
        button.target = self
        button.action = #selector(tapped)
        contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView?.addSubview(button)

        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func tapped() {
        onClick()
        orderOut(nil)
    }
}
```

- [ ] **Step 2: Delete the old file**

```bash
rm "Sources/LilButterfly/UpdateActionButtonWindow.swift"
```

- [ ] **Step 3: Confirm the project still lists both files correctly**

Run: `ls Sources/LilButterfly/ChoiceButtonWindow.swift Sources/LilButterfly/UpdateActionButtonWindow.swift 2>&1`
Expected: the first path prints, the second prints `No such file or directory` — the build will still fail at this point (ScreenOverlay/DockedOverlay still reference the old type), that's expected and fixed in Tasks 2–3.

- [ ] **Step 4: Commit**

```bash
git add -A -- Sources/LilButterfly/ChoiceButtonWindow.swift Sources/LilButterfly/UpdateActionButtonWindow.swift
git commit -m "Generalize UpdateActionButtonWindow into ChoiceButtonWindow"
```

---

### Task 2: Generalize BubbleView's action area into a choice row

**Files:**
- Modify: `Sources/LilButterfly/BubbleView.swift`

- [ ] **Step 1: Replace the single-button frame/size properties and init parameter**

Replace this block (currently lines 33–45):

```swift
    /// Reserved space at the bottom of the card, inside the same rounded
    /// rectangle as the message — not a separate floating pill below it —
    /// for actionable messages (currently just the update reminder). Only
    /// meaningful when the bubble was built with a non-nil actionTitle.
    static let actionButtonSize = CGSize(width: 116, height: 26)
    private static let actionAreaHeight: CGFloat = actionButtonSize.height + 18 // button + gap above it

    var actionButtonFrame: CGRect {
        let size = Self.actionButtonSize
        return CGRect(x: (frame.width - size.width) / 2, y: 10, width: size.width, height: size.height)
    }

    init(message: String, actionTitle: String? = nil) {
```

with:

```swift
    private static let choiceRowHeight: CGFloat = 32
    private static let choiceAreaHeight: CGFloat = choiceRowHeight + 18 // row + gap above it
    private var choiceCount = 0

    /// The rect for one choice slot in the reserved bottom row, inside the
    /// same rounded rectangle as the message — not a separate floating pill
    /// below it. The same closeTargetFrame pattern, generalized from one
    /// button (the update reminder) to N (every check-in style). A single
    /// choice keeps the update button's existing fixed 116pt-wide centered
    /// look; more than one spreads evenly across the card's content width.
    func choiceFrame(at index: Int) -> CGRect {
        guard choiceCount > 0 else { return .zero }
        if choiceCount == 1 {
            let size = CGSize(width: 116, height: Self.choiceRowHeight)
            return CGRect(x: (frame.width - size.width) / 2, y: 10, width: size.width, height: size.height)
        }
        let horizontalPadding: CGFloat = 14
        let spacing: CGFloat = 6
        let contentWidth = frame.width - horizontalPadding * 2
        let slotWidth = (contentWidth - spacing * CGFloat(choiceCount - 1)) / CGFloat(choiceCount)
        let x = horizontalPadding + CGFloat(index) * (slotWidth + spacing)
        return CGRect(x: x, y: 10, width: slotWidth, height: Self.choiceRowHeight)
    }

    init(message: String, choiceLabels: [String] = []) {
```

- [ ] **Step 2: Update the layout math inside init**

Replace this block (currently around lines 121–128):

```swift
        let actionAreaHeight: CGFloat = actionTitle != nil ? Self.actionAreaHeight : 0
        let height = textHeight + 20 + actionAreaHeight
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.layer?.cornerRadius = min(Self.cornerRadius, height / 2)
        effectView.layer?.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = effectView.bounds
        label.frame = CGRect(x: 14, y: 10 + actionAreaHeight, width: textWidth, height: textHeight)
```

with:

```swift
        choiceCount = choiceLabels.count
        let choiceAreaHeight: CGFloat = choiceLabels.isEmpty ? 0 : Self.choiceAreaHeight
        let height = textHeight + 20 + choiceAreaHeight
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        effectView.layer?.cornerRadius = min(Self.cornerRadius, height / 2)
        effectView.layer?.sublayers?.first(where: { $0 is CAGradientLayer })?.frame = effectView.bounds
        label.frame = CGRect(x: 14, y: 10 + choiceAreaHeight, width: textWidth, height: textHeight)
```

- [ ] **Step 3: Add the reply cross-fade method**

Add this method after `fadeOut(completion:)` (end of the class, before the closing `}`):

```swift
    /// Cross-fades the label to a new string — used when a check-in choice
    /// is tapped, swapping the question for a reply in place without
    /// resizing the card. Reply pools are written to stay roughly as short
    /// as the questions they follow, same convention as every other message
    /// pool in this app, since this does not re-run the height calculation
    /// from init — a much longer reply would overflow the reserved box.
    func revealReply(_ text: String) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            label.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            let font = NSFont.systemFont(ofSize: 13)
            self.label.textStorage?.setAttributedString(NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: NSColor.white]
            ))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.label.animator().alphaValue = 1
            }
        })
    }
```

- [ ] **Step 4: Commit**

```bash
git add Sources/LilButterfly/BubbleView.swift
git commit -m "Generalize BubbleView's action button into an N-choice row"
```

(The build still fails here — `ScreenOverlay.swift`/`DockedOverlay.swift` still call the old `actionTitle:`/`actionButtonFrame` names. Fixed in Tasks 3–4.)

---

### Task 3: Update ScreenOverlay to the generalized mechanism

**Files:**
- Modify: `Sources/LilButterfly/ScreenOverlay.swift`

- [ ] **Step 1: Replace the stored property**

Replace:

```swift
    private var closeWindow: BubbleCloseWindow?
    private var actionButtonWindow: UpdateActionButtonWindow?
```

with:

```swift
    private var closeWindow: BubbleCloseWindow?
    private var choiceWindows: [ChoiceButtonWindow] = []
```

- [ ] **Step 2: Update `stop()`**

Replace:

```swift
        closeWindow?.orderOut(nil)
        closeWindow = nil
        actionButtonWindow?.orderOut(nil)
        actionButtonWindow = nil
```

with:

```swift
        closeWindow?.orderOut(nil)
        closeWindow = nil
        choiceWindows.forEach { $0.orderOut(nil) }
        choiceWindows.removeAll()
```

- [ ] **Step 3: Update the bubble construction and frame helper**

Replace:

```swift
        let bubble = BubbleView(message: message, actionTitle: actionTitle)
        host.addSubview(bubble)

        func bubbleLocalRectOnScreen(_ local: CGRect) -> CGRect {
            let targetInWindow = host.convert(
                CGPoint(x: bubble.frame.minX + local.minX, y: bubble.frame.minY + local.minY),
                to: nil
            )
            let targetOnScreen = window.convertPoint(toScreen: targetInWindow)
            return CGRect(origin: targetOnScreen, size: local.size)
        }
        func closeTargetFrameOnScreen() -> CGRect { bubbleLocalRectOnScreen(bubble.closeTargetFrame) }
        // Inside the same rounded-rect card, reserved by BubbleView's own
        // layout when it's built with an actionTitle — not a separate
        // floating pill below it.
        func actionButtonFrameOnScreen() -> CGRect { bubbleLocalRectOnScreen(bubble.actionButtonFrame) }
```

with:

```swift
        let choiceLabels: [String] = actionTitle.map { [$0] } ?? []
        let bubble = BubbleView(message: message, choiceLabels: choiceLabels)
        host.addSubview(bubble)

        func bubbleLocalRectOnScreen(_ local: CGRect) -> CGRect {
            let targetInWindow = host.convert(
                CGPoint(x: bubble.frame.minX + local.minX, y: bubble.frame.minY + local.minY),
                to: nil
            )
            let targetOnScreen = window.convertPoint(toScreen: targetInWindow)
            return CGRect(origin: targetOnScreen, size: local.size)
        }
        func closeTargetFrameOnScreen() -> CGRect { bubbleLocalRectOnScreen(bubble.closeTargetFrame) }
        // Inside the same rounded-rect card, reserved by BubbleView's own
        // layout whenever it's built with one or more choiceLabels — not a
        // separate floating pill below it.
        func choiceFrameOnScreen(_ index: Int) -> CGRect { bubbleLocalRectOnScreen(bubble.choiceFrame(at: index)) }
```

- [ ] **Step 4: Update repositioning in `positionBubble`**

Replace:

```swift
            if let actionButtonWindow = self.actionButtonWindow {
                actionButtonWindow.setFrame(actionButtonFrameOnScreen(), display: true)
            }
```

with:

```swift
            for (index, window) in self.choiceWindows.enumerated() {
                window.setFrame(choiceFrameOnScreen(index), display: true)
            }
```

- [ ] **Step 5: Update cleanup in `leaveNow()`**

Replace:

```swift
                self.actionButtonWindow?.orderOut(nil)
                self.actionButtonWindow = nil
```

with:

```swift
                self.choiceWindows.forEach { $0.orderOut(nil) }
                self.choiceWindows.removeAll()
```

- [ ] **Step 6: Update window creation in the arrival completion**

Replace:

```swift
            if let onTapped {
                self.actionButtonWindow = UpdateActionButtonWindow(
                    frame: actionButtonFrameOnScreen(),
                    title: actionTitle ?? "Update",
                    onClick: {
                        leaveNow()
                        onTapped()
                    }
                )
            }
```

with:

```swift
            if let onTapped {
                let window = ChoiceButtonWindow(
                    frame: choiceFrameOnScreen(0),
                    title: actionTitle ?? "Update",
                    style: .accentCapsule
                ) {
                    leaveNow()
                    onTapped()
                }
                self.choiceWindows = [window]
            }
```

- [ ] **Step 7: Build**

Run: `swift build 2>&1 | grep -E "error:"`
Expected: no output for `ScreenOverlay.swift` errors (an error for `DockedOverlay.swift` referencing `UpdateActionButtonWindow` is still expected — fixed in Task 4).

- [ ] **Step 8: Commit**

```bash
git add Sources/LilButterfly/ScreenOverlay.swift
git commit -m "Migrate ScreenOverlay to the generalized choice-window mechanism"
```

---

### Task 4: Update DockedOverlay to the generalized mechanism

**Files:**
- Modify: `Sources/LilButterfly/DockedOverlay.swift`

- [ ] **Step 1: Replace the stored property**

Replace:

```swift
    private var closeWindow: BubbleCloseWindow?
    private var actionButtonWindow: UpdateActionButtonWindow?
```

with:

```swift
    private var closeWindow: BubbleCloseWindow?
    private var choiceWindows: [ChoiceButtonWindow] = []
```

- [ ] **Step 2: Update `removeButterflyAndVisit()`**

Replace:

```swift
        closeWindow?.orderOut(nil)
        closeWindow = nil
        actionButtonWindow?.orderOut(nil)
        actionButtonWindow = nil
```

with:

```swift
        closeWindow?.orderOut(nil)
        closeWindow = nil
        choiceWindows.forEach { $0.orderOut(nil) }
        choiceWindows.removeAll()
```

- [ ] **Step 3: Update the bubble construction and frame helper in `visit(...)`**

Replace:

```swift
        let bubble = BubbleView(message: message, actionTitle: actionTitle)
        host.addSubview(bubble)

        func bubbleLocalRectOnScreen(_ local: CGRect) -> CGRect {
            let targetInWindow = host.convert(
                CGPoint(x: bubble.frame.minX + local.minX, y: bubble.frame.minY + local.minY),
                to: nil
            )
            let targetOnScreen = window.convertPoint(toScreen: targetInWindow)
            return CGRect(origin: targetOnScreen, size: local.size)
        }
        func closeTargetFrameOnScreen() -> CGRect { bubbleLocalRectOnScreen(bubble.closeTargetFrame) }
        func actionButtonFrameOnScreen() -> CGRect { bubbleLocalRectOnScreen(bubble.actionButtonFrame) }
```

with:

```swift
        let choiceLabels: [String] = actionTitle.map { [$0] } ?? []
        let bubble = BubbleView(message: message, choiceLabels: choiceLabels)
        host.addSubview(bubble)

        func bubbleLocalRectOnScreen(_ local: CGRect) -> CGRect {
            let targetInWindow = host.convert(
                CGPoint(x: bubble.frame.minX + local.minX, y: bubble.frame.minY + local.minY),
                to: nil
            )
            let targetOnScreen = window.convertPoint(toScreen: targetInWindow)
            return CGRect(origin: targetOnScreen, size: local.size)
        }
        func closeTargetFrameOnScreen() -> CGRect { bubbleLocalRectOnScreen(bubble.closeTargetFrame) }
        func choiceFrameOnScreen(_ index: Int) -> CGRect { bubbleLocalRectOnScreen(bubble.choiceFrame(at: index)) }
```

- [ ] **Step 4: Update repositioning in `positionBubble`**

Replace:

```swift
            if let actionButtonWindow = self.actionButtonWindow {
                actionButtonWindow.setFrame(actionButtonFrameOnScreen(), display: true)
            }
```

with:

```swift
            for (index, window) in self.choiceWindows.enumerated() {
                window.setFrame(choiceFrameOnScreen(index), display: true)
            }
```

- [ ] **Step 5: Update the "perk-in-place" branch (`if Bool.random()`)**

Replace:

```swift
            if let onTapped {
                actionButtonWindow = UpdateActionButtonWindow(frame: actionButtonFrameOnScreen(), title: actionTitle ?? "Update") {
                    leaveNow()
                    onTapped()
                }
            }
```

with:

```swift
            if let onTapped {
                let window = ChoiceButtonWindow(frame: choiceFrameOnScreen(0), title: actionTitle ?? "Update", style: .accentCapsule) {
                    leaveNow()
                    onTapped()
                }
                choiceWindows = [window]
            }
```

Replace (in the same branch's `leaveNow` closure):

```swift
                    self.actionButtonWindow?.orderOut(nil)
                    self.actionButtonWindow = nil
```

with:

```swift
                    self.choiceWindows.forEach { $0.orderOut(nil) }
                    self.choiceWindows.removeAll()
```

- [ ] **Step 6: Update the "venture-and-settle" branch (`else`)**

Replace:

```swift
                if let onTapped {
                    self.actionButtonWindow = UpdateActionButtonWindow(frame: actionButtonFrameOnScreen(), title: actionTitle ?? "Update") {
                        leaveNow()
                        onTapped()
                    }
                }
```

with:

```swift
                if let onTapped {
                    let window = ChoiceButtonWindow(frame: choiceFrameOnScreen(0), title: actionTitle ?? "Update", style: .accentCapsule) {
                        leaveNow()
                        onTapped()
                    }
                    self.choiceWindows = [window]
                }
```

Replace (in the same branch's `leaveNow` closure):

```swift
                        self.actionButtonWindow?.orderOut(nil)
                        self.actionButtonWindow = nil
```

with:

```swift
                        self.choiceWindows.forEach { $0.orderOut(nil) }
                        self.choiceWindows.removeAll()
```

- [ ] **Step 7: Build**

Run: `swift build 2>&1 | grep -E "error:"`
Expected: no output — the whole project should compile clean now.

- [ ] **Step 8: Commit**

```bash
git add Sources/LilButterfly/DockedOverlay.swift
git commit -m "Migrate DockedOverlay to the generalized choice-window mechanism"
```

---

### Task 5: Regression checkpoint — update reminder must still behave identically

**Files:** none (verification only)

This is the critical checkpoint before any new feature code is written. Everything above was a refactor of shipped, working code — this task proves nothing broke.

- [ ] **Step 1: Force an update to appear**

`swift run`'s debug binary has no `CFBundleShortVersionString`, so `installedVersion` falls back to `"1.0.0"` — any real GitHub release will register as newer, guaranteeing the update-reminder path fires without needing to touch the live config.

```bash
osascript -e 'tell application "Butterfly" to quit' 2>/dev/null
pkill -f "Products/Debug/Butterfly" 2>/dev/null
sleep 1
swift run > /tmp/checkin_regression.log 2>&1 &
sleep 5
```

- [ ] **Step 2: Trigger a visit and confirm it's the update reminder**

```bash
osascript -e 'tell application "System Events" to tell process "Butterfly" to click menu bar item 1 of menu bar 1'
sleep 0.5
osascript -e 'tell application "System Events" to tell process "Butterfly" to click menu item "Show Butterfly" of menu 1 of menu bar item 1 of menu bar 1'
sleep 3
ps aux | grep "Products/Debug/Butterfly" | grep -v grep
```

Expected: the process is still running (no crash on card construction/positioning).

- [ ] **Step 3: Wait through the full hold + departure**

```bash
sleep 15
ps aux | grep "Products/Debug/Butterfly" | grep -v grep && echo "RUNNING" || echo "CRASHED"
```

Expected: `RUNNING`. If `CRASHED`, stop and diagnose before continuing — do not proceed to Task 6 with a broken refactor.

- [ ] **Step 4: Confirm no other Butterfly processes are contaminating the test**

```bash
ps aux | grep -i butterfly | grep -v grep
```

Expected: exactly one process (the `swift run` one). If more than one shows up (e.g. a stray `/Applications/Butterfly.app`), kill it and repeat Steps 1–3 in isolation — this project has previously produced false "crash" reports from ambiguous `osascript` targeting when multiple same-named processes were running.

- [ ] **Step 5: Clean up**

```bash
osascript -e 'tell application "Butterfly" to quit' 2>/dev/null
pkill -f "Products/Debug/Butterfly" 2>/dev/null
```

No commit for this task — it's verification only.

---

### Task 6: Check-in content model

**Files:**
- Create: `Sources/LilButterfly/CheckInContent.swift`

- [ ] **Step 1: Write the file**

```swift
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
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E "error:"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Sources/LilButterfly/CheckInContent.swift
git commit -m "Add CheckInContent model with the mood-picker style"
```

---

### Task 7: Local check-in logging

**Files:**
- Create: `Sources/LilButterfly/CheckInStore.swift`

- [ ] **Step 1: Write the file**

```swift
import Foundation

/// Quietly logs each completed check-in choice locally — no viewer built
/// yet (a future history feature can read this data), no network calls
/// ever. Structurally identical to ConfigStore: same Application Support
/// directory, same atomic-write JSON pattern.
enum CheckInStore {
    private struct Entry: Codable {
        let date: Date
        let style: String
        let choice: String
    }

    private struct Log: Codable {
        var entries: [Entry]
    }

    private static let maxEntries = 500

    private static var fileURL: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Butterfly", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("checkins.json")
    }

    /// Appends one entry, dropping the oldest once past maxEntries so the
    /// file can't grow unbounded with no viewer ever trimming it.
    static func record(style: String, choice: String) {
        var log = load()
        log.entries.append(Entry(date: Date(), style: style, choice: choice))
        if log.entries.count > maxEntries {
            log.entries.removeFirst(log.entries.count - maxEntries)
        }
        save(log)
    }

    private static func load() -> Log {
        guard let data = try? Data(contentsOf: fileURL),
              let log = try? JSONDecoder().decode(Log.self, from: data)
        else { return Log(entries: []) }
        return log
    }

    private static func save(_ log: Log) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | grep -E "error:"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add Sources/LilButterfly/CheckInStore.swift
git commit -m "Add CheckInStore for local, offline check-in logging"
```

---

### Task 8: Wire check-ins into ScreenOverlay

**Files:**
- Modify: `Sources/LilButterfly/ScreenOverlay.swift`

- [ ] **Step 1: Add the `checkIn` parameter**

Replace the `visit(...)` signature:

```swift
    func visit(
        message: String,
        pinnedAssetIndex: Int? = nil,
        displayWidth: CGFloat = ButterflySize.widths[ButterflySize.defaultIndex],
        restingSeconds: Double = 5.0,
        actionTitle: String? = nil,
        onTapped: (() -> Void)? = nil
    ) {
```

with:

```swift
    func visit(
        message: String,
        pinnedAssetIndex: Int? = nil,
        displayWidth: CGFloat = ButterflySize.widths[ButterflySize.defaultIndex],
        restingSeconds: Double = 5.0,
        actionTitle: String? = nil,
        onTapped: (() -> Void)? = nil,
        checkIn: CheckInContent? = nil
    ) {
```

- [ ] **Step 2: Compute choice labels from either source**

Replace:

```swift
        let choiceLabels: [String] = actionTitle.map { [$0] } ?? []
        let bubble = BubbleView(message: message, choiceLabels: choiceLabels)
```

with:

```swift
        let choiceLabels: [String]
        if let actionTitle {
            choiceLabels = [actionTitle]
        } else if let checkIn {
            choiceLabels = checkIn.choices.map { $0.label }
        } else {
            choiceLabels = []
        }
        let bubble = BubbleView(message: message, choiceLabels: choiceLabels)
```

- [ ] **Step 3: Build the per-choice windows in the arrival completion**

Replace:

```swift
            if let onTapped {
                let window = ChoiceButtonWindow(
                    frame: choiceFrameOnScreen(0),
                    title: actionTitle ?? "Update",
                    style: .accentCapsule
                ) {
                    leaveNow()
                    onTapped()
                }
                self.choiceWindows = [window]
            }
```

with:

```swift
            if let checkIn {
                // A pick reveals its reply in place and holds a bit longer
                // before leaving, rather than leaving immediately like the
                // update button does — the reply is the whole point of a
                // check-in, so it needs time to actually be read.
                self.choiceWindows = checkIn.choices.enumerated().map { index, choice in
                    ChoiceButtonWindow(frame: choiceFrameOnScreen(index), title: choice.label, style: .plainChip) {
                        CheckInStore.record(style: checkIn.style.rawValue, choice: choice.label)
                        bubble.revealReply(choice.replies.randomElement() ?? choice.replies[0])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            leaveNow()
                        }
                    }
                }
            } else if let onTapped {
                let window = ChoiceButtonWindow(
                    frame: choiceFrameOnScreen(0),
                    title: actionTitle ?? "Update",
                    style: .accentCapsule
                ) {
                    leaveNow()
                    onTapped()
                }
                self.choiceWindows = [window]
            }
```

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | grep -E "error:"`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add Sources/LilButterfly/ScreenOverlay.swift
git commit -m "Wire check-in choices into ScreenOverlay.visit()"
```

---

### Task 9: Wire check-ins into DockedOverlay

**Files:**
- Modify: `Sources/LilButterfly/DockedOverlay.swift`

- [ ] **Step 1: Add the `checkIn` parameter**

Replace:

```swift
    func visit(message: String, pinnedAssetIndex: Int?, displayWidth: CGFloat, restingSeconds: Double, actionTitle: String? = nil, onTapped: (() -> Void)? = nil) {
```

with:

```swift
    func visit(message: String, pinnedAssetIndex: Int?, displayWidth: CGFloat, restingSeconds: Double, actionTitle: String? = nil, onTapped: (() -> Void)? = nil, checkIn: CheckInContent? = nil) {
```

- [ ] **Step 2: Compute choice labels from either source**

Replace:

```swift
        let choiceLabels: [String] = actionTitle.map { [$0] } ?? []
        let bubble = BubbleView(message: message, choiceLabels: choiceLabels)
```

with:

```swift
        let choiceLabels: [String]
        if let actionTitle {
            choiceLabels = [actionTitle]
        } else if let checkIn {
            choiceLabels = checkIn.choices.map { $0.label }
        } else {
            choiceLabels = []
        }
        let bubble = BubbleView(message: message, choiceLabels: choiceLabels)
```

- [ ] **Step 3: Wire the "perk-in-place" branch**

Replace:

```swift
            if let onTapped {
                let window = ChoiceButtonWindow(frame: choiceFrameOnScreen(0), title: actionTitle ?? "Update", style: .accentCapsule) {
                    leaveNow()
                    onTapped()
                }
                choiceWindows = [window]
            }
```

with:

```swift
            if let checkIn {
                choiceWindows = checkIn.choices.enumerated().map { index, choice in
                    ChoiceButtonWindow(frame: choiceFrameOnScreen(index), title: choice.label, style: .plainChip) {
                        CheckInStore.record(style: checkIn.style.rawValue, choice: choice.label)
                        bubble.revealReply(choice.replies.randomElement() ?? choice.replies[0])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            leaveNow()
                        }
                    }
                }
            } else if let onTapped {
                let window = ChoiceButtonWindow(frame: choiceFrameOnScreen(0), title: actionTitle ?? "Update", style: .accentCapsule) {
                    leaveNow()
                    onTapped()
                }
                choiceWindows = [window]
            }
```

- [ ] **Step 4: Wire the "venture-and-settle" branch**

Replace:

```swift
                if let onTapped {
                    let window = ChoiceButtonWindow(frame: choiceFrameOnScreen(0), title: actionTitle ?? "Update", style: .accentCapsule) {
                        leaveNow()
                        onTapped()
                    }
                    self.choiceWindows = [window]
                }
```

with:

```swift
                if let checkIn {
                    self.choiceWindows = checkIn.choices.enumerated().map { index, choice in
                        ChoiceButtonWindow(frame: choiceFrameOnScreen(index), title: choice.label, style: .plainChip) {
                            CheckInStore.record(style: checkIn.style.rawValue, choice: choice.label)
                            bubble.revealReply(choice.replies.randomElement() ?? choice.replies[0])
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                leaveNow()
                            }
                        }
                    }
                } else if let onTapped {
                    let window = ChoiceButtonWindow(frame: choiceFrameOnScreen(0), title: actionTitle ?? "Update", style: .accentCapsule) {
                        leaveNow()
                        onTapped()
                    }
                    self.choiceWindows = [window]
                }
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | grep -E "error:"`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add Sources/LilButterfly/DockedOverlay.swift
git commit -m "Wire check-in choices into DockedOverlay.visit()"
```

---

### Task 10: Fold check-ins into the visit cycle

**Files:**
- Modify: `Sources/LilButterfly/AppDelegate.swift:83-140` (the `fireVisit` method)

- [ ] **Step 1: Add the probability roll and pass-through**

Replace the whole `fireVisit` method body from the `pendingUpdate` computation through the `onTapped`/`actionTitle` assignment:

```swift
        let pendingUpdate = latestRelease.flatMap { release in
            updateReminderShownForVersion == release.version ? nil : release
        }
        let message: String
        var onTapped: (() -> Void)?
        var actionTitle: String?
        // A button needs real time to notice and aim for, not the few
        // seconds a one-line message normally gets — longer than whatever
        // the user configured, specifically for this message.
        var restingSeconds = config.restingSeconds
        if let pendingUpdate {
            message = "A new Butterfly (v\(pendingUpdate.version)) is ready."
            actionTitle = "Update Now"
            onTapped = { [weak self] in self?.startSelfUpdate(release: pendingUpdate) }
            restingSeconds = max(config.restingSeconds, 14)
        } else {
            // Quiet hours are gentle mode, not a hard stop: randomMessage
            // returns nil most of the time during that window instead (see
            // its doc comment), so a scheduled cycle can land here and
            // legitimately decide to stay silent.
            guard let randomMessage = config.randomMessage(manualOverride: manualOverride) else { return false }
            message = randomMessage
        }
```

with:

```swift
        let pendingUpdate = latestRelease.flatMap { release in
            updateReminderShownForVersion == release.version ? nil : release
        }
        let message: String
        var onTapped: (() -> Void)?
        var actionTitle: String?
        var checkIn: CheckInContent?
        // A button needs real time to notice and aim for, not the few
        // seconds a one-line message normally gets — longer than whatever
        // the user configured, specifically for this message.
        var restingSeconds = config.restingSeconds
        if let pendingUpdate {
            message = "A new Butterfly (v\(pendingUpdate.version)) is ready."
            actionTitle = "Update Now"
            onTapped = { [weak self] in self?.startSelfUpdate(release: pendingUpdate) }
            restingSeconds = max(config.restingSeconds, 14)
        } else if Double.random(in: 0..<1) < (1.0 / 12.0) {
            // Rare, occasional — folded into a visit that was going to
            // happen anyway (scheduled or manual), same as the update
            // reminder, never a separate interruption. The update reminder
            // above always wins when both are pending — it's guaranteed-
            // once-per-version and functional; a check-in is discretionary
            // and can simply wait for the next eligible visit.
            let content = CheckInContent.random()
            checkIn = content
            message = content.question
            restingSeconds = max(config.restingSeconds, 14)
        } else {
            // Quiet hours are gentle mode, not a hard stop: randomMessage
            // returns nil most of the time during that window instead (see
            // its doc comment), so a scheduled cycle can land here and
            // legitimately decide to stay silent.
            guard let randomMessage = config.randomMessage(manualOverride: manualOverride) else { return false }
            message = randomMessage
        }
```

- [ ] **Step 2: Pass `checkIn` through to both dispatch calls**

Replace:

```swift
        if config.mode == "docked" {
            if let dockedOverlay {
                dockedOverlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: restingSeconds, actionTitle: actionTitle, onTapped: onTapped)
                dispatched = true
            } else {
                dispatched = false
            }
        } else if let overlay = overlays.filter({ $0.isAvailable }).randomElement() {
            overlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: restingSeconds, actionTitle: actionTitle, onTapped: onTapped)
            dispatched = true
        } else {
            dispatched = false
        }
```

with:

```swift
        if config.mode == "docked" {
            if let dockedOverlay {
                dockedOverlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: restingSeconds, actionTitle: actionTitle, onTapped: onTapped, checkIn: checkIn)
                dispatched = true
            } else {
                dispatched = false
            }
        } else if let overlay = overlays.filter({ $0.isAvailable }).randomElement() {
            overlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: restingSeconds, actionTitle: actionTitle, onTapped: onTapped, checkIn: checkIn)
            dispatched = true
        } else {
            dispatched = false
        }
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | grep -E "error:"`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add Sources/LilButterfly/AppDelegate.swift
git commit -m "Fold the mood-picker check-in into the regular visit cycle"
```

---

### Task 11: End-to-end verification

**Files:** none (verification only)

The 1-in-12 roll makes the check-in non-deterministic on any single trigger. Force it temporarily for testing rather than clicking "Show Butterfly" dozens of times hoping for a hit.

- [ ] **Step 1: Temporarily force the check-in path**

Edit `Sources/LilButterfly/AppDelegate.swift` — change the roll's condition from `Double.random(in: 0..<1) < (1.0 / 12.0)` to `true` for this test only. Do not commit this change.

- [ ] **Step 2: Test in roaming mode**

```bash
osascript -e 'tell application "Butterfly" to quit' 2>/dev/null
pkill -f "Products/Debug/Butterfly" 2>/dev/null
sleep 1
swift run > /tmp/checkin_e2e.log 2>&1 &
sleep 5
osascript -e 'tell application "System Events" to tell process "Butterfly" to click menu bar item 1 of menu bar 1'
sleep 0.5
osascript -e 'tell application "System Events" to tell process "Butterfly" to click menu item "Show Butterfly" of menu 1 of menu bar item 1 of menu bar 1'
sleep 8
ps aux | grep -i butterfly | grep -v grep
```

Expected: exactly one process, still running. Visually confirm on screen: the card shows a mood question with 5 emoji in a row, sized to fit inside the card's own rounded rectangle (not overflowing it), and the corner (x) still dismisses independently of the emoji row.

- [ ] **Step 3: Confirm a full pick → reply → departure cycle with no crash**

```bash
sleep 15
ps aux | grep -i butterfly | grep -v grep && echo "RUNNING" || echo "CRASHED"
```

Expected: `RUNNING` (the 2.5s reply hold plus the 14s minimum resting time plus fly-out should have completed within this window).

- [ ] **Step 4: Check the local log recorded something (only if a choice was actually clicked during Step 2/3 — clicking exact screen coordinates isn't available via `osascript`, so this step may show zero entries if no manual click happened; that's expected, not a failure)**

```bash
cat "$HOME/Library/Application Support/Butterfly/checkins.json" 2>&1
```

Expected: either valid JSON with an `entries` array (if a choice was manually clicked), or "No such file" (if the log has never been written yet, e.g. no click happened in this test run).

- [ ] **Step 5: Test in docked mode**

```bash
osascript -e '
tell application "System Events"
    tell process "Butterfly"
        click menu bar item 1 of menu bar 1
        delay 0.5
        click menu item "Movement · Roaming" of menu 1 of menu bar item 1 of menu bar 1
        delay 0.3
        click menu item "Dock" of menu 1 of menu item "Movement · Roaming" of menu 1 of menu bar item 1 of menu bar 1
    end tell
end tell
'
sleep 1
osascript -e 'tell application "System Events" to tell process "Butterfly" to click menu bar item 1 of menu bar 1'
sleep 0.5
osascript -e 'tell application "System Events" to tell process "Butterfly" to click menu item "Show Butterfly" of menu 1 of menu bar item 1 of menu bar 1'
sleep 20
ps aux | grep -i butterfly | grep -v grep && echo "RUNNING" || echo "CRASHED"
```

Expected: `RUNNING` after the full docked-mode cycle (which randomly picks between the "perk-in-place" and "venture-and-settle" variants — repeat this step if needed to exercise both at least once).

- [ ] **Step 6: Switch back to roaming and clean up**

```bash
osascript -e '
tell application "System Events"
    tell process "Butterfly"
        click menu bar item 1 of menu bar 1
        delay 0.5
        click menu item "Movement · Docked" of menu 1 of menu bar item 1 of menu bar 1
        delay 0.3
        click menu item "Roam" of menu 1 of menu item "Movement · Docked" of menu 1 of menu bar item 1 of menu bar 1
    end tell
end tell
'
osascript -e 'tell application "Butterfly" to quit' 2>/dev/null
pkill -f "Products/Debug/Butterfly" 2>/dev/null
```

- [ ] **Step 7: Revert the temporary test-only change from Step 1**

```bash
git diff Sources/LilButterfly/AppDelegate.swift
git checkout -- Sources/LilButterfly/AppDelegate.swift
```

Expected: the diff before checkout shows only the `true` vs. `1.0 / 12.0` change; after `checkout --`, `git status` shows a clean working tree.

No commit for this task — it's verification only, and the temporary change is explicitly reverted in Step 7.

---

## What's next (not in this plan)

The remaining 6 styles (energy slider, smile prompt, color hearts, breathe-with-me, gratitude tap, pick-a-word) each become a new `CheckInContent` case following the exact pattern `moodPicker()` establishes in Task 6 — for the choice-row styles (smile prompt, color hearts, gratitude tap, pick-a-word) that's it, no other file changes needed. The energy slider needs its own small interactive window (a real `NSSlider`-backed panel, same "draws and handles itself" shape as `ChoiceButtonWindow`) since it's a continuous drag rather than N discrete choices. Breathe-with-me needs a new `ButterflyView.setFlutterRate(_:)` method and no `ChoiceButtonWindow` at all. Each is a small, independent follow-up plan once this one is merged and used for a while.
