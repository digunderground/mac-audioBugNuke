# mac-audioBugNuke — Release Notes & Documentation

**Version:** 1.1  
**Date:** April 23, 2026  
**Author:** Dig + Claude  
**Target OS:** macOS Tahoe 26.4 (25E246)  
**Target Device:** USB PnP Sound Device (USB-C speakers)

---

## The Problem

On macOS Tahoe 26.x, USB-C speakers using Apple's built-in USB audio class driver experience intermittent audio stuttering, robotic/broken sound, and dropouts every few minutes. The issue does NOT affect audio interfaces with their own dedicated drivers (e.g., Arturia Minifuse4).

### Root Cause

This is a **confirmed macOS Tahoe bug** in CoreAudio's management of USB/Thunderbolt audio streams. Key findings:

- Audio state gradually degrades over time — corrupted state accumulates in CoreAudio **client processes**, not just the `coreaudiod` daemon
- Restarting `coreaudiod` alone does NOT fix it because corrupted state persists in client processes
- Switching audio output away and back temporarily clears the issue (10–60 minutes of relief)
- Apple has acknowledged the bug; senior support advisors confirmed a patch is in development
- As of macOS 26.4.1 (April 9, 2026), the bug is **still not fixed**
- The Minifuse4 is unaffected because it uses Arturia's own USB audio driver, not Apple's built-in class driver

### Triggers That Accelerate Degradation

- Xcode / iOS Simulator running in background
- Multiple Bluetooth device connections/disconnections
- External display connections (HDMI/Thunderbolt)
- High CPU or memory pressure
- Extended continuous playback (2-3+ hours)

---

## What We Built

### File Inventory

| File | Purpose |
|------|---------|
| `AudioFixMenuBar.swift` | Native macOS menu bar app with on/off toggle (Swift) |
| `fix-usbc-audio-refresh.sh` | Audio refresh script — switches output away and back |
| `fix-usbc-audio-nuclear.sh` | Full CoreAudio + client process reset |
| `install.sh` | One-step installer (installs deps, compiles app, launches) |
| `uninstall.sh` | Clean removal of everything |
| `RELEASE-NOTES.md` | This file |

### Installation Path

```
~/code/_audio/mac-audioBugNuke/
```

---

## Detailed Component Documentation

### 1. AudioFixMenuBar (Menu Bar App)

**What it is:** A native Swift menu bar application — no Python, no Electron, no dependencies beyond `switchaudio-osx`. Compiles to a single binary.

**Menu bar icons (native SF Symbols — adapts to dark/light menu bar):**
- `speaker.slash` = OFF (not refreshing — safe for mixing/recording)
- `speaker.wave.2` = ON (refreshing every 2 minutes)

**Menu items when clicked:**
- **Toggle Audio Fix** — turns auto-refresh on/off (keyboard shortcut: T)
- **Status line** — shows current state and refresh interval
- **Device line** — shows current output device and whether it will be refreshed
- **Refresh Audio Now** — manual one-shot refresh (keyboard shortcut: R)
- **Nuclear Reset** — full CoreAudio + client process kill (shows confirmation dialog)
- **Quit AudioFix** — stops everything (keyboard shortcut: Q)

**Device targeting:**
- ONLY acts on: `USB PnP Sound Device`
- NEVER touches: Minifuse / MiniFuse / MINIFUSE (any capitalization)
- Skips: Internal/built-in speakers (anything starting with "Mac")
- Skips: Any other audio device not matching the target

**How the refresh works:**
1. Checks current output device name
2. If it's NOT "USB PnP Sound Device" → does nothing
3. If it IS → switches to internal speakers for ~100ms, then switches back
4. This clears the degraded USB audio state before stutter becomes audible
5. Repeats every 120 seconds (configurable in source)

**Audibility note:** The switch takes ~100ms. For casual music/video/gaming, it's imperceptible. During critical DAW mixing sessions, there's a theoretical risk of a tiny click at the switch point — toggle OFF during those sessions.

### 2. fix-usbc-audio-refresh.sh (Standalone Script)

Same logic as the menu bar app, but as a standalone bash script. Can be:
- Run manually: `./fix-usbc-audio-refresh.sh`
- Automated via cron/launchd
- Called from other scripts

**Environment variables:**
- `SKIP_DEVICES` — pipe-separated device names to never touch (default: `Minifuse|MiniFuse|MINIFUSE`)
- `TARGET_DEVICES` — pipe-separated device names to target (default: `USB PnP Sound Device`)
- `INTERNAL_AUDIO_PREFIX` — prefix for internal speakers (default: `Mac`)

**Dependency:** `switchaudio-osx` (`brew install switchaudio-osx`)

### 3. fix-usbc-audio-nuclear.sh (Emergency Reset)

For when the stutter has already started and you need an immediate fix.

**What it does (two phases):**
1. **Phase 1:** Finds and kills ALL processes that have CoreAudio libraries loaded (except the audio daemons themselves). This clears the corrupted client state that `killall coreaudiod` alone misses.
2. **Phase 2:** Kills all audio daemons (`coreaudiod`, `audiomxd`, `audioclocksyncd`, `audioanalyticsd`, `audioaccessoryd`, `AudioComponentRegistrar`). They auto-restart with clean state.

**Requires:** sudo (will prompt for password)

**Note:** This will momentarily interrupt ALL audio on the system. Any apps playing audio will stop and need to be resumed.

**Can also be sourced into your shell:**
```bash
# Add to ~/.zshrc:
source ~/code/_audio/mac-audioBugNuke/fix-usbc-audio-nuclear.sh
# Then just type:
fixaudio
```

---

## Installation Instructions

### Prerequisites
- macOS Tahoe 26.x
- Homebrew installed (`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
- Xcode Command Line Tools (`xcode-select --install`)

### Install (one command)
```bash
cd ~/code/_audio/mac-audioBugNuke && bash install.sh
```

This will:
1. Install `switchaudio-osx` via Homebrew (if needed)
2. Show your current audio devices
3. Compile `AudioFixMenuBar.swift` → `AudioFixMenuBar` binary
4. Launch the menu bar app

### Auto-Start on Login
System Settings → General → Login Items → click `+` → navigate to `~/code/_audio/mac-audioBugNuke/AudioFixMenuBar`

### Uninstall (clean removal)
```bash
bash ~/code/_audio/mac-audioBugNuke/uninstall.sh
```

---

## System Tweaks Applied (Manual — Fix 3)

These were applied manually during troubleshooting on April 23, 2026:

```bash
# Boost CoreAudio daemon priority (lasts until reboot)
sudo renice -20 $(pgrep coreaudiod)

# Disable Power Nap (prevents USB re-enumeration)
sudo pmset -a powernap 0

# Disable standby and autopoweroff (prevents USB power cycling)
sudo pmset -a standby 0
sudo pmset -a autopoweroff 0
```

**Note:** The `renice` command resets on reboot. To make it persistent, add it to a login script or launchd agent.

---

## Audio MIDI Setup

- Device: USB PnP Sound Device
- Sample rate: 48,000 Hz (recommended — macOS system audio runs natively at 48kHz; using 44.1kHz forces sample rate conversion which adds CPU load to the already-buggy pipeline)
- 96,000 Hz was not available for this device
- 44,100 Hz was tested and is worse for this bug

---

## What Didn't Work

| Approach | Result |
|----------|--------|
| `sudo killall coreaudiod` alone | Fixes for ~1 second, then immediately degrades again |
| Changing sample rate to 44.1kHz | Made it worse (forces sample rate conversion) |
| Sleep/wake cycle | No effect |
| Toggling sample rates in Audio MIDI Setup | Temporary — same as output switching |

---

## When Will Apple Fix This?

Apple senior support has confirmed a patch is in development targeting the CoreAudio USB audio class driver. However:
- macOS 26.1 fixed some audio bugs (FaceTime, Safari 44.1kHz, MOTU/Apogee compatibility) but NOT the USB speaker degradation
- macOS 26.4 and 26.4.1 still exhibit the issue
- No specific ETA has been given

**Recommendation:** Keep macOS updated and check release notes for CoreAudio/USB audio mentions. Once Apple ships the fix, you can run `uninstall.sh` to remove this workaround.

---

## Research Sources

- [Apple Community: Audio glitches on Mac after macOS Tahoe update](https://discussions.apple.com/thread/256140785)
- [CoreAudio workaround — kill all clients + daemons (GitHub @metrovoc)](https://gist.github.com/metrovoc/0b5e3590c6069cf99b01559863bc2ce4)
- [Audio output switch workaround (GitHub @fl034)](https://gist.github.com/fl034/dbf7e445d96a3979af734911aac6ebe0)
- [Rogue Amoeba: macOS Tahoe audio bug fixes](https://weblog.rogueamoeba.com/2025/11/04/macos-26-tahoe-includes-important-audio-related-bug-fixes/)
- [GeeksChalk: Fix Audio Crackling on macOS Tahoe](https://geekschalk.com/fix-audio-crackling-pops-or-drop-outs-on-mac-after-updating-to-macos-tahoe-26/)
- [Sweetwater: macOS Tahoe Audio Optimization Guide](https://www.sweetwater.com/sweetcare/articles/macos-tahoe-26-audio-optimization-guide/)
- [switchaudio-osx (Homebrew)](https://formulae.brew.sh/formula/switchaudio-osx)
- [Apple Community: Crackling sound after updating to macOS Tahoe 26](https://discussions.apple.com/thread/256155108)
