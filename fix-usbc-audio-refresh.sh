#!/usr/bin/env bash
# fix-usbc-audio-refresh.sh
#
# Automated workaround for macOS Tahoe USB-C audio degradation.
# Silently switches audio output to internal speakers and immediately back,
# which resets the USB audio stream before stutter becomes audible.
#
# SAFETY: Only targets USB-C speakers. Skips if current output is:
#   - Internal/built-in speakers (nothing to fix)
#   - Minifuse4 or any other audio interface (they have their own drivers)
#
# Requirements: brew install switchaudio-osx
#
# Configuration:
#   SKIP_DEVICES    - pipe-separated list of device names to NEVER touch
#   INTERNAL_AUDIO_PREFIX - prefix of internal audio device name (default: "Mac")

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# --- Configuration ---
internal_prefix="${INTERNAL_AUDIO_PREFIX:-Mac}"

# Devices to NEVER switch away from (your audio interfaces, etc.)
# Add more with pipe separation: "Minifuse|Scarlett|Apollo"
SKIP_DEVICES="${SKIP_DEVICES:-Minifuse|MiniFuse|MINIFUSE}"

# Only refresh these specific devices (leave empty to refresh ALL non-skipped external devices)
# Set to your problematic device name for surgical targeting
TARGET_DEVICES="${TARGET_DEVICES:-USB PnP Sound Device}"

# --- Find SwitchAudioSource ---
switch_audio_bin=""
for candidate in /opt/homebrew/bin/SwitchAudioSource /usr/local/bin/SwitchAudioSource; do
    if [[ -x "$candidate" ]]; then
        switch_audio_bin="$candidate"
        break
    fi
done
if [[ -z "$switch_audio_bin" ]] && command -v SwitchAudioSource >/dev/null 2>&1; then
    switch_audio_bin="$(command -v SwitchAudioSource)"
fi

if [[ -z "$switch_audio_bin" ]]; then
    echo "error: SwitchAudioSource not found. Install with: brew install switchaudio-osx" >&2
    exit 1
fi

# --- Get current output device ---
current_output="$("$switch_audio_bin" -c -t output 2>/dev/null | head -n 1)"

if [[ -z "$current_output" ]]; then
    exit 0  # Can't determine device, skip silently
fi

# --- Skip if on internal audio (nothing to refresh) ---
if [[ "$current_output" == "$internal_prefix"* ]]; then
    exit 0
fi

# --- Skip if on a protected device (Minifuse4, etc.) ---
if echo "$current_output" | grep -qiE "$SKIP_DEVICES"; then
    exit 0
fi

# --- Skip if not our target device (when TARGET_DEVICES is set) ---
if [[ -n "$TARGET_DEVICES" ]]; then
    if ! echo "$current_output" | grep -qiE "$TARGET_DEVICES"; then
        exit 0
    fi
fi

# --- Find internal audio device ---
internal_output="$("$switch_audio_bin" -a -t output 2>/dev/null | grep -E "^${internal_prefix}" | head -n 1 || true)"

if [[ -z "$internal_output" ]]; then
    exit 0  # No internal device found, skip silently
fi

# --- Perform the switch (internal → back to external) ---
"$switch_audio_bin" -t output -s "$internal_output" >/dev/null 2>&1
sleep 0.1
"$switch_audio_bin" -t output -s "$current_output" >/dev/null 2>&1
