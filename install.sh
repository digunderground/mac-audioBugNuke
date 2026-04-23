#!/bin/bash
# ─────────────────────────────────────────────────────────────
# install.sh — One-step installer for the USB-C Audio Fix Kit
#
# What it does:
#   1. Installs switchaudio-osx via Homebrew (if not already installed)
#   2. Copies scripts to ~/fix-usbc-audio/
#   3. Compiles the menu bar app
#   4. Offers to add it to Login Items
#
# Run: bash install.sh
# ─────────────────────────────────────────────────────────────

set -e

INSTALL_DIR="$HOME/code/_audio/mac-audioBugNuke"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════════╗"
echo "║   USB-C Audio Fix Kit — Installer        ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# --- Step 1: Check/install Homebrew dependency ---
echo "▸ Step 1: Checking for switchaudio-osx..."
if command -v SwitchAudioSource >/dev/null 2>&1; then
    echo "  ✓ SwitchAudioSource already installed"
else
    echo "  Installing switchaudio-osx via Homebrew..."
    if ! command -v brew >/dev/null 2>&1; then
        echo "  ✗ Homebrew not found. Install it first: https://brew.sh"
        exit 1
    fi
    brew install switchaudio-osx
    echo "  ✓ Installed"
fi

# Show current audio devices
echo ""
echo "  Your audio output devices:"
SwitchAudioSource -a -t output 2>/dev/null | while read -r dev; do
    echo "    • $dev"
done
echo ""
echo "  Current output: $(SwitchAudioSource -c -t output 2>/dev/null)"
echo ""

# --- Step 2: Copy scripts ---
echo "▸ Step 2: Installing scripts to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/fix-usbc-audio-refresh.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/fix-usbc-audio-nuclear.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/AudioFixMenuBar.swift" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/fix-usbc-audio-refresh.sh"
chmod +x "$INSTALL_DIR/fix-usbc-audio-nuclear.sh"
echo "  ✓ Scripts installed"

# --- Step 3: Compile menu bar app ---
echo ""
echo "▸ Step 3: Compiling menu bar app..."
if command -v swiftc >/dev/null 2>&1; then
    swiftc -o "$INSTALL_DIR/AudioFixMenuBar" "$INSTALL_DIR/AudioFixMenuBar.swift" -framework Cocoa 2>&1
    if [[ $? -eq 0 ]]; then
        echo "  ✓ Menu bar app compiled"
    else
        echo "  ✗ Compilation failed — you may need Xcode Command Line Tools"
        echo "    Install with: xcode-select --install"
    fi
else
    echo "  ✗ swiftc not found — install Xcode Command Line Tools:"
    echo "    xcode-select --install"
    echo "    Then re-run this installer."
fi

# --- Step 4: Launch ---
echo ""
echo "▸ Step 4: Launching..."
if [[ -x "$INSTALL_DIR/AudioFixMenuBar" ]]; then
    "$INSTALL_DIR/AudioFixMenuBar" &
    disown
    echo "  ✓ AudioFix is running in your menu bar (look for 🔇)"
    echo "    Click it → Toggle Audio Fix to turn ON"
    echo ""
    echo "  To auto-start on login:"
    echo "    System Settings → General → Login Items → add AudioFixMenuBar"
else
    echo "  ⚠ Menu bar app not available — use the scripts manually:"
    echo "    ~/code/_audio/mac-audioBugNuke/fix-usbc-audio-refresh.sh"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Installation complete!                  ║"
echo "║                                            ║"
echo "║   🔇 = OFF (click to toggle)              ║"
echo "║   🔊 = ON  (refreshing every 2 min)       ║"
echo "║                                            ║"
echo "║   Your Minifuse4 is protected —            ║"
echo "║   only targets 'USB PnP Sound Device'.    ║"
echo "╚══════════════════════════════════════════╝"
