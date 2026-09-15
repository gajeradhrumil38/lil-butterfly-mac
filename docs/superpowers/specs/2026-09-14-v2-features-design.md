# lil butterfly — v2 features design

Date: 2026-09-14

## Overview

Four additions to the native macOS butterfly app, built together in one pass:

1. **Dock mode** — an alternative to today's roaming fly-in/fly-out behavior, where the butterfly stays parked at a screen edge.
2. **Countdown menu item** — always-visible "next visit in ~N min" line in the menu.
3. **Real SVG art** — swap the hand-authored bezier wings for the 9 designs in `Designs/`, randomized per visit (or pinned), with a matching wing-flutter and a new subtle body-tilt for natural motion.
4. **Glass message bubble** — replace the flat rounded-rect bubble background with a dark frosted `NSVisualEffectView` ("liquid glass" look).

All four are independent enough to implement and verify one at a time, but ship together since they touch overlapping files (`ButterflyView`, `ScreenOverlay`, `AppDelegate`, `Config`, `BubbleView`).

## 1. Dock mode

**Config additions:**
```swift
var mode: String       // "roaming" (default) | "docked"
var dockEdge: String   // "left" | "right" | "top" | "bottom" (default "right")
```

**Menu:** a new pair of radio-style items ("Roaming" / "Docked") alongside the existing frequency picker, and — visible only when Docked is selected — an edge picker (Left/Right/Top/Bottom), following the same `representedObject` + checkmark pattern as `addFrequencyItem`.

**Behavior:** `AppDelegate` builds either `ScreenOverlay` instances (roaming, one per screen, unchanged) or a single `DockedOverlay` (main screen / `NSScreen.main` only) based on `config.mode`, matching today's `rebuildOverlays()` pattern. Switching modes tears down the inactive kind and builds the active one.

`DockedOverlay` keeps its `ButterflyView` permanently on-screen, parked just inside `config.dockEdge`, at a position along that edge that re-randomizes on each visit (matching `ScreenOverlay.restPoint`'s existing random-along-edge logic — reused, not reimplemented). On each scheduled visit it randomly picks one of two variants (50/50):

- **Perk-in-place:** small in-place wiggle (a short scale/tilt pulse, reusing the flutter mechanism already running continuously) + message bubble shows, waits, fades.
- **Venture-in-and-settle:** flies from the dock spot to a rest point further inside the screen (reusing `ScreenOverlay`'s existing fly/rest/wait/return sequencing and `flyPath`), shows the message there, then flies back to a (re-randomized) spot on the dock edge — it does not go fully off-screen and does not disappear, since a dock is meant to stay visible as a steady presence.

No new animation primitives are needed for either variant — both are compositions of the existing `flyPath` and flutter code, just with different start/end points and, for perk-in-place, a same-point start/end.

## 2. Countdown menu item

`AppDelegate` already computes a random delay each time it calls `scheduleNext()`; that call site starts storing the fire time:
```swift
private var nextFireDate: Date?
```
`AppDelegate` becomes `NSMenuDelegate` and implements `menuNeedsUpdate(_:)` (or `menuWillOpen(_:)`) to call `rebuildMenu()` right before the menu opens, so the countdown is always current when the user actually looks at it — no polling timer needed. `rebuildMenu()` inserts a disabled `NSMenuItem` (no action/target) reading e.g. `"Next visit in ~32 min"`, computed from `max(0, nextFireDate.timeIntervalSinceNow)`. If paused or in quiet hours, it instead reads `"Paused"` / `"Quiet hours"` — reusing `config.paused` / `config.isQuietHour()`, which already exist.

## 3. Real SVG art, flutter, and tilt

**Assets:** the 9 files in `Designs/` move into `Sources/LilButterfly/Resources/Wings/` as SPM bundle resources (`Package.swift` gains a `resources: [.copy("Resources/Wings")]` entry on the target). Loaded once at process start via `NSImage(contentsOf:)` → `NSImage.cgImage(forProposedRect:...)`, cached in a `[CGImage]` array — 9 small images, trivial memory cost, no per-visit disk I/O.

**Config addition:**
```swift
var pinnedAssetIndex: Int?   // nil = random each visit (default); else always use this one
```
Menu gains a submenu ("Butterfly Design") listing "Random (default)" plus the 9 assets by name, checkmarking the active choice.

**Wing splitting:** each `CGImage` is symmetric about its horizontal midpoint (verified by inspecting the actual SVGs — left-half and right-half path data mirror around `viewBox.width / 2`). At `ButterflyView` construction time, `cropping(to:)` splits the full image into a left half (`0 ..< width/2`) and a right half (`width/2 ..< width`) — an exact 50/50 split, with no separate body/antenna layer. Whichever half a given asset's center body strip falls into (it will straddle the seam by a pixel or two depending on the asset) simply renders as part of that half; since both halves flutter together in the same phase-offset motion, this reads as a single coherent body rather than a visible seam. `leftWing`/`rightWing` become plain `CALayer`s with `contents` set to the respective half-image (replacing the current `CAShapeLayer` + hand-authored `CGPath` fill), anchored at the inner seam exactly as today's code anchors at `(23/s, 23/s)` (recomputed per-asset from that image's actual midpoint). This is the same flutter mechanism already in `startFlutter()` — `transform.scale.x` bounce, phase-offset between the two layers — just driving bitmap layers instead of shape layers. The hand-authored `CGMutablePath` wing/body path code in `buildShapes()` is deleted.

**Tilt (new):** `flyPath(from:to:duration:easeIn:completion:)` gains a second `CAKeyframeAnimation` on `transform.rotation.z`, sharing the same 36-sample loop already used to build the position path. Reuses the *exact* envelope shape as the existing perpendicular wobble — `sin(t·π·3) × (1 − |2t−1|)` — scaled to a small angle (~0.2 rad / ~12°) instead of the wobble's 22px, so the body visibly banks into the same side-to-side sway the wobble already produces, and is level (0°) at both the start and end of every flight (no snapping when the animation is removed, matching how `layer.position = to` is already set as the final model value up front — `layer.transform` gets its rotation component reset to identity the same way).

This was chosen over `CAKeyframeAnimation.rotationMode = .rotateAuto` (Core Animation's built-in path-tangent auto-orientation) because the artwork's neutral "forward" is head-up along the vertical axis, not along local +x as `rotateAuto` assumes — using it would require baking a compensating 90° rotation into every sliced asset. A sine-coupled tilt gets the same "feels alive" result without touching the art pipeline.

## 4. Glass message bubble

`BubbleView` replaces its flat background layer with an `NSVisualEffectView` (`material: .hudWindow`, `blendingMode: .withinWindow`, `state: .active`) sized/cornered the same way the current bubble is, with the text label layered on top in light-colored text for contrast. `.hudWindow` is a consistently dark, blurred, translucent material regardless of system light/dark mode — matches the "dark frosted" option picked during design. The existing `NSAnimationContext`-based fade in/out logic is unchanged; it now fades the effect view's `alphaValue` instead of a flat `NSView`'s.

## Non-goals

- No changes to the roaming mode's existing behavior or timing.
- No new automated tests — this project has none today and animation/rendering correctness is verified by running the app (`swift run` + "Show a butterfly now" / the new mode toggle), consistent with existing project convention.
- No asset editing tools or in-app SVG import — the 9 designs are the fixed initial set.

## Verification plan

Manual, via `swift run`:
- Roaming mode: confirm split-hinge wings, tilt, and random/pinned asset selection all look right via repeated "Show a butterfly now."
- Docked mode: confirm both visit variants (perk-in-place, venture-and-settle) on each of the 4 edges, and that switching Roaming ↔ Docked correctly tears down/rebuilds overlays.
- Menu: confirm the countdown line updates each time the menu is reopened, and reflects Paused/Quiet-hours states correctly.
- Bubble: confirm the frosted look renders correctly over both light and dark desktop backgrounds.
