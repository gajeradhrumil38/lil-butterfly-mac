# Interactive check-in — design spec

## Purpose

Occasionally, instead of a plain kind message, the butterfly's visit becomes a
short interactive moment — pick an emoji, drag a slider, tap a color, watch a
breathing circle — that reflects something back rather than just delivering a
line of text. Each pick is quietly logged locally (no viewer yet) so a future
history feature has real data to work with.

This is additive to the existing visit system, not a replacement: the vast
majority of visits stay exactly as they are today (a single kind message).

## Frequency and integration

Folded into `AppDelegate.fireVisit()`, the same way the update reminder is:
not a separate, extra interruption, just an occasional variant of a visit
that was going to happen anyway (scheduled or manual "Show Butterfly").

- Roughly 1 in 10–15 visits becomes a check-in instead of a plain message —
  rare enough to feel like a nice surprise, not a routine.
- Same guards as every other visit apply unchanged: `config.paused`, quiet
  hours (gentle-mode), meeting suppression. A check-in is never shown when a
  plain message wouldn't have been.
- The update reminder still takes priority when both are pending — it's
  guaranteed-once-per-version and functional; a check-in is discretionary and
  can simply wait for the next eligible visit.
- Docked and roaming mode both support check-ins, reusing each overlay's
  existing visit lifecycle (arrival, resting/hold, departure).

## The seven styles

One is picked at random each time a check-in fires — variety prevents any
single style from feeling like "a feature" rather than a moment.

1. **Mood picker** — 5 emoji spanning the Mood Meter's energy×pleasantness
   quadrants: 😄 happy, 😌 calm, 😐 neutral, 😩 stressed, 😔 down. Each has its
   own pool of 3–4 validation-style replies (acknowledge the feeling as
   legitimate, don't rush to fix it — e.g. for stressed: *"That sounds like a
   lot right now — it's okay to feel stretched thin."*).
2. **Energy slider** — draggable, 5-stage emoji morph (😴 🥱 🙂 😄 ⚡) with a
   color-fill track, live-updating as it's dragged. Multiple question
   phrasings ("How's your energy right now?" / "Where's your battery at?"),
   2–3 reply variants per stage.
3. **Smile prompt** — several different playful prompts ("Smile for me? 🦋" /
   "Bet I can get a smile out of you") with a single confirm button, varied
   button text ("Okay, smiled 😊" / "Did it 😄").
4. **Favorite color hearts** — 7 colored hearts, each mapped to a hard-work /
   success quote theme (❤️ drive, 🧡 ambition, 💛 momentum, 💚 growth, 💙
   discipline, 💜 vision, 🤍 clarity), 4+ quotes per color. Selection feedback
   is a plain scale-up zoom on the tapped heart — nothing else changes.
5. **Breathe with me** — zero-tap. A small circle expands/contracts once
   through "Breathe in... breathe out..." (~10s total), and the butterfly's
   own wing-flutter visibly slows to match for that duration, then returns to
   normal. The only style requiring no decision from the user at all.
6. **Gratitude tap** — "One good thing about today?" shows a random 5 of a
   12-item pool, deliberately tilted toward rest/connection (talked with
   family, a little nap, a good book, a quiet moment, early night ahead)
   alongside a couple of work-flavored ones (progress) — so celebrating a
   break feels as valid as celebrating output. Tapped chip turns accent blue
   and scales up slightly; reply acknowledges the specific pick.
7. **Pick-a-word** — a small set of specific mood words (e.g. "Focused",
   "Overwhelmed", "Hopeful", "Content", "Restless") rather than emoji — closer
   to the actual Mood Meter's granularity, since "overwhelmed" and "tired"
   should get different replies.

All reply/quote/word content is hand-written and stored locally (large pools,
same pattern as `Config.default`'s existing message pools) — no network
calls, no API, works fully offline.

## Technical architecture

### The core problem to avoid

The update-reminder feature hit a real bug: an invisible full-card tap
window and the corner close button both existed as separate `NSPanel`s, and
because the invisible one drew nothing, there was no way to be sure clicks
landed where intended, and an earlier version of it visibly duplicated the
close mark. The fix that worked was: **one small window both draws its own
visible control and handles its own click** — never separate "what's shown"
from "what's clickable" into two different layers.

This spec generalizes that fix into one reusable mechanism instead of
special-casing it per style, which is the actual guard against style-errors /
z-order bugs recurring as more interactive styles are added.

### `ChoiceButtonWindow`

Replaces the one-off `UpdateActionButtonWindow` with a general small
`NSPanel` that draws exactly one visible control (an emoji, a color heart, a
text chip, a word) sized to its own frame and reports taps via a closure —
identical shape to `BubbleCloseWindow`, just parameterized on content instead
of always being an xmark. `UpdateActionButtonWindow`'s "Update Now" button
becomes one configuration of this same class, not a separate type.

### `BubbleView` extension

`BubbleView` gains a `checkIn: CheckInContent?` init parameter (an enum
covering the 7 styles' static content — question text, choice count, layout
hints). When present, exactly like `actionTitle` already does for the update
button, it reserves extra height at the bottom of the card's own rounded-rect
layout for a **choice row**. `BubbleView` exposes
`choiceFrame(at index:) -> CGRect` (local coordinates), the same pattern as
`closeTargetFrame`/`actionButtonFrame` today.

Two layout modes, both computed once at init time from real content (same
principle as the card's own width/height already being measured from the
actual message text, not assumed):
- **Fixed grid** (mood picker's 5 emoji, color hearts' 7 hearts): N
  equal-width slots spanning the card's content width. 7 is the largest N in
  the roster, so the card's minimum width must comfortably fit 7 slots at a
  legible emoji size — if that pushes the card wider than today's 280pt
  ceiling, the ceiling moves up for check-in cards specifically, since plain
  messages are unaffected.
- **Flow-wrapped chips** (gratitude's 5-of-12 picks, pick-a-word's list):
  variable per-chip width based on each label's actual measured text width,
  wrapping to a second line if the row doesn't fit — same `boundingRect`
  measurement technique `BubbleView` already uses for its own text.

The energy slider is the one exception needing a live-updating control
rather than N discrete choices — it gets its own small interactive window
(a real `NSSlider`-backed panel, same "draws and handles itself" shape) sized
to a reserved horizontal strip instead of a row of N choice slots.

The breathing style needs no `ChoiceButtonWindow` at all — it's pure
animation inside the existing bubble content plus a new
`ButterflyView.setFlutterRate(_:)` call the check-in overlay invokes and then
reverts, no new window type.

### `CheckInOverlay`

A new type parallel to how `ScreenOverlay`/`DockedOverlay` already run a
visit, but reusing their exact arrival/hold/departure choreography rather
than duplicating it — concretely, `ScreenOverlay.visit(...)` and
`DockedOverlay.visit(...)` gain a `checkIn: CheckInContent?` parameter
alongside the existing `actionTitle`/`onTapped`, and construct N
`ChoiceButtonWindow`s (or the slider window, or nothing for breathing)
instead of one `UpdateActionButtonWindow`, following the identical
create-after-bubble-fades-in / reposition-on-move / clean-up-in-leaveNow
lifecycle already proven correct for the update button and close window.

Reply-reveal reuses `BubbleView`'s existing typing-dots-then-text mechanism:
on a tap, the chosen reply string swaps in with the same cross-fade already
used for the initial message.

### Local logging

A new `CheckInStore`, structurally identical to `ConfigStore` (JSON, atomic
writes, same Application Support directory), writing to `checkins.json`:

```json
{ "entries": [
  { "date": "2026-09-16T14:32:00Z", "style": "moodPicker", "choice": "stressed" },
  { "date": "2026-09-16T09:10:00Z", "style": "energySlider", "choice": "72" }
] }
```

Appended after every completed pick (not on dismiss-without-choosing).
Capped at a reasonable count (e.g. last 500 entries) so the file can't grow
unbounded with no viewer ever trimming it.

## Testing approach

Each style gets a manual `swift run` trigger path (temporarily forcing
`fireVisit` to pick a specific style, same technique used to test the update
reminder and welcome overlay), verified for: correct layout (card tall/wide
enough, no clipped content), correct click routing (each `ChoiceButtonWindow`
fires only its own choice, corner close still works and still wins in any
overlap), and a full arrival→pick→reply→departure cycle with no crash, in
both roaming and docked mode. The breathing style is verified by watching the
wing-flutter rate actually change and revert.
