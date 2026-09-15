import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var overlays: [ScreenOverlay] = []
    private var config: Config = ConfigStore.load()
    private var scheduleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildOverlays()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildOverlays),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🦋"
        rebuildMenu()

        scheduleNext()
    }

    @objc private func rebuildOverlays() {
        overlays = NSScreen.screens.map { ScreenOverlay(screen: $0) }
    }

    // MARK: - Scheduling

    private func scheduleNext() {
        scheduleTimer?.invalidate()
        let delay = config.randomIntervalSeconds()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.fireVisit()
            self?.scheduleNext()
        }
    }

    private func fireVisit() {
        guard !config.paused, !config.isQuietHour() else { return }
        guard let overlay = overlays.filter({ $0.isAvailable }).randomElement() else { return }
        overlay.visit(message: config.randomMessage())
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Lil Butterfly", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        let showNow = NSMenuItem(title: "Show a butterfly now", action: #selector(showNowTapped), keyEquivalent: "")
        showNow.target = self
        menu.addItem(showNow)

        let pause = NSMenuItem(
            title: config.paused ? "Resume" : "Pause",
            action: #selector(togglePauseTapped),
            keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())

        addFrequencyItem(to: menu, title: "Every 45–90 min (default)", min: 45, max: 90)
        addFrequencyItem(to: menu, title: "Every 20–40 min (more often)", min: 20, max: 40)
        addFrequencyItem(to: menu, title: "Every 2–3 hours (rare)", min: 120, max: 180)

        menu.addItem(.separator())

        let quiet = NSMenuItem(
            title: "Quiet hours \(config.quietHoursEnabled ? "(\(config.quietHoursStart):00–\(config.quietHoursEnd):00) ✓" : "(off)")",
            action: #selector(toggleQuietHoursTapped),
            keyEquivalent: ""
        )
        quiet.target = self
        menu.addItem(quiet)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitTapped), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func addFrequencyItem(to menu: NSMenu, title: String, min: Int, max: Int) {
        let item = NSMenuItem(title: title, action: #selector(frequencyTapped(_:)), keyEquivalent: "")
        item.target = self
        item.state = (config.minMinutes == min && config.maxMinutes == max) ? .on : .off
        item.representedObject = [min, max]
        menu.addItem(item)
    }

    @objc private func showNowTapped() {
        fireVisit()
    }

    @objc private func togglePauseTapped() {
        config.paused.toggle()
        ConfigStore.save(config)
        rebuildMenu()
    }

    @objc private func frequencyTapped(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [Int], pair.count == 2 else { return }
        config.minMinutes = pair[0]
        config.maxMinutes = pair[1]
        ConfigStore.save(config)
        rebuildMenu()
        scheduleNext()
    }

    @objc private func toggleQuietHoursTapped() {
        config.quietHoursEnabled.toggle()
        ConfigStore.save(config)
        rebuildMenu()
    }

    @objc private func quitTapped() {
        NSApplication.shared.terminate(nil)
    }
}
