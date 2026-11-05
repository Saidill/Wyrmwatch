# Design review

6 November 2026. Screenshots come from `--selftest`, on the real notch and on the virtual notch. The self-test feeds made-up Claude sessions (idle, working, waiting), a made-up song, and a running and a stopped timer, then saves each tab and state as a picture. Each round below checks those pictures against the rules in the PRD ("Maskot dan tema"):

- 5 text sizes (11, 13, 16, 28, 38), regular and semibold only;
- a 4 pt grid;
- grayscale for hierarchy, red only for signals;
- one main element per screen, left-aligned;
- no gradients, glow, emoji, colourful icons, heavy glass or shadows, decorative text or filler;
- a reason for every animation.

The bar is the polish of Perch/Alcove, Things 3 and Linear: their quality, not their look.

## Round 1

| # | Where | Problem | Rule | Fix |
|---|-------|---------|------|-----|
| 1 | Claude tab, Now | A session that is **waiting** for you showed a check mark and "Done · folder". | Correctness | Waiting sessions show "?" and "Waiting for you · 1:31". |
| 2 | Home, Claude card | "Claude · session" was cut off ("Claude · sess…") next to the status chip. | Hierarchy | The label is just "Claude"; the big number already says it's the session limit. |
| 3 | Home, Claude card (waiting) | The status line said "Waiting for you", repeating the "waiting" chip, and pushed the reset time off the card. | Filler | The line names the project instead ("thesis · resets in 3h 29m"). |
| 4 | Header, all tabs | The pill on the right ("Home", "Claude") repeated the tab that was already lit. | Filler | Removed; only the clock stays. |
| 5 | Claude tab, sections | "SESSIONS", "PLAN LIMITS": capitals with letter spacing, a decorative style no other label used. | Decorative text | `SectionTitle`: a plain 11 pt label. (Settings keeps `CardTitle`.) |
| 6 | Focus, Timer setup | The time card showed 25:00, the Pomodoro length, while the Timer was set to 1:30:00. | Correctness | Before it starts, the card shows the Timer's own length. |
| 7 | Everywhere | 18 different text sizes (9 to 15 pt, plus 46) and medium, light and bold weights. | Type scale | Only 11/13/16/28/38 and regular/semibold remain in the notch and the popover. |
| 8 | Everywhere | Gaps of 3, 5, 6, 7, 10 pt, buttons 26/30/34 pt high, cards 118 and 150 pt. | 4 pt grid | Moved to the nearest multiple of 4 (gaps 4/8, buttons 28/32, cards 120/152). |

## Round 2

| # | Where | Problem | Rule | Fix |
|---|-------|---------|------|-----|
| 9 | Menu bar popover | The title was a greeting by time of day ("Late night coding", "Good morning"). | Decorative text | The title is "Claude", and the line under it states what's running ("1 session working", "1 waiting for you"). |
| 10 | Limit bars | A sweeping highlight (shimmer) was still in the code, a second light effect next to the Ember Edge. It wasn't drawn any more. | One light effect | Removed. |
| 11 | Notification | "Back to full speed ✨". | No emoji | "You can use Claude at full speed again." |
| 12 | Sessions card | "All caught up". | Decorative text | "Nothing working". |
| 13 | Mascot | The head sprang back to straight on every first update, even with Reduce Motion on (the self-test caught a "look" animation). | Every animation has a reason | Without a pointer to follow, the head just sits still; no spring. |

## Round 3

Every tab on the real and the virtual notch, the live notch, the pops and the menu bar popover:

- Grayscale throughout. Red only on the Ember Edge, the working dot and usage of 90% or more.
- One main number per card: 38 pt on Home and Focus, 28 pt on the Claude tab.
- Left-aligned, with steady digits everywhere a number changes.
- The self-test reports no overlaps on any tab.

Left as they are, with the reason:

- **Presets stay visible while a timer runs.** Clicking one starts that preset over. That's one click to change plans, and hiding them would make the page jump. Needs a manual check.
- **The mascot in the header sits under the camera on a real notch.** It's visible on the virtual notch and on the left of the live notch, where it matters most.
- **The Claude tab has three equal number cards.** Session, the leftmost one, reads first because it's on the left. Making it bigger would break the even row the other tabs use.

## Motion, and why each one exists

| Motion | Why |
|--------|-----|
| Notch opens and closes (`Motion.open` / `close`) | Shows where the panel comes from and goes back to. |
| Ember Edge: an ember moving along a red edge / a slow white pulse | Claude working or waiting can be seen from the corner of the eye. |
| Wyrm: blinks, nods while working, turns to the pointer, jaw and fire on done | The same status, without text; the fire marks the one moment worth celebrating. |
| Scale bar: scales light one by one (20 ms) | A change in progress reads as a count, not a jump. |
| Cards come in 30 ms apart | Shows the reading order. |
| Digits roll (`numericText`) | A changing number stays readable while it changes. |
| Live notch takes turns (6 s) | More than one module to show in a small space. |
| Time and task name take turns (4 s), without a fade | The name fits only by taking the time's place. A fade here cost about 1% CPU (measured), so the swap is instant. |

Every repeating motion stops when the notch is closed (the self-test checks that no layer is animating), and none runs with Reduce Motion on.
