import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var overlays: [ScreenOverlay] = []
    private var dockedOverlay: DockedOverlay?
    private var kaviiRevealOverlay: KaviiRevealOverlay?
    private var welcomeOverlay: WelcomeOverlay?
    private var config: Config = ConfigStore.load()
    private var scheduleTimer: Timer?
    private var nextFireDate: Date?
    private let meetingCalendar = MeetingCalendar()
    private var meetingReminderTimer: Timer?
    private var remindedMeetingID: String?
    private var latestRelease: GitHubRelease?
    private lazy var updateChecker = UpdateChecker(currentVersion: installedVersion)
    private lazy var regularStatusIcon = makeStatusIcon(updateAvailable: false)
    private lazy var updateStatusIcon = makeStatusIcon(updateAvailable: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        rebuildOverlays()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildOverlays), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusIcon(updateAvailable: false)
        let menu = NSMenu(); menu.delegate = self; statusItem.menu = menu
        rebuildMenu(menu); scheduleNext(); updateMeetingReminderTimer()
        checkForUpdates(showResult: false)
        // A dedicated centered moment — a ring of butterflies bringing the
        // message, not an ordinary edge-in roaming visit — rather than
        // routing through fireVisit's quiet-hours/pause gating, since this
        // first impression is meant to always play, guaranteed, exactly
        // once per install.
        if !config.hasStarted, let screen = preferredScreen {
            welcomeOverlay = WelcomeOverlay(screen: screen)
            welcomeOverlay?.show(message: Self.welcomeMessage, pinnedAssetIndex: config.pinnedAssetIndex)
            config.hasStarted = true
            ConfigStore.save(config)
        }
    }

    @objc private func rebuildOverlays() {
        overlays.forEach { $0.stop() }
        overlays.removeAll()
        dockedOverlay?.stop()
        dockedOverlay = nil
        if config.mode == "docked" {
            if let main = preferredScreen {
                let docked = DockedOverlay(
                    screen: main,
                    edge: ScreenEdge(rawValue: config.dockEdge) ?? .right,
                    positionFraction: config.dockPositionFraction
                )
                docked.onPositionChanged = { [weak self] fraction in
                    guard let self else { return }
                    self.config.dockPositionFraction = fraction
                    ConfigStore.save(self.config)
                }
                docked.parkNow(pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: ButterflySize.width(forIndex: config.butterflySizeIndex)); dockedOverlay = docked
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

    /// Shown once, in place of the usual random pool, on the very first
    /// visit after a fresh install — a proper introduction rather than
    /// whatever the dice happened to land on.
    private static let welcomeMessage = "Hi there — just a gentle reminder to pause sometimes. I know you're hardworking and dedicated, but you deserve rest too. Made with a lot of care, just for you 🦋"

    @discardableResult
    private func fireVisit(manualOverride: Bool = false) -> Bool {
        guard manualOverride || !config.paused else { return false }
        guard manualOverride || !config.suppressDuringMeetings ||
                (!MeetingDetector.isMeetingAppActive && !meetingCalendar.isVideoMeetingActive()) else { return false }
        // Quiet hours are gentle mode, not a hard stop: randomMessage
        // returns nil most of the time during that window instead (see its
        // doc comment), so a scheduled cycle can land here and legitimately
        // decide to stay silent.
        guard let message = config.randomMessage(manualOverride: manualOverride) else { return false }
        let displayWidth = ButterflySize.width(forIndex: config.butterflySizeIndex)
        if config.mode == "docked" {
            guard let dockedOverlay else { return false }
            dockedOverlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: config.restingSeconds)
            return true
        }
        guard let overlay = overlays.filter({ $0.isAvailable }).randomElement() else { return false }
        overlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: config.restingSeconds)
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu(menu) }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let headerItem = NSMenuItem(title: "Butterfly", action: nil, keyEquivalent: "")
        headerItem.image = regularStatusIcon
        menu.addItem(headerItem)
        menu.addItem(.separator())

        let countdown: String
        if config.paused { countdown = "Paused" }
        else if config.isQuietHour() { countdown = "Quiet time" }
        else if let nextFireDate { countdown = "Next · ~\(IntervalSliderView.formatted(max(0, nextFireDate.timeIntervalSinceNow)))" }
        else { countdown = "Ready" }
        let countdownItem = NSMenuItem(title: countdown, action: nil, keyEquivalent: "")
        countdownItem.image = symbolImage("clock")
        countdownItem.isEnabled = false
        menu.addItem(countdownItem)

        if let latestRelease {
            addItem(to: menu, title: "Update · v\(latestRelease.version)", action: #selector(updateTapped), symbol: "arrow.down.circle.fill")
        } else {
            addItem(to: menu, title: "Check for Updates…", action: #selector(checkForUpdatesTapped), symbol: "arrow.triangle.2.circlepath")
        }
        addItem(to: menu, title: "Show Butterfly", action: #selector(showNowTapped), symbol: "sparkles")
        addItem(
            to: menu,
            title: config.paused ? "Resume Visits" : "Pause Visits",
            action: #selector(togglePauseTapped),
            symbol: config.paused ? "play.circle.fill" : "pause.circle.fill"
        )
        menu.addItem(.separator())

        let frequencyMenu = NSMenu(title: "Visit Timing")
        frequencyMenu.minimumWidth = 270
        addFrequencyItem(to: frequencyMenu, title: "Often · 20–40 min", min: 20, max: 40)
        addFrequencyItem(to: frequencyMenu, title: "Gentle · 45–90 min", min: 45, max: 90)
        addFrequencyItem(to: frequencyMenu, title: "Rare · 2–3 hr", min: 120, max: 180)
        frequencyMenu.addItem(.separator())
        let current = config.customIntervalSeconds ?? Double(config.minMinutes) * 60
        let slider = IntervalSliderView(currentSeconds: current, target: self, action: #selector(intervalSliderMoved(_:)))
        let sliderItem = NSMenuItem()
        sliderItem.view = slider
        frequencyMenu.addItem(sliderItem)
        let frequencyItem = NSMenuItem(title: "Visits · \(frequencySummary)", action: nil, keyEquivalent: "")
        frequencyItem.image = symbolImage("clock")
        frequencyItem.submenu = frequencyMenu
        menu.addItem(frequencyItem)

        let movementMenu = NSMenu(title: "Movement")
        movementMenu.minimumWidth = 230
        addModeItem(to: movementMenu, title: "Roam", mode: "roaming", symbol: "paperplane")
        addModeItem(to: movementMenu, title: "Dock", mode: "docked", symbol: "pin.fill")
        movementMenu.addItem(.separator())
        let edgeMenu = NSMenu()
        for edge in ScreenEdge.allCases {
            let item = NSMenuItem(title: edge.rawValue.capitalized, action: #selector(dockEdgeTapped(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = edge.rawValue
            item.image = symbolImage(edgeSymbol(for: edge))
            item.state = config.dockEdge == edge.rawValue ? .on : .off
            edgeMenu.addItem(item)
        }
        let edgeItem = NSMenuItem(title: "Dock Edge", action: nil, keyEquivalent: "")
        edgeItem.image = symbolImage("square.dashed")
        edgeItem.submenu = edgeMenu
        movementMenu.addItem(edgeItem)
        let dragHint = NSMenuItem(title: "Drag Butterfly to Move", action: nil, keyEquivalent: "")
        dragHint.image = symbolImage("hand.draw")
        dragHint.isEnabled = false
        movementMenu.addItem(dragHint)
        let movementItem = NSMenuItem(
            title: config.mode == "docked" ? "Movement · Docked" : "Movement · Roaming",
            action: nil,
            keyEquivalent: ""
        )
        movementItem.image = symbolImage(config.mode == "docked" ? "pin.fill" : "paperplane")
        movementItem.submenu = movementMenu
        menu.addItem(movementItem)

        let appearanceMenu = NSMenu(title: "Butterfly")
        appearanceMenu.minimumWidth = 280
        addAssetItem(to: appearanceMenu, title: "Surprise Me", index: -1)
        for index in WingAssets.names().indices {
            addAssetItem(to: appearanceMenu, title: "Design \(index + 1)", index: index)
        }
        appearanceMenu.addItem(.separator())
        let sizeSlider = SizeSliderView(currentIndex: config.butterflySizeIndex, target: self, action: #selector(sizeSliderMoved(_:)))
        let sizeSliderItem = NSMenuItem()
        sizeSliderItem.view = sizeSlider
        appearanceMenu.addItem(sizeSliderItem)
        let appearanceItem = NSMenuItem(title: butterflySummary, action: nil, keyEquivalent: "")
        appearanceItem.image = WingAssets.menuImage(at: config.pinnedAssetIndex ?? 0)
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        let messageMenu = NSMenu(title: "Message")
        messageMenu.minimumWidth = 270
        let restingSlider = RestingSliderView(currentSeconds: config.restingSeconds, target: self, action: #selector(restingSliderMoved(_:)))
        let restingSliderItem = NSMenuItem()
        restingSliderItem.view = restingSlider
        messageMenu.addItem(restingSliderItem)
        let messageItem = NSMenuItem(title: "Message · \(RestingSliderView.formatted(config.restingSeconds))", action: nil, keyEquivalent: "")
        messageItem.image = symbolImage("text.bubble")
        messageItem.submenu = messageMenu
        menu.addItem(messageItem)
        menu.addItem(.separator())

        addItem(to: menu, title: "Kavii", action: #selector(kaviiTapped), symbol: "wand.and.stars")
        menu.addItem(.separator())

        addToggle(
            to: menu,
            title: "Quiet Hours",
            detail: "\(config.quietHoursStart):00–\(config.quietHoursEnd):00",
            symbol: "moon.stars",
            isOn: config.quietHoursEnabled,
            action: #selector(quietHoursSwitchChanged(_:))
        )
        addToggle(
            to: menu,
            title: "Hide During Meetings",
            detail: "Zoom · Teams · Meet",
            symbol: "video.slash",
            isOn: config.suppressDuringMeetings,
            action: #selector(meetingSuppressionSwitchChanged(_:))
        )
        addToggle(
            to: menu,
            title: "Meeting Reminder",
            detail: "15 min before",
            symbol: "bell",
            isOn: config.meetingReminderEnabled,
            action: #selector(meetingReminderSwitchChanged(_:))
        )
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit Butterfly", action: #selector(quitTapped), keyEquivalent: "q", symbol: "power")
    }

    @discardableResult
    private func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        if let symbol { item.image = symbolImage(symbol) }
        menu.addItem(item)
        return item
    }

    private func addModeItem(to menu: NSMenu, title: String, mode: String, symbol: String) {
        let item = NSMenuItem(title: title, action: #selector(modeTapped(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = mode
        item.image = symbolImage(symbol)
        item.state = config.mode == mode ? .on : .off
        menu.addItem(item)
    }

    private func addToggle(
        to menu: NSMenu,
        title: String,
        detail: String,
        symbol: String,
        isOn: Bool,
        action: Selector
    ) {
        let item = NSMenuItem()
        item.view = MenuToggleView(
            title: title,
            detail: detail,
            symbol: symbol,
            isOn: isOn,
            target: self,
            action: action
        )
        menu.addItem(item)
    }

    private func addAssetItem(to menu: NSMenu, title: String, index: Int) {
        let item = NSMenuItem(title: title, action: #selector(assetTapped(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = index
        item.image = index == -1 ? symbolImage("sparkles") : WingAssets.menuImage(at: index)
        item.state = index == -1 ? (config.pinnedAssetIndex == nil ? .on : .off) : (config.pinnedAssetIndex == index ? .on : .off)
        menu.addItem(item)
    }

    private func addFrequencyItem(to menu: NSMenu, title: String, min: Int, max: Int) {
        let item = NSMenuItem(title: title, action: #selector(frequencyTapped(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = [min, max]
        item.image = symbolImage(min < 45 ? "hare" : (min >= 120 ? "tortoise" : "clock"))
        item.state = config.customIntervalSeconds == nil && config.minMinutes == min && config.maxMinutes == max ? .on : .off
        menu.addItem(item)
    }

    private var frequencySummary: String {
        if let custom = config.customIntervalSeconds {
            return IntervalSliderView.formatted(custom)
        }
        let minimum = IntervalSliderView.formatted(Double(config.minMinutes) * 60)
        let maximum = IntervalSliderView.formatted(Double(config.maxMinutes) * 60)
        return "\(minimum)–\(maximum)"
    }

    private var butterflySummary: String {
        guard let index = config.pinnedAssetIndex else { return "Butterfly · Surprise" }
        return "Butterfly · Design \(index + 1)"
    }

    private func symbolImage(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let configured = image.withSymbolConfiguration(configuration) ?? image
        configured.isTemplate = true
        return configured
    }

    private func edgeSymbol(for edge: ScreenEdge) -> String {
        switch edge {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .top: return "arrow.up"
        case .bottom: return "arrow.down"
        }
    }

    @objc private func showNowTapped() { _ = fireVisit(manualOverride: true) }
    @objc private func checkForUpdatesTapped() { checkForUpdates(showResult: true) }
    @objc private func updateTapped() {
        guard let latestRelease else { return }
        NSWorkspace.shared.open(latestRelease.htmlURL)
    }

    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private func configureStatusIcon(updateAvailable: Bool) {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = updateAvailable ? updateStatusIcon : regularStatusIcon
        button.imagePosition = .imageOnly
        button.toolTip = updateAvailable ? "Butterfly — update available" : "Butterfly"
        button.setAccessibilityLabel(updateAvailable ? "Butterfly, update available" : "Butterfly")
    }

    private func makeStatusIcon(updateAvailable: Bool) -> NSImage {
        let canvasSize = NSSize(width: 20, height: 18)
        guard let url = Bundle.module.url(forResource: "ICON", withExtension: "svg"),
              let source = NSImage(contentsOf: url) else {
            let fallback = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Butterfly") ?? NSImage(size: canvasSize)
            fallback.size = canvasSize
            fallback.isTemplate = true
            return fallback
        }

        let sourceAspect = source.size.width / max(source.size.height, 1)
        let artworkHeight: CGFloat = 14
        let artworkWidth = min(18, artworkHeight * sourceAspect)
        let artworkRect = NSRect(
            x: (canvasSize.width - artworkWidth) / 2,
            y: (canvasSize.height - artworkHeight) / 2,
            width: artworkWidth,
            height: artworkHeight
        )

        let icon = NSImage(size: canvasSize, flipped: false) { _ in
            source.draw(in: artworkRect, from: .zero, operation: .sourceOver, fraction: 1)
            if updateAvailable {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 15.5, y: 13.5, width: 4, height: 4)).fill()
            }
            return true
        }
        icon.isTemplate = true
        icon.accessibilityDescription = updateAvailable ? "Butterfly, update available" : "Butterfly"
        return icon
    }

    private func checkForUpdates(showResult: Bool) {
        updateChecker.check { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let release):
                    self.latestRelease = release
                    self.configureStatusIcon(updateAvailable: release != nil)
                    if let menu = self.statusItem?.menu { self.rebuildMenu(menu) }
                    if showResult {
                        if let release {
                            let alert = NSAlert()
                            alert.messageText = "A new Butterfly is ready"
                            alert.informativeText = "Version \(release.version) is available. Open the download page to install it."
                            alert.addButton(withTitle: "Open Download Page")
                            alert.addButton(withTitle: "Later")
                            if alert.runModal() == .alertFirstButtonReturn {
                                NSWorkspace.shared.open(release.htmlURL)
                            }
                        } else {
                            self.showUpdateMessage("Butterfly is up to date.")
                        }
                    }
                case .failure(let error) where showResult:
                    self.showUpdateMessage("Could not check for updates.\n\(error.localizedDescription)")
                case .failure:
                    break
                }
            }
        }
    }

    private func showUpdateMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func togglePauseTapped() {
        let wasPaused = config.paused
        config.paused.toggle()
        ConfigStore.save(config)
        if wasPaused && !config.paused {
            fireVisit()
            scheduleNext()
        }
    }
    @objc private func frequencyTapped(_ sender: NSMenuItem) { guard let pair = sender.representedObject as? [Int], pair.count == 2 else { return }; config.minMinutes = pair[0]; config.maxMinutes = pair[1]; config.customIntervalSeconds = nil; ConfigStore.save(config); scheduleNext() }
    @objc private func intervalSliderMoved(_ sender: NSSlider) { guard let view = sender.superview as? IntervalSliderView else { return }; config.customIntervalSeconds = view.sliderMoved(); ConfigStore.save(config); scheduleNext() }
    @objc private func sizeSliderMoved(_ sender: NSSlider) { guard let view = sender.superview as? SizeSliderView else { return }; config.butterflySizeIndex = view.sliderMoved(); ConfigStore.save(config) }
    @objc private func restingSliderMoved(_ sender: NSSlider) { guard let view = sender.superview as? RestingSliderView else { return }; config.restingSeconds = view.sliderMoved(); ConfigStore.save(config) }
    @objc private func modeTapped(_ sender: NSMenuItem) { guard let mode = sender.representedObject as? String, mode != config.mode else { return }; config.mode = mode; ConfigStore.save(config); rebuildOverlays() }
    @objc private func dockEdgeTapped(_ sender: NSMenuItem) { guard let raw = sender.representedObject as? String, let edge = ScreenEdge(rawValue: raw) else { return }; config.dockEdge = raw; config.dockPositionFraction = nil; ConfigStore.save(config); dockedOverlay?.updateEdge(edge, positionFraction: nil) }
    @objc private func assetTapped(_ sender: NSMenuItem) { guard let index = sender.representedObject as? Int else { return }; config.pinnedAssetIndex = index == -1 ? nil : index; ConfigStore.save(config) }

    @objc private func quietHoursSwitchChanged(_ sender: NSSwitch) {
        config.quietHoursEnabled = sender.state == .on
        ConfigStore.save(config)
    }

    @objc private func meetingSuppressionSwitchChanged(_ sender: NSSwitch) {
        config.suppressDuringMeetings = sender.state == .on
        ConfigStore.save(config)
    }

    @objc private func meetingReminderSwitchChanged(_ sender: NSSwitch) {
        config.meetingReminderEnabled = sender.state == .on
        ConfigStore.save(config)
        updateMeetingReminderTimer()
    }

    @objc private func kaviiTapped() {
        guard let screen = preferredScreen else { return }
        if kaviiRevealOverlay == nil { kaviiRevealOverlay = KaviiRevealOverlay(screen: screen) }
        kaviiRevealOverlay?.show()
    }

    /// Menu-bar apps do not always have a key window, so NSScreen.main can be
    /// nil. The first screen is the reliable fallback for docked/reveal UI.
    private var preferredScreen: NSScreen? {
        NSScreen.main ?? NSScreen.screens.first
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
