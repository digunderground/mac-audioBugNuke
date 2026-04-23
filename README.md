# mac-audioBugNuke 🔊

**A workaround for the macOS Tahoe USB-C audio stuttering / dropout bug.**

If your USB-C speakers stutter, sound robotic, or drop out every few minutes on macOS Tahoe — and restarting CoreAudio doesn't fully fix it — this tool is for you.

> **Status:** Active bug in macOS Tahoe 26.x confirmed by Apple senior support. A CoreAudio patch is in development. This tool provides a reliable workaround until Apple ships the fix.

---

## The Problem

On macOS Tahoe 26.x, USB-C speakers and USB audio devices using Apple's built-in USB audio class driver experience intermittent audio stuttering, robotic/broken sound, and complete dropouts — typically every 5–30 minutes of use.

**Key findings:**

- Audio state gradually degrades over time in CoreAudio **client processes**, not just the `coreaudiod` daemon itself
- Running `sudo killall coreaudiod` alone does **not** fix it — corrupted state persists in all apps that have CoreAudio loaded
- Switching your audio output to another device and back temporarily clears the issue (buys you another 10–60 minutes)
- **Apple has acknowledged the bug.** Senior support advisors confirmed a patch is in development
- As of macOS 26.4.1 (April 2026), the bug is **still not fixed**
- Audio interfaces with their own dedicated USB drivers are **not affected** — only devices relying on Apple's generic USB audio class driver

**Triggers that accelerate degradation:**
- Xcode / iOS Simulator running in the background
- Multiple Bluetooth device connections/disconnections
- External display connections (HDMI/Thunderbolt)
- High CPU or memory pressure
- Extended continuous playback (2–3+ hours)

---

## What This Tool Does

Instead of waiting for the stutter to start, it quietly and automatically performs the output-switch trick on a timer — before degradation becomes audible. The switch is wrapped in a mute/unmute so it is completely silent and imperceptible.

**Three components:**

| Component | Purpose |
|-----------|---------|
| `AudioFixMenuBar` | Native Swift menu bar app — toggle on/off, per-device targeting, manual refresh, nuclear reset |
| `fix-usbc-audio-refresh.sh` | Standalone bash script for the same refresh logic (cron/launchd friendly) |
| `fix-usbc-audio-nuclear.sh` | Emergency full reset — kills all CoreAudio clients + restarts all audio daemons |

**Device targeting:**

The menu bar app dynamically lists all your connected external output devices. You choose which ones to protect — the fix only runs when the active output is one you've enabled. Your choices are saved and restored on every launch.

- ✅ Refreshes only devices you explicitly enable in the **Target Devices** menu
- 🚫 Never touches internal/built-in speakers
- 🚫 Never touches devices you haven't enabled
- 🔄 Device list updates live as you plug/unplug hardware — no restart needed

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

### 4. Turn it on and choose your devices

The app launches in the **ON** state automatically. Click the menu bar icon and go to **Target Devices** to check which audio devices you want protected. Any device you enable will be silently refreshed on the timer.

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
| **Output line** | Shows current output device and whether it will be refreshed |
| **Target Devices ▶** | Submenu listing all connected external audio devices — click any to enable/disable it as a refresh target |
| **Refresh Audio Now** | Runs a one-shot manual refresh immediately (keyboard: `R`) |
| **Nuclear Reset** | Full CoreAudio + client process kill — use when stutter has already started |
| **Quit AudioFix** | Exits the app (keyboard: `Q`) |

**Target Devices** is fully dynamic — the list is rebuilt every time you open the menu by querying your system live, so plugging in a new device or disconnecting one is reflected immediately without restarting the app. Your enabled/disabled choices are saved in `UserDefaults` and restored on every launch.

**When to toggle OFF:** During critical DAW recording or mixing sessions you may prefer to pause the timer. Toggle it back on when done.

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
| `SKIP_DEVICES` | *(empty)* | Pipe-separated device names to never touch, e.g. `Scarlett\|Apollo` |
| `TARGET_DEVICES` | *(empty — targets all external devices)* | Pipe-separated device names to target specifically |
| `INTERNAL_AUDIO_PREFIX` | `Mac` | Prefix used to identify internal speakers |

Example — target only one specific device:
```bash
TARGET_DEVICES="My USB Speakers" bash fix-usbc-audio-refresh.sh
```

Example — skip your audio interface while targeting everything else:
```bash
SKIP_DEVICES="Scarlett|Apollo" bash fix-usbc-audio-refresh.sh
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

Open **Audio MIDI Setup** (Applications → Utilities) and set your USB audio device to **48,000 Hz**.

- macOS system audio runs natively at 48 kHz
- Using 44.1 kHz forces a sample rate conversion, adding CPU load to an already-buggy audio pipeline and making the bug worse
- 96 kHz is typically not available on USB audio class devices

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

Make sure you're running it with `bash` (not `source`) so it prompts for sudo correctly:
```bash
bash ~/code/_audio/mac-audioBugNuke/fix-usbc-audio-nuclear.sh
```

**My device doesn't appear in the Target Devices list**

Only external, non-internal devices appear in the list. Run the following to see exactly how your system reports your device names:
```bash
SwitchAudioSource -a -t output
```
The name shown there is exactly what will appear in the Target Devices menu.

**The fix runs but I still hear stutter**

Try reducing the refresh interval. Edit `AudioFixMenuBar.swift`, change `refreshIntervalSeconds` from `120` to `60` (or lower), and recompile. Some systems degrade faster than others.

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

- A proper `.app` bundle with code signing so Gatekeeper stops complaining
- A launchd plist installer as an alternative to the Login Items approach
- Testing on Intel Macs (developed and tested on Apple Silicon)
- Configurable refresh interval via the menu (without recompiling)

---

## License

MIT — do whatever you want with it. If this saves your sanity, a ⭐ on the repo is appreciated.
