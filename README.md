# lil butterfly 🦋 (native macOS)

Same idea as before, rewritten as a native Swift/AppKit app instead of
Electron — lighter, no npm/node install issues, and more precise control
over the exact behavior that matters here: fully invisible almost all the
time.

Every 45–90 minutes (randomized), a butterfly flutters in from a random edge
of a random monitor, shows a short kind message near the edge — never over
the center of your screen — waits about 10 seconds, then flies back out.

- Fully click-through: the overlay window ignores all mouse events, so it
  never blocks a click.
- Never appears in the Dock, Cmd-Tab, or Mission Control app switcher
  (`.accessory` activation policy).
- Lives at screen edges, not the center.
- Menu bar (🦋) icon lets you trigger a test flight, pause/resume, change
  frequency, or toggle quiet hours (default: off 11pm–7am).
- No network calls, no telemetry — everything is a local timer and some
  Core Animation.

## Requirements

- macOS 13 (Ventura) or newer.
- Xcode 15+ (for the Swift 5.9 toolchain), or the Swift toolchain installed
  standalone via Xcode Command Line Tools.

## Run it (development)

From the terminal:

```bash
swift run
```

Or open it in Xcode: **File → Open…** and select `Package.swift` — Xcode
will treat it as a normal project you can build and run (⌘R) directly, set
breakpoints in, etc.

A 🦋 icon will appear in your menu bar. Click it → **"Show a butterfly
now"** to test immediately instead of waiting.

## Customize

- **Messages / frequency / quiet hours defaults**: `Sources/LilButterfly/Config.swift`
  (`Config.default`). After first run, live edits from the menu are saved to
  `~/Library/Application Support/LilButterfly/config.json` — edit that file
  directly any time for things not exposed in the menu (like the message
  list).
- **Look of the butterfly**: `Sources/LilButterfly/ButterflyView.swift` — the
  wings are plain `CAShapeLayer` bezier shapes; swap the path data or the
  fill colors, or replace the whole approach with an image/sprite sheet if
  you'd rather use real artwork.
- **Flight feel**: `ScreenOverlay.swift` controls timing (`duration: 1.4` /
  `1.2`), how long it lingers (`restingSeconds`), and how far from the edge
  it rests (`margin`). `ButterflyView.flyPath` controls the wobble amplitude
  and segment count of the flight curve.

## Package as a real app

```bash
./scripts/make_app_bundle.sh
```

This builds a release binary and wraps it into `LilButterfly.app`, which you
can drag into `/Applications`. It sets `LSUIElement` in `Info.plist` so it
never shows a Dock icon even before the app's own code runs.

To make it launch automatically at login: System Settings → General → Login
Items, and add `LilButterfly.app` once it's in `/Applications`.

## How it works, briefly

- `main.swift` sets `NSApplication.shared.setActivationPolicy(.accessory)`
  (no Dock icon) and starts the run loop.
- `AppDelegate.swift` owns the menu bar item/menu, the config, and a
  `Timer`-based scheduler that picks a random delay and asks a random
  screen's overlay to run a "visit."
- `OverlayWindow.swift` is one borderless, transparent, click-through,
  always-on-top `NSWindow` per connected screen (rebuilt automatically if
  displays are connected/disconnected).
- `ScreenOverlay.swift` orchestrates one full visit on a given screen: picks
  a random edge, computes a rest point and an off-screen entry point, and
  sequences the fly-in → bubble → wait → fly-out → cleanup.
- `ButterflyView.swift` draws the butterfly (two `CAShapeLayer` wings with a
  looping flutter animation) and implements the eased, wobbly flight-path
  animation via `CAKeyframeAnimation`.
- `BubbleView.swift` is the small rounded message bubble with a simple fade
  in/out.
- `Config.swift` is a small `Codable` struct persisted as JSON in
  `Application Support`.

## Known rough edges / good next steps

- Butterfly wing shapes are hand-authored bezier curves — good enough to
  read clearly, but could be swapped for real illustration/sprite art.
- No global keyboard shortcut yet for an on-demand "I need a break" trigger.
- No in-app settings window — everything is menu-bar-item or manual
  config-file edits right now.
- Written and syntax-reviewed without access to a Mac/Xcode in the
  environment it was built in — first real build/run on your machine is the
  first real test. If `swift build` surfaces an error, share the exact
  message and it's usually a quick fix.
