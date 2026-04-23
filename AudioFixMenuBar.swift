import Cocoa

// ─────────────────────────────────────────────────────────────
// AudioFixMenuBar — Menu bar toggle for USB-C audio refresh
//
// Shows a speaker icon in the menu bar. Click to toggle on/off.
//   🔊 (green dot)  = Active — refreshing audio every 2 minutes
//   🔇 (red dot)    = Paused — doing nothing
//
// Compile:
//   swiftc -o AudioFixMenuBar AudioFixMenuBar.swift -framework Cocoa
//
// Run:
//   ./AudioFixMenuBar
//
// Or move to /Applications and add to Login Items for auto-start.
// ─────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var isActive = true

    // ── Configuration ──
    let refreshIntervalSeconds: TimeInterval = 120  // 2 minutes
    let scriptPath: String = NSHomeDirectory() + "/code/_audio/mac-audioBugNuke/fix-usbc-audio-refresh.sh"
    let skipDevices = ["Minifuse", "MiniFuse", "MINIFUSE"]
    let targetDevice = "USB PnP Sound Device"  // ONLY refresh this device
    let internalPrefix = "Mac"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        updateIcon()
        buildMenu()
        startTimer()  // auto-start ON at launch
    }

    func buildMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Toggle Audio Fix", action: #selector(toggleFix), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let statusItem2 = NSMenuItem(title: "Status: OFF", action: nil, keyEquivalent: "")
        statusItem2.tag = 100
        menu.addItem(statusItem2)

        let deviceItem = NSMenuItem(title: "Current output: checking...", action: nil, keyEquivalent: "")
        deviceItem.tag = 200
        menu.addItem(deviceItem)

        menu.addItem(NSMenuItem.separator())

        let refreshNow = NSMenuItem(title: "Refresh Audio Now", action: #selector(runRefreshOnce), keyEquivalent: "r")
        refreshNow.target = self
        menu.addItem(refreshNow)

        let nuclearItem = NSMenuItem(title: "Nuclear Reset (kills all audio clients)", action: #selector(runNuclear), keyEquivalent: "")
        nuclearItem.target = self
        menu.addItem(nuclearItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit AudioFix", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func updateIcon() {
        if let button = statusItem.button {
            let symbolName = isActive ? "speaker.wave.2" : "speaker.slash"
            if let image = NSImage(systemSymbolName: symbolName,
                                   accessibilityDescription: isActive ? "Audio Fix: ON" : "Audio Fix: OFF") {
                image.isTemplate = true   // auto-adapts to dark/light menu bar
                button.image = image
                button.title = ""
            }
        }
        // Update status text in menu
        if let menu = statusItem.menu,
           let statusMenuItem = menu.item(withTag: 100) {
            statusMenuItem.title = isActive ? "Status: ON — refreshing every \(Int(refreshIntervalSeconds))s" : "Status: OFF"
        }
        updateDeviceInfo()
    }

    func updateDeviceInfo() {
        guard let menu = statusItem.menu,
              let deviceItem = menu.item(withTag: 200) else { return }

        if let device = getCurrentDevice() {
            let protected = skipDevices.contains(where: { device.localizedCaseInsensitiveContains($0) })
            let isTarget = device.localizedCaseInsensitiveContains(targetDevice)
            if protected {
                deviceItem.title = "Output: \(device) (protected — won't touch)"
            } else if device.hasPrefix(internalPrefix) {
                deviceItem.title = "Output: \(device) (internal — skipping)"
            } else if isTarget {
                deviceItem.title = "Output: \(device) ✓ (will refresh)"
            } else {
                deviceItem.title = "Output: \(device) (not target — skipping)"
            }
        } else {
            deviceItem.title = "Output: unknown"
        }
    }

    @objc func toggleFix() {
        isActive.toggle()
        if isActive {
            startTimer()
        } else {
            stopTimer()
        }
        updateIcon()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            self?.runRefresh()
        }
        // Also run immediately on start
        runRefresh()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func getCurrentDevice() -> String? {
        let task = Process()
        let pipe = Pipe()

        // Try common locations for SwitchAudioSource
        let candidates = ["/opt/homebrew/bin/SwitchAudioSource", "/usr/local/bin/SwitchAudioSource"]
        var found: String?
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                found = c
                break
            }
        }
        guard let bin = found else { return nil }

        task.executableURL = URL(fileURLWithPath: bin)
        task.arguments = ["-c", "-t", "output"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func runRefresh() {
        // Check current device first
        guard let current = getCurrentDevice() else { return }

        // Skip internal audio
        if current.hasPrefix(internalPrefix) { return }

        // Skip protected devices (Minifuse, etc.)
        for skip in skipDevices {
            if current.localizedCaseInsensitiveContains(skip) { return }
        }

        // Only act on the target device
        if !current.localizedCaseInsensitiveContains(targetDevice) { return }

        // Find SwitchAudioSource
        let candidates = ["/opt/homebrew/bin/SwitchAudioSource", "/usr/local/bin/SwitchAudioSource"]
        var bin: String?
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                bin = c
                break
            }
        }
        guard let switchBin = bin else { return }

        // Get internal device name
        let listTask = Process()
        let listPipe = Pipe()
        listTask.executableURL = URL(fileURLWithPath: switchBin)
        listTask.arguments = ["-a", "-t", "output"]
        listTask.standardOutput = listPipe
        listTask.standardError = FileHandle.nullDevice

        do {
            try listTask.run()
            listTask.waitUntilExit()
            let data = listPipe.fileHandleForReading.readDataToEndOfFile()
            let devices = String(data: data, encoding: .utf8)?
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix(internalPrefix) } ?? []

            guard let internalDevice = devices.first, !internalDevice.isEmpty else { return }

            // Switch to internal
            let t1 = Process()
            t1.executableURL = URL(fileURLWithPath: switchBin)
            t1.arguments = ["-t", "output", "-s", internalDevice]
            t1.standardOutput = FileHandle.nullDevice
            t1.standardError = FileHandle.nullDevice
            try t1.run()
            t1.waitUntilExit()

            // Brief pause
            usleep(100_000)  // 0.1 seconds

            // Switch back
            let t2 = Process()
            t2.executableURL = URL(fileURLWithPath: switchBin)
            t2.arguments = ["-t", "output", "-s", current]
            t2.standardOutput = FileHandle.nullDevice
            t2.standardError = FileHandle.nullDevice
            try t2.run()
            t2.waitUntilExit()

        } catch {
            // Silently fail
        }

        updateDeviceInfo()
    }

    @objc func runRefreshOnce() {
        runRefresh()
        updateDeviceInfo()
    }

    @objc func runNuclear() {
        let alert = NSAlert()
        alert.messageText = "Nuclear Audio Reset"
        alert.informativeText = "This will kill ALL CoreAudio client processes and restart audio daemons. Any apps playing audio will be interrupted.\n\nContinue?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset Audio")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let script = NSHomeDirectory() + "/code/_audio/mac-audioBugNuke/fix-usbc-audio-nuclear.sh"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [script]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
            } catch {
                let errAlert = NSAlert()
                errAlert.messageText = "Failed to run nuclear reset"
                errAlert.informativeText = "Make sure \(script) exists and is executable."
                errAlert.runModal()
            }
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// ── Main ──
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // No dock icon, menu bar only
app.run()
