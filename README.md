# Claude Usage (becoming Notchwyrm)

A macOS notch app for focused work: Claude Code usage, a Pomodoro timer, Apple Music and your next calendar event, all in the camera notch. A red dragon keeps watch. It is being renamed to **Notchwyrm**; until then the app is still called `ClaudeUsage`.

## In the notch

Hover the notch (or click it) to open it. The header is split by the camera: the dragon with the date and time on the left, five tabs on the right (Home, Focus, Music, Claude, Settings). The notch grows to fit each tab.

- **Home**: one row with everything. The album cover with a soft glow, the song with a visualizer, a seek bar and the controls (playlist, previous, play/pause, next, favourite). To the right: the Pomodoro (time left, pause, stop, or the 25/5 · 50/10 · Set up chips when it isn't running) and your Claude session limit. No music playing? There's a **Play music** button instead.
- **Focus**: start a Pomodoro with a preset (Classic 25/5, Deep 50/10) or your own lengths, the number of sessions (1–8) and an optional task. While it runs: big digits, "Focus 2/4 · your task", a dial-like tick scale, +5 min, pause, skip and stop. It keeps time through sleep and restarts.
- **Music**: the cover and the playlist being played. Click a song to play it.
- **Claude**: session and week limits with the forecast, then Now (running sessions, click to jump to their terminal), Recent (click to resume) and Usage (tokens).
- **Settings**: display mode, modules, Pomodoro, Music, Claude alerts and system options.

When it's closed, the notch shows what matters in a slim "live" strip: the small dragon while Claude works, the cover and a visualizer while music plays, the time left with a small ring during a Pomodoro (taking turns with the music every 6 seconds). Short cards drop out of it when a Claude session finishes, a Pomodoro phase ends or the song changes.

On a screen without a notch (an external monitor), the app draws one: a small black pill at the top that opens the same way. Display modes are Auto, Notch, Menu bar and All screens. In Menu bar mode the app lives in a popover under a menu bar icon instead.

The look is plain black with silver accents. Red is only for the dragon, and amber or rose only for usage warnings. Repeating animations (the dragon, the visualizer) run in Core Animation, so the app does no work per frame: about 0.2% CPU closed or live and under 2% open on an M-series Mac (`scripts/measure-perf.sh`). Nothing animates unless it's on screen, and Reduce Motion (or Settings → System → Always reduce motion) turns all repeating animation off.

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
git clone https://github.com/<your-username>/claude-usage-ui.git
cd claude-usage-ui
./scripts/build-app.sh
cp -R ClaudeUsage.app /Applications/
open /Applications/ClaudeUsage.app
```

Then click the ring in the menu bar → ⚙ → turn on **Open at login**. From then on it starts by itself.

If you change the code later, run `./scripts/build-app.sh --install`. It rebuilds the app, replaces the copy in `/Applications` and relaunches it.

While you're working on it, run `./scripts/dev.sh` and leave it open: every time you save a file in `Sources/`, the app rebuilds and relaunches by itself, so you never have to quit and reopen it.

To check that everything still works after a change, run the self-test. It switches between the menu bar and the notch, opens every tab on the real and on a virtual notch, checks that no view overlaps another and that the notch follows each tab's height, runs the Pomodoro, Music and Info modules on made-up data, and saves a picture of every screen plus a `report.txt` to the folder you give it:

```bash
./scripts/build-app.sh && ./ClaudeUsage.app/Contents/MacOS/ClaudeUsage --selftest /tmp/claude-usage-test
```

## How it works

Everything is read from files Claude Code already writes on your Mac. Nothing is sent anywhere, apart from one request for your plan limits.

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
Sources/ClaudeUsage/
  App/            entry point, display modes, menu bar icon, self-test, --diagnose, --perf, --render-icon
  Core/           NotchModule protocol, module registry, priority resolver, pop queue, layout probe
  Notch/          notch window and shape, virtual notch, open panel (header, tabs, Home page)
  Modules/
    Claude/       sessions, usage, plan limits, notifications, jump/resume
    Pomodoro/     timer, Focus page, fuse and dots
    Music/        Music.app bridge, artwork cache, Music page, playlist
    Info/         next calendar event
  Views/          theme and motion, the dragon, shared controls, popover, settings
scripts/
  build-app.sh    builds ClaudeUsage.app (and the dragon app icon); --install puts it in /Applications
  measure-perf.sh CPU and memory per notch state
  dev.sh          rebuild and relaunch on every save
```

## Development

```bash
swift build                 # compile
./scripts/build-app.sh      # build the .app bundle
```

No Xcode project is needed. It's a plain Swift package.

## Credits

The dragon is [Spiked dragon head](https://game-icons.net/1x1/delapouite/spiked-dragon-head.html) by Delapouite, from [game-icons.net](https://game-icons.net), licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). It is tinted red and animated in the app.
