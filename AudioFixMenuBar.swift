import Cocoa

// ─────────────────────────────────────────────────────────────
// AudioFixMenuBar — Menu bar toggle for USB-C audio refresh
//
// Compile:
//   swiftc -o AudioFixMenuBar AudioFixMenuBar.swift -framework Cocoa
//
// Run:
//   ./AudioFixMenuBar
// ─────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    var statusItem: NSStatusItem!
    var timer: Timer?
    var isActive = true

    // ── Persisted settings ──
    var refreshIntervalSeconds: TimeInterval = 120   // how often to refresh
    var switchDelayMs: Int = 20                      // how long the switch holds on internal

    let skipDevices    = ["Minifuse", "MiniFuse", "MINIFUSE"]
    let internalPrefix = "Mac"

    // UserDefaults keys
    let keyEnabledDevices  = "AudioFix.enabledDevices"
    let keyRefreshInterval = "AudioFix.refreshInterval"
    let keySwitchDelay     = "AudioFix.switchDelayMs"

    var enabledDevices: Set<String> = []

    // Preset options shown in the menu
    let refreshOptions: [(label: String, seconds: TimeInterval)] = [
        ("30 seconds",  30),
        ("1 minute",    60),
        ("2 minutes",  120),
        ("3 minutes",  180),
        ("5 minutes",  300),
        ("10 minutes", 600),
    ]
    let switchSpeedOptions: [(label: String, ms: Int)] = [
        ("10 ms",  10),
        ("20 ms",  20),
        ("50 ms",  50),
        ("100 ms", 100),
    ]

    // ─────────────────────────────────────────────────────────
    // MARK: Launch
    // ─────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ notification: Notification) {
        let d = UserDefaults.standard

        // Load enabled devices (default: empty — user picks on first run)
        if let saved = d.array(forKey: keyEnabledDevices) as? [String], !saved.isEmpty {
            enabledDevices = Set(saved)
        } else {
            enabledDevices = []
        }

        // Load refresh interval
        let savedInterval = d.double(forKey: keyRefreshInterval)
        if savedInterval > 0 { refreshIntervalSeconds = savedInterval }

        // Load switch delay
        let savedDelay = d.integer(forKey: keySwitchDelay)
        if savedDelay > 0 { switchDelayMs = savedDelay }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Order matters: build menu first so tag lookups in updateIcon() work
        buildMenu()
        updateIcon()
        startTimer()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Persistence
    // ─────────────────────────────────────────────────────────

    func saveEnabledDevices() {
        UserDefaults.standard.set(Array(enabledDevices), forKey: keyEnabledDevices)
    }

    func saveSettings() {
        UserDefaults.standard.set(refreshIntervalSeconds, forKey: keyRefreshInterval)
        UserDefaults.standard.set(switchDelayMs,          forKey: keySwitchDelay)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Menu construction
    // ─────────────────────────────────────────────────────────

    func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Toggle on/off
        let toggleItem = NSMenuItem(title: "Toggle Audio Fix", action: #selector(toggleFix), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Status line (tag 100)
        let statusLine = NSMenuItem(title: "Status: OFF", action: nil, keyEquivalent: "")
        statusLine.tag = 100
        menu.addItem(statusLine)

        // Current output line (tag 200)
        let deviceLine = NSMenuItem(title: "Output: checking...", action: nil, keyEquivalent: "")
        deviceLine.tag = 200
        menu.addItem(deviceLine)

        menu.addItem(.separator())

        // ── Target Devices submenu (tag 300) ──
        menu.addItem(makeSubmenuItem(title: "Target Devices", tag: 300))

        // ── Switch Speed submenu (tag 400) ──
        let speedParent = NSMenuItem(title: "Switch Speed", action: nil, keyEquivalent: "")
        speedParent.tag = 400
        let speedSubmenu = NSMenu()
        speedSubmenu.autoenablesItems = false
        for opt in switchSpeedOptions {
            let item = NSMenuItem(title: opt.label, action: #selector(setSwitchSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opt.ms as AnyObject
            item.state = (opt.ms == switchDelayMs) ? .on : .off
            speedSubmenu.addItem(item)
        }
        speedParent.submenu = speedSubmenu
        menu.addItem(speedParent)

        // ── Refresh Interval submenu (tag 500) ──
        let intervalParent = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        intervalParent.tag = 500
        let intervalSubmenu = NSMenu()
        intervalSubmenu.autoenablesItems = false
        for opt in refreshOptions {
            let item = NSMenuItem(title: opt.label, action: #selector(setRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opt.seconds as AnyObject
            item.state = (opt.seconds == refreshIntervalSeconds) ? .on : .off
            intervalSubmenu.addItem(item)
        }
        intervalParent.submenu = intervalSubmenu
        menu.addItem(intervalParent)

        menu.addItem(.separator())

        // Actions
        let refreshNow = NSMenuItem(title: "Refresh Audio Now", action: #selector(runRefreshOnce), keyEquivalent: "r")
        refreshNow.target = self
        menu.addItem(refreshNow)

        let nuclearItem = NSMenuItem(title: "Nuclear Reset (kills all audio clients)", action: #selector(runNuclear), keyEquivalent: "")
        nuclearItem.target = self
        menu.addItem(nuclearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit AudioFix", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func makeSubmenuItem(title: String, tag: Int) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.tag  = tag
        let sub = NSMenu()
        sub.autoenablesItems = false
        parent.submenu = sub
        return parent
    }

    // Refresh device list every time menu opens
    func menuWillOpen(_ menu: NSMenu) {
        refreshDeviceSubmenu()
        updateDeviceInfo()
    }

    func refreshDeviceSubmenu() {
        guard let menu    = statusItem.menu,
              let parent  = menu.item(withTag: 300),
              let submenu = parent.submenu else { return }

        submenu.removeAllItems()

        let external = getAllOutputDevices().filter { dev in
            !dev.hasPrefix(internalPrefix) &&
            !skipDevices.contains(where: { dev.localizedCaseInsensitiveContains($0) })
        }

        if external.isEmpty {
            let ph = NSMenuItem(title: "No external devices found", action: nil, keyEquivalent: "")
            ph.isEnabled = false
            submenu.addItem(ph)
            return
        }

        for device in external {
            let item = NSMenuItem(title: device, action: #selector(toggleDevice(_:)), keyEquivalent: "")
            item.target = self
            item.state  = enabledDevices.contains(device) ? .on : .off
            submenu.addItem(item)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Settings actions
    // ─────────────────────────────────────────────────────────

    @objc func toggleDevice(_ sender: NSMenuItem) {
        let device = sender.title
        if enabledDevices.contains(device) {
            enabledDevices.remove(device)
            sender.state = .off
        } else {
            enabledDevices.insert(device)
            sender.state = .on
        }
        saveEnabledDevices()
        updateDeviceInfo()
    }

    @objc func setSwitchSpeed(_ sender: NSMenuItem) {
        guard let ms = sender.representedObject as? Int else { return }
        switchDelayMs = ms
        saveSettings()
        // Update checkmarks in the submenu
        if let submenu = sender.menu {
            for item in submenu.items { item.state = (item.representedObject as? Int == ms) ? .on : .off }
        }
    }

    @objc func setRefreshInterval(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? TimeInterval else { return }
        refreshIntervalSeconds = secs
        saveSettings()
        // Update checkmarks in the submenu
        if let submenu = sender.menu {
            for item in submenu.items { item.state = (item.representedObject as? TimeInterval == secs) ? .on : .off }
        }
        // Restart the timer on the new interval
        if isActive { startTimer() }
        updateIcon()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Icon & status display
    // ─────────────────────────────────────────────────────────

    @objc func toggleFix() {
        isActive.toggle()
        isActive ? startTimer() : stopTimer()
        updateIcon()
    }

    func updateIcon() {
        if let button = statusItem.button {
            let symbol = isActive ? "speaker.wave.2" : "speaker.slash"
            if let img = NSImage(systemSymbolName: symbol,
                                 accessibilityDescription: isActive ? "Audio Fix: ON" : "Audio Fix: OFF") {
                img.isTemplate = true
                button.image   = img
                button.title   = ""
            }
        }
        if let menu = statusItem.menu, let line = menu.item(withTag: 100) {
            if isActive {
                let intervalLabel = refreshOptions.first(where: { $0.seconds == refreshIntervalSeconds })?.label
                    ?? "\(Int(refreshIntervalSeconds))s"
                line.title = "Status: ON — every \(intervalLabel)"
            } else {
                line.title = "Status: OFF"
            }
        }
        updateDeviceInfo()
    }

    func updateDeviceInfo() {
        guard let menu = statusItem.menu,
              let line = menu.item(withTag: 200) else { return }

        guard let device = getCurrentDevice() else {
            line.title = "Output: unknown"
            return
        }

        let isProtected = skipDevices.contains(where: { device.localizedCaseInsensitiveContains($0) })
        let isInternal  = device.hasPrefix(internalPrefix)
        let isEnabled   = enabledDevices.contains(device)

        if isProtected {
            line.title = "Output: \(device) (protected — skipping)"
        } else if isInternal {
            line.title = "Output: \(device) (internal — skipping)"
        } else if isEnabled {
            line.title = "Output: \(device) ✓ (will refresh)"
        } else {
            line.title = "Output: \(device) (not a target — skipping)"
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Timer
    // ─────────────────────────────────────────────────────────

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshIntervalSeconds, repeats: true) { [weak self] _ in
            self?.runRefresh()
        }
        runRefresh()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Audio device helpers
    // ─────────────────────────────────────────────────────────

    func switchAudioBin() -> String? {
        ["/opt/homebrew/bin/SwitchAudioSource", "/usr/local/bin/SwitchAudioSource"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func getCurrentDevice() -> String? {
        guard let bin = switchAudioBin() else { return nil }
        let task = Process(); let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: bin)
        task.arguments     = ["-c", "-t", "output"]
        task.standardOutput = pipe
        task.standardError  = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func getAllOutputDevices() -> [String] {
        guard let bin = switchAudioBin() else { return [] }
        let task = Process(); let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: bin)
        task.arguments     = ["-a", "-t", "output"]
        task.standardOutput = pipe
        task.standardError  = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        return (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Volume helpers (silent mute around the switch)
    // ─────────────────────────────────────────────────────────

    func getVolumeState() -> (volume: Int, isMuted: Bool) {
        let task = Process(); let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e",
            "set s to get volume settings\nreturn (output volume of s) & \",\" & (output muted of s)"]
        task.standardOutput = pipe
        task.standardError  = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
        let raw   = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = raw.components(separatedBy: ",")
        return (Int(parts.first ?? "50") ?? 50,
                parts.last?.lowercased().contains("true") ?? false)
    }

    func setMuted(_ muted: Bool, volume: Int? = nil) {
        var script = "set volume output muted \(muted ? "true" : "false")"
        if let v = volume { script += "\nset volume output volume \(v)" }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments     = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError  = FileHandle.nullDevice
        try? task.run(); task.waitUntilExit()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Refresh logic
    // ─────────────────────────────────────────────────────────

    func runRefresh() {
        guard let current = getCurrentDevice() else { return }

        if current.hasPrefix(internalPrefix) { return }
        if skipDevices.contains(where: { current.localizedCaseInsensitiveContains($0) }) { return }
        if !enabledDevices.contains(current) { return }

        guard let switchBin      = switchAudioBin(),
              let internalDevice = getAllOutputDevices().first(where: { $0.hasPrefix(internalPrefix) })
        else { return }

        do {
            // Mute so the switch is completely silent
            let (originalVolume, wasAlreadyMuted) = getVolumeState()
            if !wasAlreadyMuted {
                setMuted(true)
                usleep(5_000)   // 5ms — let mute settle
            }

            // Switch → internal
            let t1 = Process()
            t1.executableURL = URL(fileURLWithPath: switchBin)
            t1.arguments     = ["-t", "output", "-s", internalDevice]
            t1.standardOutput = FileHandle.nullDevice
            t1.standardError  = FileHandle.nullDevice
            try t1.run(); t1.waitUntilExit()

            // Hold on internal for the user-configured duration
            usleep(UInt32(switchDelayMs * 1_000))

            // Switch → back to original
            let t2 = Process()
            t2.executableURL = URL(fileURLWithPath: switchBin)
            t2.arguments     = ["-t", "output", "-s", current]
            t2.standardOutput = FileHandle.nullDevice
            t2.standardError  = FileHandle.nullDevice
            try t2.run(); t2.waitUntilExit()

            // Restore volume
            if !wasAlreadyMuted {
                usleep(10_000)   // 10ms — let switch complete before unmuting
                setMuted(false, volume: originalVolume)
            }
        } catch { }

        updateDeviceInfo()
    }

    @objc func runRefreshOnce() {
        runRefresh()
        updateDeviceInfo()
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Nuclear reset
    // ─────────────────────────────────────────────────────────

    @objc func runNuclear() {
        let alert = NSAlert()
        alert.messageText     = "Nuclear Audio Reset"
        alert.informativeText = "This will kill ALL CoreAudio client processes and restart audio daemons. Any apps playing audio will be interrupted.\n\nContinue?"
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Reset Audio")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let script = NSHomeDirectory() + "/code/_audio/mac-audioBugNuke/fix-usbc-audio-nuclear.sh"
        let task   = Process()
        task.executableURL  = URL(fileURLWithPath: "/bin/bash")
        task.arguments      = [script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError  = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            let err = NSAlert()
            err.messageText     = "Failed to run nuclear reset"
            err.informativeText = "Make sure \(script) exists and is executable."
            err.runModal()
        }
    }

    @objc func quitApp() { NSApp.terminate(nil) }
}

// ── Main ──
let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
