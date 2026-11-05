# Wyrmwatch

**Guarding your focus, your music, and your AI agents, right from the notch.**

Wyrmwatch is a macOS notch app: a Pomodoro and countdown timer, Apple Music, and your Claude Code sessions and usage limits, all in the camera notch.

## In the notch

Hover the notch (or click it) to open it. The header is split by the camera: four small tabs on the left (Home, Focus, Music, Claude), the active tab's name and the time on the right, and in between, where the camera sits, a slot for the Wyrmwatch mascot (coming soon). The notch grows to fit each tab. Right-click the notch for **Settings** and **Quit**.

- **Home**: three cards of the same height, one big number each.
  - **Claude**: your session limit, whether Claude is working (a slowly pulsing red dot) or waiting for you, and what it is doing right now ("Editing HomePage.swift"), with when the limit resets.
  - **Music**: the cover, title and artist, progress, and previous / play-pause / next. Nothing playing? A **Play music** button.
  - **Focus**: the time left with pause and stop, or the 25/5 and 50/10 presets when no timer runs.
- **Focus**: Pomodoro or Countdown, with presets 25/5, 50/10, 90/15, 05:00 and 15:00, or your own lengths. It keeps time through sleep and restarts, starts each break by itself and plays a short alarm when a phase ends.
- **Music**: a large cover, the song with its progress and controls (shuffle, previous, play-pause, next, repeat), and the library playlist being played. Click a song to play it.
- **Claude**: session limit, week limit and sessions running as big numbers, then Now (running sessions, click to jump to their terminal), Recent (click to resume) and Usage (tokens).

When it's closed, the notch shows what matters in a slim "live" strip: Claude's status dot while it works or waits, the cover and a visualizer while music plays, the time left with a small ring during a Pomodoro (taking turns with the music every 6 seconds). Short cards drop out of it when a Claude session finishes, a timer ends or the song changes.

On a screen without a notch (an external monitor), the app draws one: a small black pill at the top that opens the same way. Display modes are Auto, Notch, Menu bar and All screens. In Menu bar mode the app lives in a popover under a menu bar icon instead.

The look is black with #1C1C1E cards and silver progress. The only colour is red (#E5322B): Claude working, and usage above 90%. Repeating animations run in Core Animation, so the app does no work per frame. Nothing animates unless it's on screen, and Reduce Motion (or Settings → System → Always reduce motion) turns all repeating animation off.

## Claude in the background

- **A sound when Claude finishes**, plus a notification, so you can look away while it works.
- **Limit alerts**: a heads-up when your session or weekly limit passes 80% (adjustable), and a ping the moment your session limit resets.
- **Limit forecast**: where you're heading at your current pace ("At this pace, full at 15.40"), from the last 30 minutes.

## Requirements

- macOS 14 or later (built and tested on an M2 MacBook)
- [Claude Code](https://claude.com/claude-code), logged in with a Claude subscription
- Xcode Command Line Tools (`xcode-select --install`)

## Install

```bash
git clone https://github.com/Saidill/Wyrmwatch.git
cd Wyrmwatch
./scripts/build-app.sh
cp -R Wyrmwatch.app /Applications/
open /Applications/Wyrmwatch.app
```

Then click the ring in the menu bar → ⚙ → turn on **Open at login**. From then on it starts by itself.

If you change the code later, run `./scripts/build-app.sh --install`. It rebuilds the app, replaces the copy in `/Applications` and relaunches it.

While you're working on it, run `./scripts/dev.sh` and leave it open: every time you save a file in `Sources/`, the app rebuilds and relaunches by itself, so you never have to quit and reopen it.

To check that everything still works after a change, run the self-test. It switches between the menu bar and the notch, opens every tab on the real and on a virtual notch, checks that no view overlaps another and that the notch follows each tab's height, runs the Pomodoro, Music and Info modules on made-up data, and saves a picture of every screen plus a `report.txt` to the folder you give it:

```bash
./scripts/build-app.sh && ./Wyrmwatch.app/Contents/MacOS/Wyrmwatch --selftest /tmp/wyrmwatch-test
```

## How it works

Everything is read from files Claude Code already writes on your Mac, and from Music.app. Nothing is sent anywhere, apart from one request for your Claude plan limits.

| What | Where it comes from |
| --- | --- |
| Sessions and the finish sound | `~/.claude/sessions/*.json`. Each running session has a `status`, and a change from `busy` to anything else means Claude finished. Checked every second. |
| Token counts | `~/.claude/projects/**/*.jsonl` transcripts. Only new lines are read, every 2 seconds. |
| Plan limits and alerts | `GET https://api.anthropic.com/api/oauth/usage`, using the login token Claude Code keeps in your Keychain. Refreshed every minute and when you open the popover. When the token expires (after about 8 hours without Claude Code running), the app renews it and saves it back, so Claude Code stays logged in. |
| Recent sessions | The newest transcripts in `~/.claude/projects`. Only the last 64 KB of each file is read, for its title and folder. |
| Jump to session | Finds the app that owns the session's process. For Terminal and iTerm2 it selects the tab by its TTY using AppleScript; macOS asks once for permission. |
| Music | Song changes and play/pause come from the system notification Music posts (`com.apple.Music.playerInfo`). The cover, position, playlist, favourite and controls use AppleScript, never while Music is closed; macOS asks once for permission. Radio and catalog songs outside your library have no readable playlist. |
| Next calendar event | EventKit, after you allow calendar access. Refused? It simply doesn't show. |

The plan-limits endpoint is **unofficial**: it's the same one Claude Code's `/usage` command uses, and Anthropic may change it. If it stops working, the app says so and everything else keeps working.

The Session and Week limits are shared, so they include your chats on claude.ai and in the Claude desktop app. Token counts cover Claude Code only, because chats aren't saved on your Mac.

## Project layout

```
Sources/Wyrmwatch/
  App/            entry point, display modes, menu bar icon, self-test, --diagnose, --perf, --render-icon
  Core/           NotchModule protocol, module registry, priority resolver, pop queue, layout probe
  Notch/          notch window and shape, virtual notch, open panel (header, tabs, Home page)
  Modules/
    Claude/       sessions, usage, plan limits, notifications, jump/resume
    Pomodoro/     timer, Focus page, fuse and dots
    Music/        Music.app bridge, artwork cache, Music page, playlist
    Info/         next calendar event
  Views/          design tokens and motion, the mascot slot (WyrmSlot), shared controls, popover, settings
scripts/
  build-app.sh    builds Wyrmwatch.app (with the Rive runtime and app icon); --install puts it in /Applications
  measure-perf.sh CPU and memory per notch state
  dev.sh          rebuild and relaunch on every save
```

## Development

```bash
swift build                 # compile
./scripts/build-app.sh      # build the .app bundle
```

No Xcode project is needed. It's a plain Swift package.

## The mascot

The mascot slot plays `Resources/wyrm.riv` with [Rive](https://rive.app) (`RiveRuntime`, about 14 MB in the app) when that file is present, and shows nothing otherwise. Its state machine gets one boolean input per state (`hidden`, `peek`, `working`, `alert`, `done`, `sleep`) and the numbers `lookX` / `lookY` for where the pointer is.
