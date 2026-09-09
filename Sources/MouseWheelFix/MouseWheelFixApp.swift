import AppLocalization
import AppKit
import ServiceManagement
import PowerCore
import Sparkle

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, SPUStandardUserDriverDelegate {
    private let controller = ScrollController()
    private let desktopAppearance = DesktopAppearanceController()
    private let folderHub = FolderHubController()
    private let keepAwake = KeepAwakeController()
    private lazy var updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    private var updateMenuItem: NSMenuItem?
    private var awakeMenuItem: NSMenuItem?
    private var awakeOptions: [NSMenuItem] = []
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private weak var toggle: NSSwitch?
    private weak var statusLabel: NSTextField?
    private weak var permissionButton: NSButton?
    private weak var permissionLabel: NSTextField?
    private weak var loginToggle: NSSwitch?
    private weak var loginLabel: NSTextField?
    private weak var notchToggle: NSSwitch?
    private weak var cornersToggle: NSSwitch?
    private weak var externalNotchToggle: NSButton?
    private weak var externalCornersToggle: NSButton?
    private weak var folderHubToggle: NSSwitch?
    private weak var safariButtonsToggle: NSSwitch?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 {
            NSApp.terminate(nil)
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = DalbearIcon.menuBarImage()
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: L10n.text("마우스 휠 · 화면 설정…"), action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let folders = menu.addItem(withTitle: L10n.text("폴더 허브 열기"), action: #selector(openFolderHub), keyEquivalent: "")
        folders.target = self
        menu.delegate = self
        let awakeItem = menu.addItem(withTitle: L10n.text("잠자기 방지: 꺼짐"), action: nil, keyEquivalent: "")
        let awakeMenu = NSMenu()
        for (title, minutes) in [(L10n.text("끄기"), 0), (L10n.text("30분 동안"), 30), (L10n.text("1시간 동안"), 60), (L10n.text("직접 해제할 때까지"), -1)] {
            let option = awakeMenu.addItem(withTitle: title, action: #selector(changeKeepAwake(_:)), keyEquivalent: "")
            option.tag = minutes
            option.target = self
            awakeOptions.append(option)
        }
        awakeMenu.addItem(.separator())
        let explanation = awakeMenu.addItem(withTitle: L10n.text("화면은 꺼져도 Mac은 깨어 있습니다"), action: nil, keyEquivalent: "")
        explanation.isEnabled = false
        awakeItem.submenu = awakeMenu
        awakeMenuItem = awakeItem
        keepAwake.onChange = { [weak self] in self?.updateKeepAwakeStatus() }
        updateKeepAwakeStatus()
        menu.addItem(.separator())
        let update = menu.addItem(withTitle: L10n.text("업데이트 확인…"), action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = updaterController
        updateMenuItem = update
        let quit = menu.addItem(withTitle: L10n.text("Dalbear 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        item.menu = menu
        statusItem = item
        // 중복 실행 검사를 통과한 앱에서만 업데이트 확인을 시작합니다.
        updaterController.startUpdater()
        desktopAppearance.refresh()
        folderHub.start()
        controller.onChange = { [weak self] in self?.updateStatus() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        // 로그인 항목으로 실행된 경우 설정 창을 만들지 않습니다.
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.eventID == kAEOpenApplication
            && launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        updateStatus()
        if !launchedAtLogin { showSettings() }
    }

    @objc private func applicationChanged() { controller.cancelAnimation() }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        // 다른 앱의 작업을 방해하지 않고 메뉴 막대에 새 버전을 알립니다.
        statusItem?.length = NSStatusItem.variableLength
        statusItem?.button?.title = " ↑"
        updateMenuItem?.title = L10n.text("새 버전 %@ 사용 가능…", update.displayVersionString)
    }

    func standardUserDriverWillFinishUpdateSession() {
        statusItem?.button?.title = ""
        statusItem?.length = NSStatusItem.squareLength
        updateMenuItem?.title = L10n.text("업데이트 확인…")
    }
    @objc private func willSleep() {
        controller.stop()
        // 사용자가 직접 잠자기를 선택하면 기존 절전 방지 세션을 끝냅니다.
        do { try keepAwake.stop() } catch { showKeepAwakeError(error) }
    }
    @objc private func didWake() { controller.refresh() }
    func applicationDidBecomeActive(_ notification: Notification) { controller.refresh() }

    @objc private func showSettings() {
        if window == nil { window = makeWindow() }
        controller.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 770), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Dalbear"
        window.isReleasedWhenClosed = false
        window.delegate = self
        guard let content = window.contentView else { return window }

        func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: size, weight: weight)
            return label
        }
        let title = label("Dalbear", 25, .bold)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let subtitle = label(L10n.text("내 Mac을 더 편하게.  ·  v%@", version), 13)
        subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 7
        heading.frame = NSRect(x: 28, y: 354, width: 464, height: 62)
        content.addSubview(heading)

        let switchLabel = label(L10n.text("마우스 휠 반전"), 15, .semibold)
        switchLabel.frame = NSRect(x: 28, y: 299, width: 370, height: 24)
        content.addSubview(switchLabel)
        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(toggleScrolling)
        toggle.setAccessibilityLabel(L10n.text("마우스 휠 반전"))
        toggle.frame = NSRect(x: 446, y: 298, width: 46, height: 26)
        content.addSubview(toggle)
        self.toggle = toggle
        let description = label(L10n.text("세로 휠을 반전하고 짧은 픽셀 이동으로 부드럽게 연결합니다."), 12)
        description.textColor = .secondaryLabelColor
        description.frame = NSRect(x: 28, y: 268, width: 464, height: 24)
        content.addSubview(description)
        let directions = label(L10n.text("↑ 휠 위로 → 화면 위로       ↓ 휠 아래로 → 화면 아래로"), 13, .medium)
        directions.frame = NSRect(x: 28, y: 226, width: 464, height: 24)
        content.addSubview(directions)
        let note = label(L10n.text("macOS의 ‘자연스러운 스크롤’이 켜져 있을 때의 동작입니다."), 11)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 28, y: 204, width: 464, height: 22)
        content.addSubview(note)
        let status = label("", 13, .medium)
        status.frame = NSRect(x: 28, y: 153, width: 464, height: 24)
        content.addSubview(status)
        statusLabel = status
        let permission = label(L10n.text("시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서\nDalbear를 허용해 주세요."), 11)
        permission.textColor = .secondaryLabelColor
        permission.frame = NSRect(x: 28, y: 103, width: 464, height: 40)
        content.addSubview(permission)
        permissionLabel = permission
        let button = NSButton(title: L10n.text("손쉬운 사용 권한 설정 열기"), target: self, action: #selector(requestPermission))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 24, y: 67, width: 220, height: 32)
        content.addSubview(button)
        permissionButton = button
        // 기존 설정 아래에 로그인 옵션을 배치할 공간을 확보합니다.
        for view in content.subviews { view.frame.origin.y += 100 }
        let loginTitle = label(L10n.text("로그인 시 자동 실행"), 14, .semibold)
        loginTitle.frame = NSRect(x: 28, y: 108, width: 370, height: 24)
        content.addSubview(loginTitle)
        let loginToggle = NSSwitch()
        loginToggle.target = self
        loginToggle.action = #selector(toggleLaunchAtLogin)
        loginToggle.setAccessibilityLabel(L10n.text("로그인 시 자동 실행"))
        loginToggle.frame = NSRect(x: 446, y: 106, width: 46, height: 26)
        content.addSubview(loginToggle)
        self.loginToggle = loginToggle
        let loginDescription = label("", 11)
        loginDescription.textColor = .secondaryLabelColor
        loginDescription.frame = NSRect(x: 28, y: 67, width: 464, height: 36)
        content.addSubview(loginDescription)
        loginLabel = loginDescription
        // 기존 휠·로그인 설정 아래에 화면 꾸미기 옵션을 배치합니다.
        for view in content.subviews { view.frame.origin.y += 140 }
        let notchTitle = label(L10n.text("노치 숨기기"), 14, .semibold)
        notchTitle.frame = NSRect(x: 28, y: 163, width: 370, height: 24)
        content.addSubview(notchTitle)
        let notchToggle = NSSwitch()
        notchToggle.target = self
        notchToggle.action = #selector(toggleNotch)
        notchToggle.setAccessibilityLabel(L10n.text("노치 숨기기"))
        notchToggle.state = desktopAppearance.hideNotch ? .on : .off
        notchToggle.frame = NSRect(x: 446, y: 161, width: 46, height: 26)
        content.addSubview(notchToggle)
        self.notchToggle = notchToggle
        let externalNotch = NSButton(checkboxWithTitle: L10n.text("확장 모니터에도 상단 검은 바 표시"), target: self, action: #selector(toggleExternalNotch))
        externalNotch.font = .systemFont(ofSize: 11)
        externalNotch.state = desktopAppearance.hideNotchOnExternalDisplays ? .on : .off
        externalNotch.isEnabled = desktopAppearance.hideNotch
        externalNotch.frame = NSRect(x: 28, y: 137, width: 464, height: 22)
        content.addSubview(externalNotch)
        externalNotchToggle = externalNotch
        let cornersTitle = label(L10n.text("배경화면 모서리 둥글게"), 14, .semibold)
        cornersTitle.frame = NSRect(x: 28, y: 101, width: 370, height: 24)
        content.addSubview(cornersTitle)
        let cornersToggle = NSSwitch()
        cornersToggle.target = self
        cornersToggle.action = #selector(toggleCorners)
        cornersToggle.setAccessibilityLabel(L10n.text("배경화면 모서리 둥글게"))
        cornersToggle.state = desktopAppearance.roundCorners ? .on : .off
        cornersToggle.frame = NSRect(x: 446, y: 99, width: 46, height: 26)
        content.addSubview(cornersToggle)
        self.cornersToggle = cornersToggle
        let externalCorners = NSButton(checkboxWithTitle: L10n.text("확장 모니터에도 모서리 둥글게 표시"), target: self, action: #selector(toggleExternalCorners))
        externalCorners.font = .systemFont(ofSize: 11)
        externalCorners.state = desktopAppearance.roundCornersOnExternalDisplays ? .on : .off
        externalCorners.isEnabled = desktopAppearance.roundCorners
        externalCorners.frame = NSRect(x: 28, y: 75, width: 464, height: 22)
        content.addSubview(externalCorners)
        externalCornersToggle = externalCorners
        // 폴더 허브는 휠 반전과 독립적으로 켜고 끕니다.
        for view in content.subviews { view.frame.origin.y += 80 }
        let hubTitle = label(L10n.text("폴더 허브 사용"), 14, .semibold)
        hubTitle.frame = NSRect(x: 28, y: 93, width: 370, height: 24)
        content.addSubview(hubTitle)
        let openHub = NSButton(title: L10n.text("폴더 열기…"), target: self, action: #selector(openFolderHub))
        openHub.bezelStyle = .rounded
        openHub.frame = NSRect(x: 280, y: 90, width: 110, height: 28)
        content.addSubview(openHub)
        let hubToggle = NSSwitch()
        hubToggle.target = self
        hubToggle.action = #selector(toggleFolderHub)
        hubToggle.setAccessibilityLabel(L10n.text("폴더 허브 사용"))
        hubToggle.frame = NSRect(x: 446, y: 91, width: 46, height: 26)
        content.addSubview(hubToggle)
        folderHubToggle = hubToggle
        let hubDescription = label(L10n.text("노치에 마우스를 올리거나 ⌘⌥→ 키로 폴더를 엽니다."), 11)
        hubDescription.textColor = .secondaryLabelColor
        hubDescription.frame = NSRect(x: 28, y: 64, width: 464, height: 22)
        content.addSubview(hubDescription)
        let safariTitle = label(L10n.text("Safari 뒤로·앞으로 버튼"), 14, .semibold)
        safariTitle.frame = NSRect(x: 28, y: 360, width: 370, height: 24)
        content.addSubview(safariTitle)
        let safariToggle = NSSwitch()
        safariToggle.target = self
        safariToggle.action = #selector(toggleSafariButtons)
        safariToggle.setAccessibilityLabel(L10n.text("Safari 뒤로·앞으로 버튼"))
        safariToggle.toolTip = L10n.text("Safari에서만 마우스 옆 버튼을 뒤로·앞으로 가기로 연결합니다. 휠 반전과 독립적으로 동작합니다.")
        safariToggle.frame = NSRect(x: 446, y: 358, width: 46, height: 26)
        content.addSubview(safariToggle)
        safariButtonsToggle = safariToggle
        let awakeButton = NSButton(title: L10n.text("잠자기 방지…"), target: self, action: #selector(openKeepAwakeMenu(_:)))
        awakeButton.bezelStyle = .rounded
        awakeButton.frame = NSRect(x: 280, y: 387, width: 212, height: 32)
        content.addSubview(awakeButton)
        let footer = label(L10n.text("창을 닫아도 메뉴 막대에서 실행됩니다.\n트랙패드 등 연속 스크롤과 가로 스크롤은 그대로 유지합니다."), 11)
        footer.textColor = .secondaryLabelColor
        footer.frame = NSRect(x: 28, y: 18, width: 464, height: 36)
        content.addSubview(footer)
        window.center()
        return window
    }

    @objc private func toggleScrolling() { controller.enabled = toggle?.state == .on }
    @objc private func toggleSafariButtons() { controller.safariButtonsEnabled = safariButtonsToggle?.state == .on }
    @objc private func requestPermission() { controller.requestPermission() }
    @objc private func toggleNotch() {
        desktopAppearance.hideNotch = notchToggle?.state == .on
        externalNotchToggle?.isEnabled = desktopAppearance.hideNotch
    }
    @objc private func toggleExternalNotch() {
        desktopAppearance.hideNotchOnExternalDisplays = externalNotchToggle?.state == .on
    }
    @objc private func toggleCorners() {
        desktopAppearance.roundCorners = cornersToggle?.state == .on
        externalCornersToggle?.isEnabled = desktopAppearance.roundCorners
    }
    @objc private func toggleExternalCorners() {
        desktopAppearance.roundCornersOnExternalDisplays = externalCornersToggle?.state == .on
    }
    @objc private func toggleFolderHub() { folderHub.enabled = folderHubToggle?.state == .on }
    @objc private func openFolderHub() { folderHub.open(); updateStatus() }

    func menuWillOpen(_ menu: NSMenu) {
        keepAwake.refresh()
        updateKeepAwakeStatus()
    }

    @objc private func openKeepAwakeMenu(_ sender: NSButton) {
        keepAwake.refresh()
        updateKeepAwakeStatus()
        awakeMenuItem?.submenu?.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func changeKeepAwake(_ sender: NSMenuItem) {
        do {
            if sender.tag == 0 {
                try keepAwake.stop()
            } else {
                try keepAwake.start(duration: sender.tag < 0 ? nil : TimeInterval(sender.tag * 60))
            }
        } catch { showKeepAwakeError(error) }
    }

    private func updateKeepAwakeStatus() {
        if let endDate = keepAwake.endDate {
            awakeMenuItem?.title = L10n.text("잠자기 방지: %@까지", endDate.formatted(date: .omitted, time: .shortened))
        } else {
            awakeMenuItem?.title = keepAwake.isActive ? L10n.text("잠자기 방지: 켜짐") : L10n.text("잠자기 방지: 꺼짐")
        }
        let selected = keepAwake.isActive ? keepAwake.duration.map { Int($0 / 60) } ?? -1 : 0
        for option in awakeOptions { option.state = option.tag == selected ? .on : .off }
    }

    private func showKeepAwakeError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.text("잠자기 방지 설정을 변경하지 못했습니다")
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if loginToggle?.state == .on {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.text("자동 실행 설정을 변경하지 못했습니다")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            if let window { alert.beginSheetModal(for: window) }
        }
        updateLoginStatus()
    }

    private func updateLoginStatus() {
        let status = SMAppService.mainApp.status
        loginToggle?.state = status == .enabled || status == .requiresApproval ? .on : .off
        switch status {
        case .enabled:
            loginLabel?.stringValue = L10n.text("Mac에 로그인하면 설정 창 없이 메뉴 막대에서 시작합니다.")
        case .requiresApproval:
            loginLabel?.stringValue = L10n.text("시스템 설정 → 일반 → 로그인 항목에서 허용해 주세요.")
        case .notFound:
            loginLabel?.stringValue = L10n.text("앱을 찾을 수 없습니다. 설치 위치를 확인한 뒤 다시 켜 주세요.")
        default:
            loginLabel?.stringValue = L10n.text("Mac에 로그인할 때 Dalbear를 자동으로 시작합니다.")
        }
    }

    private func updateStatus() {
        folderHubToggle?.state = folderHub.enabled ? .on : .off
        toggle?.state = controller.enabled ? .on : .off
        safariButtonsToggle?.state = controller.safariButtonsEnabled ? .on : .off
        statusLabel?.stringValue = controller.status
        statusLabel?.textColor = controller.active ? .systemGreen : .secondaryLabelColor
        permissionLabel?.isHidden = controller.trusted
        permissionButton?.isHidden = controller.trusted
        statusItem?.button?.toolTip = controller.status
        updateLoginStatus()
    }

    func windowWillClose(_ notification: Notification) {
        // 설정 화면을 닫으면 뷰와 창을 해제하고 메뉴 막대만 유지합니다.
        window = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? keepAwake.stop()
        folderHub.stop()
        desktopAppearance.stop()
        controller.stop()
    }
}
