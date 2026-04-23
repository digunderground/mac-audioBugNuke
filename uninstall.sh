#!/bin/bash
# ─────────────────────────────────────────────────────────────
# uninstall.sh — Cleanly remove the USB-C Audio Fix Kit
# ─────────────────────────────────────────────────────────────

echo "Removing USB-C Audio Fix Kit..."

# Stop the menu bar app if running
pkill -f AudioFixMenuBar 2>/dev/null && echo "  ✓ Stopped AudioFixMenuBar" || echo "  · AudioFixMenuBar not running"

# Remove the launchd agent if it exists (from older install method)
if [[ -f "$HOME/Library/LaunchAgents/com.user.fixaudio.plist" ]]; then
    launchctl unload "$HOME/Library/LaunchAgents/com.user.fixaudio.plist" 2>/dev/null
    rm "$HOME/Library/LaunchAgents/com.user.fixaudio.plist"
    echo "  ✓ Removed launchd agent"
fi

# Remove install directory
if [[ -d "$HOME/code/_audio/mac-audioBugNuke" ]]; then
    rm -rf "$HOME/code/_audio/mac-audioBugNuke"
    echo "  ✓ Removed ~/code/_audio/mac-audioBugNuke/"
fi

echo ""
echo "Done. Everything is cleaned up."
echo "switchaudio-osx was left installed (brew remove switchaudio-osx to remove it too)."
