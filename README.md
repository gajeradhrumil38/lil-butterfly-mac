# lil butterfly 🦋 (native macOS)

**Kavii is ready to install:** [open the download page](https://gajeradhrumil38.github.io/lil-butterfly-mac/) · [latest release](https://github.com/gajeradhrumil38/lil-butterfly-mac/releases/latest) · [installation guide](INSTALL.md)

Same idea as before, rewritten as a native Swift/AppKit app instead of
Electron — lighter, no npm/node install issues, and more precise control
over the exact behavior that matters here: fully invisible almost all the
time.

Every 45–90 minutes (randomized), a butterfly flutters in from a random edge
of a random monitor, shows a short kind message near the edge — never over
the center of your screen — waits about 10 seconds, then flies back out.

- Fully click-through everywhere except the message card's small close mark,
  so the card can be dismissed without blocking clicks elsewhere.
- Never appears in the Dock, Cmd-Tab, or Mission Control app switcher
  (`.accessory` activation policy).
- Lives at screen edges, not the center.
- Menu bar (🦋) icon lets you trigger a test flight, pause/resume, change
  frequency (via presets or a slider for exact/short testing intervals),
  switch between Roaming and Docked modes, pick a dock edge and a specific
  butterfly design (or leave it randomized), and toggle quiet hours
  (default: off 11pm–7am). The menu always shows how long until the next
  visit. Meeting suppression is on by default for Zoom, Teams, and Meet
  apps; optional calendar-based meeting reminders are off by default. The
  first launch and every resume begin with an immediate welcome visit.
- No telemetry or account tracking. The only optional network request checks
  the public GitHub Releases endpoint so Kavii can tell you when an update is
  available.

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

## Install a release

For a normal installation, download the ZIP for your Mac from the
[Kavii download page](https://gajeradhrumil38.github.io/lil-butterfly-mac/),
unzip it, and drag LilButterfly.app into Applications. See
[INSTALL.md](INSTALL.md) for Gatekeeper, updates, troubleshooting, and the
maintainer release checklist.

## Customize

- **Messages / frequency / quiet hours defaults**: `Sources/LilButterfly/Config.swift`
  (`Config.default`). After first run, live edits from the menu are saved to
  `~/Library/Application Support/LilButterfly/config.json` — edit that file
  directly any time for things not exposed in the menu (like the message
  list).
- **Look of the butterfly**: the 9 designs live in
  `Sources/LilButterfly/Resources/Wings/`; add or replace SVGs there (and
  update `WingAssets.names()`) to change the art. `ButterflyView.swift`
  crops each into left/right halves and flutters them independently — it
  expects the source art to be roughly symmetric about its horizontal
  midpoint.
- **Flight feel**: `ScreenOverlay.swift` controls timing (`duration: 1.4` /
  `1.2`), how long it lingers (`restingSeconds`), and how far from the edge
  it rests (`margin`). `ButterflyView.flyPath` controls the wobble amplitude
  and segment count of the flight curve.

## Package as a real app

```bash
APP_VERSION=1.0.0 ./scripts/make_app_bundle.sh
```

This builds a release binary and wraps it into `LilButterfly.app`, which you
can drag into `/Applications`. It sets `LSUIElement` in `Info.plist` so it
never shows a Dock icon even before the app's own code runs.

To make it launch automatically at login: System Settings → General → Login
Items, and add `LilButterfly.app` once it's in `/Applications`.

Tagged releases are built automatically for Apple Silicon and Intel by
.github/workflows/release.yml. Push a tag such as v1.0.1 to publish both ZIPs
and make the update available to existing installations.

## How it works, briefly

- `main.swift` sets `NSApplication.shared.setActivationPolicy(.accessory)`
  (no Dock icon) and starts the run loop.
- `AppDelegate.swift` owns the menu bar item/menu, the config, and a
  `Timer`-based scheduler that picks a random delay and — depending on
  whether the mode is Roaming or Docked — asks a random screen's
  `ScreenOverlay` or the single `DockedOverlay` to run a "visit." The menu
  rebuilds itself fresh every time it's opened (`NSMenuDelegate`), which is
  how the "next visit in ~N min" line stays current.
- `OverlayWindow.swift` is one borderless, transparent, click-through,
  always-on-top `NSWindow` per connected screen (rebuilt automatically if
  displays are connected/disconnected).
- `ScreenOverlay.swift` orchestrates one full visit on a given screen: picks
  a random edge, computes a rest point and an off-screen entry point, and
  sequences the fly-in → bubble → wait → fly-out → cleanup.
- `WingAssets.swift` loads and rasterizes the bundled SVG designs.
- `ButterflyView.swift` draws the butterfly (two bitmap wing-half layers
  with a looping flutter animation) and implements the eased, wobbly,
  tilt-banking flight-path animation via `CAKeyframeAnimation`.
- `DockedOverlay.swift` is the dock-mode counterpart to `ScreenOverlay.swift`
  — keeps one butterfly permanently parked at a configurable edge instead
  of flying fully on/off screen between visits.
- `BubbleView.swift` is the small frosted message card with a close mark and
  directional tail pointing toward the butterfly.
- `MeetingDetector.swift` suppresses visits while Zoom, Teams, or a standalone
  Meet app is running. Browser-tab detection is intentionally not enabled;
  use Pause for Google Meet in Chrome or Safari.
- `MeetingCalendar.swift` optionally reads local Calendar events, only after
  calendar reminders are enabled, to show a butterfly 15 minutes before a
  video meeting.
- `KaviiRevealOverlay.swift` powers the `Kavii ✨` menu action: small butterflies
  fly in and assemble the word "Kavii" themselves, then dissolve away.
- `Config.swift` is a small `Codable` struct persisted as JSON in
  `Application Support`.
- `UpdateChecker.swift` checks only the repository's latest public GitHub
  Release and exposes an update item in the menu; it never downloads or
  replaces the app automatically.

## Known rough edges / good next steps

- Google Meet in a regular Chrome/Safari tab cannot be identified without
  Accessibility permission; the menu explains that Pause should be used for
  those meetings.
- No global keyboard shortcut yet for an on-demand "I need a break" trigger.
- No in-app settings window — everything is menu-bar-item or manual
  config-file edits right now.
- Written and syntax-reviewed without access to a Mac/Xcode in the
  environment it was built in — first real build/run on your machine is the
  first real test. If `swift build` surfaces an error, share the exact
  message and it's usually a quick fix.
