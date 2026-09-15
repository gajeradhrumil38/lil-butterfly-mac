import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlays: [ScreenOverlay] = []
    private var dockedOverlay: DockedOverlay?
    private var config: Config = ConfigStore.load()
    private var scheduleTimer: Timer?
    private var nextFireDate: Date?
    private let meetingCalendar = MeetingCalendar()
    private var meetingReminderTimer: Timer?
    private var remindedMeetingID: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildOverlays()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildOverlays), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🦋"
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        rebuildMenu(menu); scheduleNext(); updateMeetingReminderTimer()
    }

    @objc private func rebuildOverlays() {
        dockedOverlay?.stop()
        dockedOverlay = nil
        if config.mode == "docked" {
            overlays = []
            if let main = NSScreen.main {
                let docked = DockedOverlay(screen: main, edge: ScreenEdge(rawValue: config.dockEdge) ?? .right)
                docked.parkNow(pinnedAssetIndex: config.pinnedAssetIndex); dockedOverlay = docked
            }
        } else {
            overlays = NSScreen.screens.map { ScreenOverlay(screen: $0) }
        }
    }

    private func scheduleNext() {
        scheduleTimer?.invalidate()
        let delay = config.randomIntervalSeconds(); nextFireDate = Date().addingTimeInterval(delay)
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.fireVisit(); self?.scheduleNext() }
    }

    private func fireVisit() {
        guard !config.paused, !config.isQuietHour() else { return }
        guard !config.suppressDuringMeetings ||
                (!MeetingDetector.isMeetingAppActive && !meetingCalendar.isVideoMeetingActive()) else { return }
        let message = config.randomMessage()
        if config.mode == "docked" { dockedOverlay?.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex) }
        else if let overlay = overlays.filter({ $0.isAvailable }).randomElement() { overlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "Lil Butterfly", action: nil, keyEquivalent: "")); menu.addItem(.separator())
        let countdown: String
        if config.paused { countdown = "Paused" }
        else if config.isQuietHour() { countdown = "Quiet hours" }
        else if let nextFireDate { countdown = "Next visit in ~\(IntervalSliderView.formatted(max(0, nextFireDate.timeIntervalSinceNow)))" }
        else { countdown = "Next visit: not scheduled" }
        let countdownItem = NSMenuItem(title: countdown, action: nil, keyEquivalent: ""); countdownItem.isEnabled = false; menu.addItem(countdownItem)
        addItem(to: menu, title: "Show a butterfly now", action: #selector(showNowTapped))
        addItem(to: menu, title: config.paused ? "Resume" : "Pause", action: #selector(togglePauseTapped)); menu.addItem(.separator())
        addFrequencyItem(to: menu, title: "Every 45–90 min (default)", min: 45, max: 90)
        addFrequencyItem(to: menu, title: "Every 20–40 min (more often)", min: 20, max: 40)
        addFrequencyItem(to: menu, title: "Every 2–3 hours (rare)", min: 120, max: 180)
        let current = config.customIntervalSeconds ?? Double(config.minMinutes) * 60
        let slider = IntervalSliderView(currentSeconds: current, target: self, action: #selector(intervalSliderMoved(_:)))
        let sliderItem = NSMenuItem(); sliderItem.view = slider; menu.addItem(sliderItem); menu.addItem(.separator())
        addModeItem(to: menu, title: "Roaming", mode: "roaming"); addModeItem(to: menu, title: "Docked", mode: "docked")
        let edgeMenu = NSMenu()
        for edge in ScreenEdge.allCases {
            let item = NSMenuItem(title: edge.rawValue.capitalized, action: #selector(dockEdgeTapped(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = edge.rawValue; item.state = config.dockEdge == edge.rawValue ? .on : .off; edgeMenu.addItem(item)
        }
        let edgeItem = NSMenuItem(title: "Dock Edge", action: nil, keyEquivalent: ""); edgeItem.submenu = edgeMenu; menu.addItem(edgeItem)
        let assetMenu = NSMenu(); addAssetItem(to: assetMenu, title: "Random (default)", index: -1)
        for (index, name) in WingAssets.names().enumerated() { addAssetItem(to: assetMenu, title: name, index: index) }
        let assetItem = NSMenuItem(title: "Butterfly Design", action: nil, keyEquivalent: ""); assetItem.submenu = assetMenu; menu.addItem(assetItem); menu.addItem(.separator())
        addItem(to: menu, title: "Quiet hours \(config.quietHoursEnabled ? "(\(config.quietHoursStart):00–\(config.quietHoursEnd):00) ✓" : "(off)")", action: #selector(toggleQuietHoursTapped)); menu.addItem(.separator())
        addItem(to: menu, title: "Hide during Zoom / Teams / Meet \(config.suppressDuringMeetings ? "✓" : "(off)")", action: #selector(toggleMeetingSuppressionTapped))
        addItem(to: menu, title: "Meeting reminder (15 min before) \(config.meetingReminderEnabled ? "✓" : "(off)")", action: #selector(toggleMeetingReminderTapped))
        let meetingNote = NSMenuItem(title: "Google Meet in Chrome/Safari: use Pause", action: nil, keyEquivalent: "")
        meetingNote.isEnabled = false
        menu.addItem(meetingNote)
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit", action: #selector(quitTapped), keyEquivalent: "q")
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector, keyEquivalent: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent); item.target = self; menu.addItem(item)
    }
    private func addModeItem(to menu: NSMenu, title: String, mode: String) {
        let item = NSMenuItem(title: title, action: #selector(modeTapped(_:)), keyEquivalent: ""); item.target = self; item.representedObject = mode; item.state = config.mode == mode ? .on : .off; menu.addItem(item)
    }
    private func addAssetItem(to menu: NSMenu, title: String, index: Int) {
        let item = NSMenuItem(title: title, action: #selector(assetTapped(_:)), keyEquivalent: ""); item.target = self; item.representedObject = index; item.state = index == -1 ? (config.pinnedAssetIndex == nil ? .on : .off) : (config.pinnedAssetIndex == index ? .on : .off); menu.addItem(item)
    }
    private func addFrequencyItem(to menu: NSMenu, title: String, min: Int, max: Int) {
        let item = NSMenuItem(title: title, action: #selector(frequencyTapped(_:)), keyEquivalent: ""); item.target = self; item.representedObject = [min, max]; item.state = config.customIntervalSeconds == nil && config.minMinutes == min && config.maxMinutes == max ? .on : .off; menu.addItem(item)
    }

    @objc private func showNowTapped() { fireVisit() }
    @objc private func togglePauseTapped() { config.paused.toggle(); ConfigStore.save(config) }
    @objc private func frequencyTapped(_ sender: NSMenuItem) { guard let pair = sender.representedObject as? [Int], pair.count == 2 else { return }; config.minMinutes = pair[0]; config.maxMinutes = pair[1]; config.customIntervalSeconds = nil; ConfigStore.save(config); scheduleNext() }
    @objc private func intervalSliderMoved(_ sender: NSSlider) { guard let view = sender.superview as? IntervalSliderView else { return }; config.customIntervalSeconds = view.sliderMoved(); ConfigStore.save(config); scheduleNext() }
    @objc private func modeTapped(_ sender: NSMenuItem) { guard let mode = sender.representedObject as? String, mode != config.mode else { return }; config.mode = mode; ConfigStore.save(config); rebuildOverlays() }
    @objc private func dockEdgeTapped(_ sender: NSMenuItem) { guard let raw = sender.representedObject as? String, let edge = ScreenEdge(rawValue: raw) else { return }; config.dockEdge = raw; ConfigStore.save(config); dockedOverlay?.updateEdge(edge) }
    @objc private func assetTapped(_ sender: NSMenuItem) { guard let index = sender.representedObject as? Int else { return }; config.pinnedAssetIndex = index == -1 ? nil : index; ConfigStore.save(config) }
    @objc private func toggleQuietHoursTapped() { config.quietHoursEnabled.toggle(); ConfigStore.save(config) }
    @objc private func toggleMeetingSuppressionTapped() { config.suppressDuringMeetings.toggle(); ConfigStore.save(config) }
    @objc private func toggleMeetingReminderTapped() {
        config.meetingReminderEnabled.toggle()
        ConfigStore.save(config)
        updateMeetingReminderTimer()
    }

    private func updateMeetingReminderTimer() {
        meetingReminderTimer?.invalidate()
        meetingReminderTimer = nil
        remindedMeetingID = nil
        guard config.meetingReminderEnabled else { return }
        meetingCalendar.requestAccess { [weak self] granted in
            guard let self, granted else { return }
            self.meetingReminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.checkMeetingReminder()
            }
            self.checkMeetingReminder()
        }
    }

    private func checkMeetingReminder() {
        guard config.meetingReminderEnabled,
              let meeting = meetingCalendar.nextVideoMeeting() else { return }
        let secondsUntilMeeting = meeting.startDate.timeIntervalSinceNow
        let reminderWindow = Double(config.meetingReminderMinutes * 60)
        guard secondsUntilMeeting > 0, secondsUntilMeeting <= reminderWindow,
              remindedMeetingID != meeting.identifier else { return }
        remindedMeetingID = meeting.identifier
        fireVisit()
    }
    @objc private func quitTapped() { NSApplication.shared.terminate(nil) }
}
