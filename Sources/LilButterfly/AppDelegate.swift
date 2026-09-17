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
    private let activityTracker = ActivityTracker()
    private var meetingReminderTimer: Timer?
    private var remindedMeetingID: String?
    private var latestRelease: GitHubRelease?
    private var isUpdating = false
    /// Which release version the update reminder has already been folded
    /// into a visit for — so it surfaces once per newly-detected version,
    /// on the next message that would have happened anyway, rather than
    /// nagging on every single visit.
    private var updateReminderShownForVersion: String?
    private lazy var updateChecker = UpdateChecker(currentVersion: installedVersion)
    private lazy var selfUpdater = SelfUpdater()
    private lazy var regularStatusIcon = makeStatusIcon(updateAvailable: false)
    private lazy var updateStatusIcon = makeStatusIcon(updateAvailable: true)

    func applicationDidFinishLaunching(_ notification: Notification) {
        activityTracker.start()
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
                // Configs saved before top/bottom docking was removed can
                // still have one of those on disk — fall back to right
                // rather than letting a stale value dock somewhere the
                // menu no longer offers.
                var edge = ScreenEdge(rawValue: config.dockEdge) ?? .right
                if edge != .left && edge != .right {
                    edge = .right
                    config.dockEdge = edge.rawValue
                    ConfigStore.save(config)
                }
                let docked = DockedOverlay(
                    screen: main,
                    edge: edge,
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
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.attemptScheduledVisit() }
    }

    /// A scheduled visit (unlike a manual "Show Butterfly Now") only makes
    /// sense if someone's actually there to see it — showing a message to
    /// an empty desk, or one that's gone stale by the time the user is
    /// back, isn't caring, it's just wasted. Recheck shortly instead of
    /// firing blind or giving up on this cycle entirely; there's no retry
    /// cap since however long the user's away, this just waits them out.
    private func attemptScheduledVisit() {
        guard !activityTracker.isIdle else {
            scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in self?.attemptScheduledVisit() }
            return
        }
        _ = fireVisit()
        scheduleNext()
    }

    /// Shown once, in place of the usual random pool, on the very first
    /// visit after a fresh install — a proper introduction rather than
    /// whatever the dice happened to land on.
    private static let welcomeMessage = "Hi there — just a gentle reminder to pause sometimes. I know you're hardworking and dedicated, but you deserve rest too. Made with a lot of care, just for you 🦋"

    @discardableResult
    private func fireVisit(manualOverride: Bool = false, forcedCheckIn: CheckInContent? = nil) -> Bool {
        guard manualOverride || !config.paused else { return false }
        guard manualOverride || !config.suppressDuringMeetings ||
                (!MeetingDetector.isMeetingAppActive && !meetingCalendar.isVideoMeetingActive()) else { return false }

        // Not a separate, immediate notification — just folded into
        // whichever visit was about to happen anyway (scheduled or manual),
        // once per newly-detected version, so it stays quiet and low-key
        // rather than interrupting on its own.
        let pendingUpdate = latestRelease.flatMap { release in
            updateReminderShownForVersion == release.version ? nil : release
        }
        let message: String
        var onTapped: (() -> Void)?
        var actionTitle: String?
        var checkIn: CheckInContent?
        // A button needs real time to notice and aim for, not the few
        // seconds a one-line message normally gets — longer than whatever
        // the user configured, specifically for this message.
        var restingSeconds = config.restingSeconds
        // Set only when a check-in below was chosen for an activity
        // reason rather than the plain random roll — marked "shown" after
        // the dispatched check further down, same as the update reminder,
        // so a failed dispatch (no available overlay) doesn't burn it.
        var markActivityNudgeShown: (() -> Void)?
        if let forcedCheckIn {
            checkIn = forcedCheckIn
            message = forcedCheckIn.question
            restingSeconds = max(config.restingSeconds, 14)
        } else if let pendingUpdate {
            message = "A new Butterfly (v\(pendingUpdate.version)) is ready."
            actionTitle = "Update Now"
            onTapped = { [weak self] in self?.startSelfUpdate(release: pendingUpdate) }
            restingSeconds = max(config.restingSeconds, 14)
        } else if activityTracker.continuousActiveSeconds >= ActivityTracker.longSessionThreshold
                    && !activityTracker.hasShownLongSessionNudgeThisSession {
            // A real uninterrupted multi-hour stretch gets the stronger,
            // zero-tap reset rather than competing with the plain random
            // check-in roll — earned by actual screen time, not chance.
            let content = CheckInContent.make(style: .breatheWithMe)
            checkIn = content
            message = content.question
            restingSeconds = max(config.restingSeconds, 14)
            markActivityNudgeShown = { [weak self] in self?.activityTracker.markLongSessionNudgeShown() }
        } else if activityTracker.secondsSinceLastEyeRestPrompt >= ActivityTracker.eyeRestInterval {
            // The eye-rest check-in fires from real continuous screen time
            // (tracked by ActivityTracker, default every 2 hours — see
            // ActivityTracker.eyeRestInterval), not a flat random chance
            // shared with every other check-in style. The break it paces
            // is still the real 20 seconds the 20-20-20 rule calls for.
            let content = CheckInContent.make(style: .eyeRestReset)
            checkIn = content
            message = content.question
            restingSeconds = max(config.restingSeconds, 14)
            markActivityNudgeShown = { [weak self] in self?.activityTracker.markEyeRestShown() }
        } else if Double.random(in: 0..<1) < (1.0 / 12.0) {
            // Rare, occasional — folded into a visit that was going to
            // happen anyway (scheduled or manual), same as the update
            // reminder, never a separate interruption. The update reminder
            // above always wins when both are pending — it's guaranteed-
            // once-per-version and functional; a check-in is discretionary
            // and can simply wait for the next eligible visit.
            let content = CheckInContent.random()
            checkIn = content
            message = content.question
            restingSeconds = max(config.restingSeconds, 14)
        } else {
            // Quiet hours are gentle mode, not a hard stop: randomMessage
            // returns nil most of the time during that window instead (see
            // its doc comment), so a scheduled cycle can land here and
            // legitimately decide to stay silent.
            guard let randomMessage = config.randomMessage(manualOverride: manualOverride) else { return false }
            message = randomMessage
        }

        let displayWidth = ButterflySize.width(forIndex: config.butterflySizeIndex)
        let dispatched: Bool
        if config.mode == "docked" {
            if let dockedOverlay {
                dockedOverlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: restingSeconds, actionTitle: actionTitle, onTapped: onTapped, checkIn: checkIn)
                dispatched = true
            } else {
                dispatched = false
            }
        } else if let overlay = overlays.filter({ $0.isAvailable }).randomElement() {
            overlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: restingSeconds, actionTitle: actionTitle, onTapped: onTapped, checkIn: checkIn)
            dispatched = true
        } else {
            dispatched = false
        }

        // Only marked "shown" once actually dispatched — a failed attempt
        // (no available overlay) shouldn't burn the one-time chance to
        // surface this version's reminder.
        if dispatched, let pendingUpdate {
            updateReminderShownForVersion = pendingUpdate.version
        }
        if dispatched {
            markActivityNudgeShown?()
        }
        return dispatched
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

        if isUpdating {
            let updatingItem = NSMenuItem(title: "Updating…", action: nil, keyEquivalent: "")
            updatingItem.image = symbolImage("arrow.down.circle.fill")
            updatingItem.isEnabled = false
            menu.addItem(updatingItem)
        } else if let latestRelease {
            addItem(to: menu, title: "Update · v\(latestRelease.version)", action: #selector(updateTapped), symbol: "arrow.down.circle.fill")
        } else {
            addItem(to: menu, title: "Check for Updates…", action: #selector(checkForUpdatesTapped), symbol: "arrow.triangle.2.circlepath")
        }
        addItem(to: menu, title: "Show Butterfly", action: #selector(showNowTapped), symbol: "sparkles")
        let checkInTestMenu = NSMenu(title: "Test Interactive Check-In")
        checkInTestMenu.minimumWidth = 240
        addCheckInTestItem(to: checkInTestMenu, title: "Random Choice-Row Variant", style: nil)
        checkInTestMenu.addItem(.separator())
        for style in CheckInStyle.allCases {
            addCheckInTestItem(to: checkInTestMenu, title: style.displayName, style: style)
        }
        let checkInTestItem = NSMenuItem(title: "Test Interactive Check-In", action: nil, keyEquivalent: "")
        checkInTestItem.image = symbolImage("hand.tap")
        checkInTestItem.submenu = checkInTestMenu
        menu.addItem(checkInTestItem)
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
        // Docking to the top or bottom edge is what put the parked
        // butterfly and its message right where a MacBook's camera housing
        // (or the menu bar, on non-notched Macs) sits — left/right are the
        // only edges that never compete with either, so those are the only
        // ones offered here now. Roaming visits still use all 4 edges;
        // OverlayWindow avoids the notch itself for those (see
        // ScreenEdge.restPoint's topSafeInset).
        for edge in [ScreenEdge.left, .right] {
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

    private func addCheckInTestItem(to menu: NSMenu, title: String, style: CheckInStyle?) {
        let item = NSMenuItem(title: title, action: #selector(testInteractiveCheckInTapped(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = style?.rawValue
        item.image = symbolImage(style == nil ? "shuffle" : "hand.tap")
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

    /// Opens a check-in on demand so every choice can be exercised without
    /// waiting for the scheduled visit or the occasional-content chance.
    @objc private func testInteractiveCheckInTapped(_ sender: NSMenuItem) {
        let style = (sender.representedObject as? String).flatMap(CheckInStyle.init(rawValue:))
        _ = fireVisit(manualOverride: true, forcedCheckIn: style.map(CheckInContent.make) ?? CheckInContent.random())
    }
    @objc private func checkForUpdatesTapped() { checkForUpdates(showResult: true) }
    @objc private func updateTapped() {
        guard let latestRelease else { return }
        startSelfUpdate(release: latestRelease)
    }

    /// Downloads, installs, and relaunches in place — a single click
    /// instead of sending the user to the GitHub release page to copy and
    /// run a terminal command themselves. Falls back to that page only if
    /// the release has no matching download asset to fetch.
    private func startSelfUpdate(release: GitHubRelease) {
        guard !isUpdating else { return }
        guard let downloadURL = release.appDownloadURL else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }
        isUpdating = true
        if let menu = statusItem?.menu { rebuildMenu(menu) }
        selfUpdater.update(downloadURL: downloadURL) { [weak self] error in
            guard let self, let error else { return }
            // Only reached on failure — success replaces this process
            // entirely (SelfUpdater terminates the app once the new one is
            // already launched).
            self.isUpdating = false
            if let menu = self.statusItem?.menu { self.rebuildMenu(menu) }
            self.showUpdateMessage("Could not install the update automatically.\n\(error.localizedDescription)\n\nYou can also open the download page instead.")
        }
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
                            self.presentBubbleNotice(
                                message: "A new Butterfly (v\(release.version)) is ready.",
                                actionTitle: "Update Now"
                            ) { [weak self] in self?.startSelfUpdate(release: release) }
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
        presentBubbleNotice(message: message)
    }

    /// The one place any of this app's own status notices (update
    /// available, up to date, update failed) actually reach the screen —
    /// via the same click-through-safe bubble every ordinary visit uses,
    /// never NSAlert. An accessory (LSUIElement) app like this one has no
    /// reliable way to bring a real NSAlert's window to the front:
    /// NSApp.activate is refused unless the current frontmost app yields,
    /// which nothing does for an accessory app, so the alert could show up
    /// not-key/not-frontmost — a click meant to dismiss it then lands on
    /// whatever app actually was frontmost instead, which is exactly the
    /// "click outside the message does something wrong" bug this removes.
    private func presentBubbleNotice(message: String, actionTitle: String? = nil, onTapped: (() -> Void)? = nil) {
        let displayWidth = ButterflySize.width(forIndex: config.butterflySizeIndex)
        let restingSeconds = max(config.restingSeconds, 14)
        if config.mode == "docked" {
            dockedOverlay?.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: restingSeconds, actionTitle: actionTitle, onTapped: onTapped)
        } else if let overlay = overlays.filter({ $0.isAvailable }).randomElement() {
            overlay.visit(message: message, pinnedAssetIndex: config.pinnedAssetIndex, displayWidth: displayWidth, restingSeconds: restingSeconds, actionTitle: actionTitle, onTapped: onTapped)
        }
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
