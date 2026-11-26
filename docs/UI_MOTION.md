# Brow: motion and UI/UX ideas

Brainstorm from a Claude (Cowork) session on 26 Nov 2026, after reading the code at commit `3db5bd1`.
Line numbers refer to that commit. See "Status" below for what has been built since.

## Status (26 Nov 2026)

Built, with the pull request that brought each in:

- Findings 1–3 (headroom for the overshoot, `Spring.settlingDuration` for the shrink delay, one spring per gesture): #2.
- Reduce Motion (finding 7, step 3): #4. A 0.15 s fade replaces the spring, and screens cross-fade.
- Close grace (finding 4): #5, 280 ms, cancelled when the pointer comes back.
- Content that follows the shape (finding 5): #6. It arrives 70 ms late, from 0.94 scale and a 6 pt blur, and leaves in
  120 ms.
- Button press and hover feedback, the play/pause symbol replace and glyph scale transitions (part of step 5): #7.

Tried and removed: **`numericText` on the countdowns.** The "Performance" section below says it animates once a
second and is acceptable. Measured on a notched MacBook with a pomodoro running, it is not: CPU went from 0.2–1% to
15–17% with the time beside the notch, and from 0.3–0.6% to 23–37% with the island open. Limiting it to the open
island did not help. It is out until a cheaper way is found (for example a single cross-fade of the whole time, not
per-digit rolling).

Not built: the interactive swipe and shared-card morph (step 4), card stagger, the click-mode hover lift, scroll to
open, haptics, the launch hello, the peek's extra bounce, the slide-down on a screen without a notch, and the
blur-replace of the right-hand time.

## What the code does today

- `IslandController`: one `NSPanel` whose frame is the island. The `NSHostingView` is a fixed size (the largest
  island), pinned top-centre, so a resize never moves the drawing. The panel grows at once and shrinks after
  `openDuration + 0.1` s (`layout()`, L201–224). Hover opens after 120 ms; leaving closes at once (L96–118).
  Swipes go through `SwipeTracker`: one step after 36 pt, no tracking of the fingers (L165–184).
- `IslandView`: two animations on the root, `.spring(0.35, bounce 0.15)` on `mode` and `.spring(0.35)` on `size`
  (L50–51). Content swaps with `.transition(.opacity)`. `IslandShape` already animates shoulder and bottom radius.
  Screens use `.push(from:)` with their own `.spring(duration: 0.3)` (L181, L204).
- `Cards`: press state is opacity only (`PillButtonStyle`, `IconButtonStyle`); no hover state; numbers and symbols
  change without transitions.

The foundation is already right (fixed host, grow-then-shrink panel, animatable shape). The work is in tuning.

## Findings: why it may not feel smooth yet

1. **The bounce is clipped.** The panel grows to exactly the target size and the host is exactly the largest
   island, so a spring that overshoots draws outside the window: the bottom corners flatten at the peak of the
   open. Give both 16–24 pt of headroom (host = largest + margin; panel = target + margin while animating, then
   exact). The margin takes clicks only for those ~0.5 s.
2. **Three different springs.** mode (bounce 0.15), size (no bounce) and screen push (0.3 s) run together, so on a
   screen switch the cards settle before the island's height does. Use one spring per gesture.
3. **Shrink timer is a guess.** 0.45 s against a spring whose tail lasts longer. Use
   `Spring(duration:bounce:).settlingDuration` for the delay.
4. **Close is immediate.** Leaving the frame by one pixel shuts the island. Add a 250–300 ms grace (cancel on
   re-enter). Already on the STATUS improvement list.
5. **Content appears with the mask.** The open content is laid out at its final size and revealed by the growing
   clip while it fades, which reads as a wipe. Better: shape leads, content follows.
6. **Swipe is a trigger, not a gesture.** Nothing moves until 36 pt, then the screen jumps.
7. **No Reduce Motion.**

## Ideas, by area

### Opening and closing

- Separate springs: open `.spring(duration: 0.4, bounce: 0.2)`, close `.spring(duration: 0.3, bounce: 0)` (a
  bouncing close makes the wings overshoot past the notch).
- Content in: `scale 0.94 → 1` anchored `.top`, opacity, `blur 6 → 0`, about 60–80 ms after the shape starts.
  Content out: opacity + slight scale-down, 120 ms, before the shape shrinks. Use an asymmetric transition.
- Card stagger: 25–35 ms per card on open only.
- In click-to-open mode, a small hover "lift" (+8 pt wide, +2 pt tall) signals the island is clickable.
- Two-finger scroll down on the closed island opens it, scroll up closes it (the scroll monitor is already there;
  today it returns early unless open).
- Haptic: `NSHapticFeedbackManager` / `.sensoryFeedback(.alignment)` only plays while a finger is on the
  trackpad, so it fits a swipe commit well and hover-open only sometimes.

### Switching screens

- Interactive: extend `SwipeTracker` to report progress (−1…1). Offset the current screen with the fingers,
  rubber-band at the ends, commit on distance or flick velocity at `.ended`, otherwise spring back. Keep it in
  `BrowCore` with tests.
- Shared cards morph: Calendar is on all three default screens (wide → half → quarter). A `@Namespace` with
  `matchedGeometryEffect(id: widget)` lets it resize in place while only new cards fade in.
- Island height and content on the same spring; haptic `.alignment` on commit.
- Page dots already stretch; move the white pill with `matchedGeometryEffect` so it slides between dots.

### Beside the notch (compact) and peeks

- Each glyph: `.transition(.scale(0.5).combined(with: .opacity))`; right-side text: blur-replace when it changes
  from event to pomodoro to Keep Awake.
- `contentTransition(.numericText(countsDown: true))` on `Countdown`, `EventCountdown`, `KeepAwakeRemaining`.
- "Now": one `.symbolEffect(.bounce)` on the calendar glyph.
- Peek: slightly more bounce than open (it's a notification), and content slides down 6 pt as it fades in.
- On screens without a notch: slide down from above the top edge instead of fading (`opacity` at L46).

### Cards and controls

- Buttons: scale 0.96 on press with `.snappy(0.18)`, hover highlight (`onHover`, brighten fill 8%).
- Play/pause: `.contentTransition(.symbolEffect(.replace))`.
- Keep Awake presets: selected fill slides between pills with `matchedGeometryEffect`.
- Phase change: tint cross-fades amber ↔ teal; usage bars animate from old to new value.

### Launch

- Brow has no Dock or menu bar icon, so launching gives no sign it worked. A one-time hello peek (date or
  "Brow is running", 1.5 s) on launch and after login, with a setting to turn it off.

## Performance (keep "idle means idle")

- Animations run only on state changes. Measure anything that animates every second: `numericText` on the 1 s
  countdown was tried and cost 15–37% CPU (see Status).
- Don't add continuous animations (pulsing dots, shimmer) to the closed state.
- Check on a 120 Hz ProMotion display.

## Suggested order

1. Headroom for the overshoot + `settlingDuration` + one spring per gesture (findings 1–3). Small, biggest win.
2. Close grace and the asymmetric content transition (findings 4–5).
3. Reduce Motion.
4. Interactive swipe + matched cards.
5. Numeric text, symbol effects, button press/hover, glyph transitions.
6. Launch hello, scroll-to-open, haptics.

## References

- Apple HIG, Motion: https://developer.apple.com/design/human-interface-guidelines/motion
- WWDC23 "Animate with springs": https://developer.apple.com/videos/play/wwdc2023/10158
- SwiftUI `Spring` (settlingDuration): https://developer.apple.com/documentation/swiftui/spring
- Haptics need a finger on the trackpad: https://developer.apple.com/forums/thread/70605
- boring.notch: https://github.com/TheBoredTeam/boring.notch
