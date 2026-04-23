#!/bin/bash
# fix-usbc-audio-nuclear.sh
#
# Full CoreAudio reset — kills client processes holding corrupted state,
# THEN restarts audio daemons. More thorough than "sudo killall coreaudiod".
#
# Usage: ./fix-usbc-audio-nuclear.sh
#        (requires sudo — will prompt for password)

fixaudio() {
    sudo -v || return 1

    local skip="coreaudiod|audiomxd|audioclocksyncd|audioanalyticsd|audioaccessoryd|AudioComponentRegistrar|audio.DriverHelper|audio.SandboxHelper|ParrotAudioPlugin"

    echo "=== Phase 1: Killing CoreAudio client processes ==="
    lsof 2>/dev/null | grep CoreAudio | awk '{print $2, $1}' | sort -t' ' -k1,1 -un | grep -vE "$skip" | while read pid name; do
        echo "  kill $name (PID $pid)"
        kill -9 "$pid" 2>/dev/null
    done

    killall Xcode SimulatorTrampoline com.apple.CoreSimulator.CoreSimulatorService simdiskimaged 2>/dev/null || true

    echo "  Waiting for clients to terminate..."
    sleep 1

    echo "=== Phase 2: Restarting all audio daemons ==="
    sudo killall -9 coreaudiod audiomxd audioclocksyncd audioanalyticsd audioaccessoryd AudioComponentRegistrar 2>/dev/null || true
    echo "  All audio daemons killed (they will auto-restart)"

    sleep 2

    local new_pid
    new_pid=$(pgrep coreaudiod 2>/dev/null || echo "not found")
    echo "=== Done. New coreaudiod PID: $new_pid ==="
    echo ""
    echo "Audio should be restored. You may need to reselect your output device."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    fixaudio
fi
