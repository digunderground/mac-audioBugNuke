# mac-audioBugNuke 🔊

**A workaround for the macOS Tahoe USB-C audio stuttering / dropout bug.**

If your USB-C speakers stutter, sound robotic, or drop out every few minutes on macOS Tahoe — and restarting CoreAudio doesn't fully fix it — this tool is for you.

> **Status:** Active bug in macOS Tahoe 26.x confirmed by Apple senior support. A CoreAudio patch is in development. This tool provides a reliable workaround until Apple ships the fix.

---

## The Problem

On macOS Tahoe 26.x, USB-C speakers using Apple's built-in USB audio class driver experience intermittent audio stuttering, robotic/broken sound, and complete dropouts — typically every 5–30 minutes of use.

**Key findings:**

- Audio state gradually degrades over time in CoreAudio **client processes**, not just the `coreaudiod` daemon itself
- Running `sudo killall coreaudiod` alone does **not** fix it — corrupted state persists in all the apps that have CoreAudio loaded
- Switching your audio output to another device and back temporarily clears the issue (buys you another 10–60 minutes)
- **Apple has acknowledged the bug.** Senior support advisors confirmed a patch is in development
- As of macOS 26.4.1 (April 2026), the bug is **still not fixed**
- Audio interfaces with their own dedicated USB drivers (e.g., Arturia Minifuse4, Scarlett series) are **not affected** — only devices using Apple's generic USB audio class driver

**Triggers that accelerate degradation:**
- Xcode / iOS Simulator running in the background
- Multiple Bluetooth device connections/disconnections
- External display connections (HDMI/Thunderbolt)
- High CPU or memory pressure
- Extended continuous playback (2–3+ hours)

---

## What This Tool Does

Instead of waiting for the stutter to start, it quietly and automatically performs the output-switch trick every 2 minutes — before degradation becomes audible. The switch takes ~100ms and is imperceptible during normal music, video, or gaming playback.

**Three components:**

| Component | Purpose |
|-----------|---------|
| `AudioFixMenuBar` | Native Swift menu bar app — toggle on/off, manual refresh, nuclear reset |
| `fix-usbc-audio-refresh.sh` | Standalone bash script for the same refresh logic (crон/launchd friendly) |
| `fix-usbc-audio-nuclear.sh` | Emergency full reset — kills all CoreAudio clients + restarts all audio daemons |

**Device safety:**
- ✅ Only acts on: `USB PnP Sound Device` (configurable)
- 🚫 Never touches: Minifuse / MiniFuse / MINIFUSE (any capitalization)
- 🚫 Never touches: Internal/built-in speakers (Mac*)
- 🚫 Never touches: Any other audio device not matching the target

---

## Requirements

- **macOS Tahoe 26.x** (this bug does not exist on earlier macOS versions)
- **Homebrew** — [install here](https://brew.sh) if you don't have it:
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
- **Xcode Command Line Tools** — required to compile the menu bar app:
  ```bash
  xcode-select --install
  ```
- **switchaudio-osx** — installed automatically by `install.sh`, or manually:
  ```bash
  brew install switchaudio-osx
  ```

---

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/digunderground/mac-audioBugNuke.git ~/code/_audio/mac-audioBugNuke
cd ~/code/_audio/mac-audioBugNuke
```

### 2. Run the installer

```bash
bash install.sh
```

This will:
1. Check for / install `switchaudio-osx` via Homebrew
2. Display your current audio output devices
3. Compile `AudioFixMenuBar.swift` → native binary
4. Launch the menu bar app

### 3. Handle Gatekeeper (first launch only)

Because the binary is unsigned, macOS will block it on first run. When you see the "unidentified developer" dialog:

1. Open **System Settings → Privacy & Security**
2. Scroll down to the Security section
3. Click **"Allow Anyway"** next to AudioFixMenuBar
4. Try launching again — click **Open** on the follow-up dialog

This only happens once.

### 4. Enable the fix

Click the menu bar icon → **Toggle Audio Fix** to turn it ON.

The icon changes from `speaker.slash` (off) to `speaker.wave.2` (on, refreshing every 2 min).

---

## Auto-Start on Login

To have AudioFix launch automatically when you log in:

1. **System Settings → General → Login Items & Extensions**
2. Click **`+`** under "Open at Login"
3. Navigate to `~/code/_audio/mac-audioBugNuke/` and select **`AudioFixMenuBar`**
4. Click **Open**

The app launches in the **ON** state by default, so it starts protecting your audio immediately.

---

## Menu Bar App Usage

Click the menu bar icon to open the menu:

| Menu Item | What It Does |
|-----------|-------------|
| **Toggle Audio Fix** | Turns auto-refresh ON/OFF (keyboard: `T`) |
| **Status line** | Shows current state and refresh interval |
| **Device line** | Shows current output and whether it will be refreshed |
| **Refresh Audio Now** | Runs a one-shot manual refresh immediately (keyboard: `R`) |
| **Nuclear Reset** | Full CoreAudio + client process kill — use when stutter has already started |
| **Quit AudioFix** | Exits the app (keyboard: `Q`) |

**When to toggle OFF:** During critical DAW recording/mixing sessions, the ~100ms output switch could theoretically cause a tiny click at the switch point. Toggle off for those sessions, then back on when done.

---

## Standalone Scripts

### fix-usbc-audio-refresh.sh

The same refresh logic as the menu bar app, as a plain bash script. Run it manually or wire it into cron/launchd:

```bash
# Run once manually
./fix-usbc-audio-refresh.sh

# Or via cron every 2 minutes
*/2 * * * * /bin/bash ~/code/_audio/mac-audioBugNuke/fix-usbc-audio-refresh.sh
```

**Environment variable overrides:**

| Variable | Default | Description |
|----------|---------|-------------|
| `SKIP_DEVICES` | `Minifuse\|MiniFuse\|MINIFUSE` | Pipe-separated device names to never touch |
| `TARGET_DEVICES` | `USB PnP Sound Device` | Pipe-separated device names to target |
| `INTERNAL_AUDIO_PREFIX` | `Mac` | Prefix used to identify internal speakers |

Example — target a different device name:
```bash
TARGET_DEVICES="My USB Speakers" bash fix-usbc-audio-refresh.sh
```

### fix-usbc-audio-nuclear.sh

For when the stutter has **already started** and you need an immediate fix.

```bash
bash ~/code/_audio/mac-audioBugNuke/fix-usbc-audio-nuclear.sh
```

**What it does (two phases):**
1. **Phase 1:** Finds and kills ALL processes that have CoreAudio libraries loaded (except audio daemons themselves). This clears the corrupted client state that `killall coreaudiod` alone misses.
2. **Phase 2:** Kills all audio daemons (`coreaudiod`, `audiomxd`, `audioclocksyncd`, `audioanalyticsd`, `audioaccessoryd`, `AudioComponentRegistrar`). They auto-restart with clean state in 1–2 seconds.

> ⚠️ This interrupts ALL audio on your system momentarily. Any apps playing audio will stop and need to be resumed.

**Add it as a shell function** for quick access — add to your `~/.zshrc`:
```bash
source ~/code/_audio/mac-audioBugNuke/fix-usbc-audio-nuclear.sh
# Then just type: fixaudio
```

---

## Recommended System Tweaks

These optional system settings reduce how often CoreAudio degrades. Apply once in Terminal — they persist across reboots (except `renice`, which resets on reboot):

```bash
# Disable Power Nap (prevents USB re-enumeration during idle)
sudo pmset -a powernap 0

# Disable standby and autopoweroff (prevents USB power cycling)
sudo pmset -a standby 0
sudo pmset -a autopoweroff 0

# Boost CoreAudio daemon priority (resets on reboot)
sudo renice -20 $(pgrep coreaudiod)
```

To make the `renice` persistent, add it to a login script or launchd agent.

---

## Audio MIDI Setup Recommendation

Open **Audio MIDI Setup** (Applications → Utilities) and set your USB PnP Sound Device to **48,000 Hz**.

- macOS system audio runs natively at 48 kHz
- Using 44.1 kHz forces a sample rate conversion, adding CPU load to an already-buggy audio pipeline and making the bug worse
- 96 kHz is typically not available on USB class audio devices

---

## Uninstall

```bash
bash ~/code/_audio/mac-audioBugNuke/uninstall.sh
```

This stops the menu bar app, removes any launchd agents, and deletes the install directory. It leaves `switchaudio-osx` installed — to remove that too:

```bash
brew remove switchaudio-osx
```

---

## Troubleshooting

**Icon doesn't appear in menu bar after launch**

macOS may be hiding it due to a full menu bar. Check System Settings → Control Centre, or use [Bartender](https://www.macbartender.com) / [Ice](https://github.com/jordanbaird/Ice) to manage overflow icons.

**Compilation fails with `command not found: swiftc`**

Install Xcode Command Line Tools:
```bash
xcode-select --install
```
Then recompile manually:
```bash
swiftc -o ~/code/_audio/mac-audioBugNuke/AudioFixMenuBar \
  ~/code/_audio/mac-audioBugNuke/AudioFixMenuBar.swift \
  -framework Cocoa
```

**"Cannot be opened because it is from an unidentified developer"**

See Step 3 of Installation above. Go to System Settings → Privacy & Security → Allow Anyway.

**The nuclear reset doesn't fix it**

Make sure you're running it with `bash` (not `source` in this case) so it prompts for sudo correctly:
```bash
bash ~/code/_audio/mac-audioBugNuke/fix-usbc-audio-nuclear.sh
```

**My device name isn't "USB PnP Sound Device"**

Find your device's exact name:
```bash
SwitchAudioSource -a -t output
```
Then set the `TARGET_DEVICES` environment variable before running the script, or edit the `targetDevice` constant in `AudioFixMenuBar.swift` and recompile.

---

## What Didn't Work

For the record — approaches that were tried and failed:

| Approach | Result |
|----------|--------|
| `sudo killall coreaudiod` alone | Fixes for ~1 second, then immediately degrades again |
| Changing sample rate to 44.1 kHz | Made it worse (forces sample rate conversion) |
| Sleep/wake cycle | No effect |
| Toggling sample rates in Audio MIDI Setup | Same temporary relief as output switching |
| Unplugging and replugging USB-C | Temporary fix only |

---

## When Will Apple Fix This?

Apple senior support has confirmed a CoreAudio patch is in development targeting the USB audio class driver. However:

- macOS 26.1 fixed some audio bugs (FaceTime, Safari 44.1 kHz, MOTU/Apogee compatibility) but not this one
- macOS 26.4 and 26.4.1 still exhibit the issue

**Recommendation:** Keep macOS updated and watch release notes for CoreAudio/USB audio mentions. Once Apple ships the fix, run `uninstall.sh` to clean everything up.

---

## Research & Credits

This tool is built on community-discovered workarounds. Thanks to everyone who dug into this:

- [Apple Community: Audio glitches on Mac after macOS Tahoe update](https://discussions.apple.com/thread/256140785)
- [Apple Community: Crackling sound after updating to macOS Tahoe 26](https://discussions.apple.com/thread/256155108)
- [CoreAudio workaround — kill all clients + daemons — @metrovoc](https://gist.github.com/metrovoc/0b5e3590c6069cf99b01559863bc2ce4)
- [Audio output switch workaround — @fl034](https://gist.github.com/fl034/dbf7e445d96a3979af734911aac6ebe0)
- [Rogue Amoeba: macOS Tahoe audio bug fixes](https://weblog.rogueamoeba.com/2025/11/04/macos-26-tahoe-includes-important-audio-related-bug-fixes/)
- [switchaudio-osx on Homebrew](https://formulae.brew.sh/formula/switchaudio-osx)

---

## Contributing

PRs welcome. Especially useful:

- Support for other affected device names / device-name detection improvements
- A proper `.app` bundle with code signing so Gatekeeper stops complaining
- A launchd plist installer as an alternative to the Login Items approach
- Testing on Intel Macs (developed and tested on Apple Silicon)

---

## License

MIT — do whatever you want with it. If this saves your sanity, a ⭐ on the repo is appreciated.
