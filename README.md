# Pomodoraaa

A small, floating pomodoro widget for macOS. It stays on top of every app and every Space (full-screen apps too), you can drag it anywhere, and it plays built-in focus music right inside the app.

Designed as a clean, minimal **glass** widget, with 12 templates inspired by modern widget sets.

## Features

- **Floats above everything.** The widget never steals focus from what you're working on. Drag it anywhere; it remembers where you left it.
- **Edit time:** focus, short break, long break and rounds, plus 25/5, 50/10 and 90/20 presets and auto-start.
- **Focus music:** six built-in tracks (Lofi Study, Piano Drift, Deep Focus, Rain, Ocean and Brown Noise). They're generated live inside the app, so they need no internet, no account and no other app, and they never run out or repeat exactly.
  - Music follows the timer: it plays during focus, pauses when you pause, and can pause on breaks. Switching tracks crossfades.
- **Templates:** Liquid Glass (default), the glowing Bloom, Aurora, Neon and Ultraviolet, plus Ember, Forest, Tide, Sunny, Paper, Pixel and Midnight. Glass tint is adjustable.
- **Ticker digits:** the countdown rolls digit by digit like a ticker.
- **Minimized pill:** double-click the widget to shrink it, and double-click again to expand it.
- **Clock icon:** the − button shrinks the whole widget into a small round clock that shows progress. Click it to expand.
- **Close and come back:** the ✕ hides the widget, and the timer keeps running in the menu bar. To bring it back:
  - click the menu-bar timer and choose **Show widget**,
  - press **⌃⌥P** from any app, or
  - open Pomodoraaa again from Launchpad, Spotlight or `/Applications`.
- **⌃⌥Space** pauses or resumes from anywhere. The menu bar shows a live countdown, you get a chime and notification at the end of each session, and there's a **Launch at login** option.

## Install

Requirements: macOS 13 Ventura or later, plus Apple's command line tools (`xcode-select --install`, or a full Xcode install).

```bash
git clone https://github.com/Akschaya21/Pomodoro-desktop-widget.git
cd Pomodoro-desktop-widget
./scripts/install.sh
```

This builds `Pomodoraaa.app`, copies it to `/Applications` and launches it. Look for the timer icon in your menu bar.

To build without installing, run `./scripts/build-app.sh`. The result is `build/Pomodoraaa.app`.

### First-run permissions

- **Notifications:** allow them so you hear and see when a session ends.

## Using it

| Button | What it does |
| --- | --- |
| ⏱ | Edit time: durations, presets, rounds, auto-start |
| ♪ | Focus music: pick one of the built-in tracks and set the volume |
| 🎨 | Template: pick a look and adjust the glass tint |
| ▶ / ❚❚ | Start or pause |
| ⏭ | Skip to the next session |
| ✕ | Hide the widget (the timer keeps running in the menu bar) |
| − | Minimise to a clock icon (click the icon to expand) |

## Project layout

```
Sources/Pomodoraaa/
  AppDelegate.swift    app entry, menu bar, global shortcuts, wiring
  FloatingPanel.swift  always-on-top, draggable, non-activating window
  WidgetView.swift     widget card, minimized pill
  Panels.swift         Edit time · Focus music · Template panels
  Components.swift     glass background, buttons, tick progress bar
  Templates.swift      the 12 templates
  TimerModel.swift     pomodoro engine, chime + notifications
  MusicPlayer.swift    built-in focus tracks: playback, volume, follows the timer
  FocusSynth.swift     generates the focus tracks live (synth, noise, reverb)
  HotKey.swift         system-wide shortcuts
  Prefs.swift          saved look preferences
Resources/             Info.plist, app icon
scripts/               build-app.sh, install.sh
design/                screen designs (HTML)
```

## Design

The screens were designed first: an interactive prototype, the three option panels, the template gallery and the widget states. The design files are in `design/`.
