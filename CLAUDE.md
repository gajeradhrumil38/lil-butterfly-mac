# CLAUDE.md — lil butterfly (native macOS)

Read this first before doing anything else.

## What this project is

A native Swift/AppKit menu-bar app (Swift Package, no `.xcodeproj` needed —
open `Package.swift` directly in Xcode, or just use `swift build`/`swift
run`). It replaces an earlier Electron prototype of the same idea: an
ambient desktop companion that's invisible almost all the time and, every
45–90 minutes (randomized), has a butterfly flutter in from a random edge of
a random monitor, show a short kind message near that edge, wait ~10s, then
fly back out.

**The one rule that matters more than any feature: it must never be
distracting.** Concretely:
- Never steals focus or keyboard input (overlay windows override
  `canBecomeKey`/`canBecomeMain` to `false`, and are never sent
  `makeKeyAndOrderFront`).
- Fully click-through (`ignoresMouseEvents = true` on every overlay window)
  — nothing it renders should ever block a click meant for the app
  underneath.
- Never appears in the Dock, Cmd-Tab, or Mission Control app switcher
  (`NSApp.setActivationPolicy(.accessory)`).
- Stays near screen edges, never the center.
- Respects quiet hours (default 11pm–7am, configurable from the menu).
- Any new feature has to be justified against this rule before it gets
  added.

## Current status (as of this handoff)

The whole thing was written and syntax-reviewed in a Linux sandbox with no
Swift toolchain or macOS available — **it has not been built or run yet.**
First real build (`swift run`, or Xcode ⌘R) on an actual Mac is the first
real test. Likely rough spots to check first: window layering/click-through
actually behaving as expected across Spaces and full-screen apps, the
flight path/wobble looking natural rather than glitchy, and the bezier
butterfly shape rendering the way it's meant to (it's hand-authored curve
data, never visually verified).

## Architecture

- `Package.swift` — SPM manifest, macOS 13+ target, single executable
  target `LilButterfly`.
- `Sources/LilButterfly/main.swift` — entry point. Sets `.accessory`
  activation policy (no Dock icon) and calls `NSApplication.run()`.
- `AppDelegate.swift` — owns the `NSStatusItem` (🦋 menu bar icon) and its
  `NSMenu` (show now / pause-resume / frequency presets / quiet hours
  toggle / quit), the loaded `Config`, and a `Timer`-based scheduler that
  picks a random delay and asks a random screen's `ScreenOverlay` to run a
  visit. Rebuilds overlays on
  `NSApplication.didChangeScreenParametersNotification` (display
  connect/disconnect).
- `OverlayWindow.swift` — one borderless, transparent, `.screenSaver`-level,
  click-through `NSWindow` per screen. `collectionBehavior` includes
  `.canJoinAllSpaces`, `.stationary`, `.ignoresCycle`,
  `.fullScreenAuxiliary` so it stays visible across Spaces/full-screen apps
  without being cycled through like a normal window.
- `ScreenOverlay.swift` — orchestrates one full "visit" on its screen: picks
  a random edge (`left`/`right`/`top`/`bottom`), computes a rest point near
  that edge and an off-screen entry point, and sequences fly-in → position
  + fade in the message bubble → wait ~9s → fade out bubble → fly-out →
  remove views. Tracks `isBusy` so a screen already mid-visit isn't picked
  again.
- `ButterflyView.swift` — the visual. Two `CAShapeLayer` wings (hand-authored
  bezier paths) with an infinite looping flutter animation
  (`transform.scale.x`, slightly phase-offset between wings), plus
  `flyPath(from:to:duration:easeIn:completion:)` which builds a
  `CGMutablePath` with a perpendicular sine "wobble" added to a straight
  eased line, and animates the layer's `position` along it via
  `CAKeyframeAnimation` (setting the final model `position` up front so
  there's no snap-back when the animation is removed).
- `BubbleView.swift` — small rounded message bubble, sizes itself to its
  text, simple alpha fade in/out via `NSAnimationContext`.
- `Config.swift` — `Codable` struct (min/max minutes, quiet hours,
  paused, messages) with a `ConfigStore` that persists it as JSON under
  `~/Library/Application Support/LilButterfly/config.json`.
- `scripts/make_app_bundle.sh` — optional packaging: builds a release
  binary and wraps it into a minimal `LilButterfly.app` with `LSUIElement`
  set, for dragging into `/Applications`.

No backend or telemetry. The only network call is the optional public GitHub
Releases update check; there are no analytics calls.

## Your first task

1. Check if this directory is already a git repo (`git status`). If not,
   `git init`.
2. Add a `.gitignore` covering `.build/`, `.swiftpm/`, and `LilButterfly.app`
   if one doesn't already exist.
3. Stage and commit everything as the initial commit.
4. Create a GitHub repo using the `gh` CLI (assume the user is already
   authenticated — if `gh auth status` fails, stop and tell the user to run
   `gh auth login` first rather than asking for a token in chat). Ask the
   user whether they want it public or private, and what name to use
   (`lil-butterfly-mac` is a reasonable default) before creating it.
5. Push the initial commit to the new repo's default branch.
6. Confirm the remote URL back to the user.
7. Then: actually try `swift build` and `swift run` and fix whatever the
   first real compile turns up — this code has never been compiled.

After that, treat this as an ordinary iterative project developed together
in the repo.

## Conventions / preferences

- Keep it dependency-free. No third-party Swift packages needed for
  something this small — pure AppKit/Core Animation is intentional.
- Don't add analytics or telemetry. The optional GitHub Releases request is
  reserved for update metadata and must not become a general data channel.
- If you add configurable behavior, wire it into both the menu and
  `Config`, not just one.
- Prefer small, testable changes — this is easy to visually verify by
  running the app and using "Show a butterfly now" from the menu, so lean
  on that for feedback loops rather than guessing at timing/animation
  values.
- There is an earlier Electron version of this same idea (different repo/
  history) — this native version is the one going forward; no need to keep
  them in sync.

## Known rough edges / good next steps

- Butterfly wing shapes are hand-authored bezier curves, never visually
  verified — check they actually look like a butterfly and adjust the
  control points if not.
- No global keyboard shortcut yet for an on-demand "I need a break" trigger.
- No in-app settings window — menu-bar-item and manual config-file edits
  only, for now.
- No auto-launch-at-login wiring yet (could add a small helper LoginItem, or
  just document the manual Login Items step, which the README currently
  does).
- Multi-monitor behavior (one overlay window per screen, rebuilt on
  display changes) is implemented but untested on an actual multi-monitor
  setup.

See `README.md` for user-facing setup/run/packaging instructions.
