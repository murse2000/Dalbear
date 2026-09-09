import AppLocalization
import AppKit
import ApplicationServices
import ScrollCore

final class ScrollController {
    var onChange: (() -> Void)?
    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "reverseScrolling")
            refresh()
        }
    }
    var safariButtonsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(safariButtonsEnabled, forKey: "safariNavigationButtons")
            refresh()
        }
    }
    private(set) var trusted = false
    private(set) var active = false
    private(set) var failed = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var permissionTimer: Timer?
    private var animationTimer: Timer?
    private var smoother = ScrollSmoother()
    private var safariButtons = SafariButtonRouter()
    private var output: CGEvent?
    private var inputFlags: CGEventFlags = []
    private static let outputMarker: Int64 = 0x4D5746534D4F4F54

    var status: String {
        if !enabled && !safariButtonsEnabled { return L10n.text("마우스 입력 기능이 꺼져 있습니다") }
        if !trusted { return L10n.text("손쉬운 사용 권한이 필요합니다") }
        if failed { return L10n.text("스크롤 연결 실패 · 앱을 다시 실행해 주세요") }
        if !active { return L10n.text("마우스 입력 연결 중") }
        return enabled ? L10n.text("마우스 휠 반전 · 부드러운 스크롤 사용 중") : L10n.text("Safari 뒤로·앞으로 버튼 사용 중")
    }

    init() {
        enabled = UserDefaults.standard.object(forKey: "reverseScrolling") as? Bool ?? true
        safariButtonsEnabled = UserDefaults.standard.object(forKey: "safariNavigationButtons") as? Bool ?? true
        refresh()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        refresh()
        if !trusted && permissionTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                // 미허용 상태의 refresh가 대기 타이머를 중단하지 않게 합니다.
                if AXIsProcessTrusted() { self?.refresh() }
            }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            permissionTimer = timer
        }
    }

    func refresh() {
        trusted = AXIsProcessTrusted()
        if trusted {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
        defer { onChange?() }
        guard (enabled || safariButtonsEnabled) && trusted else {
            stop()
            failed = false
            return
        }
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            active = CGEvent.tapIsEnabled(tap: tap)
            failed = !active
            return
        }
        let types: [CGEventType] = [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown, .otherMouseUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<ScrollController>.fromOpaque(context).takeUnretainedValue()
                return controller.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            failed = true
            return
        }
        guard let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            failed = true
            return
        }
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        active = CGEvent.tapIsEnabled(tap: newTap)
        failed = !active
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.outputMarker {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelAnimation()
            safariButtons.reset()
            refresh()
            return Unmanaged.passUnretained(event)
        }
        if type == .otherMouseDown || type == .otherMouseUp {
            cancelAnimation()
            let application = NSWorkspace.shared.frontmostApplication
            let action = safariButtons.handle(
                type: type, button: event.getIntegerValueField(.mouseEventButtonNumber),
                enabled: safariButtonsEnabled, bundleIdentifier: application?.bundleIdentifier
            )
            switch action {
            case .passThrough:
                return Unmanaged.passUnretained(event)
            case .suppress:
                return nil
            case .navigate(let direction):
                guard let application, let keys = direction.makeKeyEvents() else {
                    safariButtons.reset()
                    return Unmanaged.passUnretained(event)
                }
                // 전역 키 입력 대신 확인된 Safari 프로세스에만 단축키를 전달합니다.
                keys.down.postToPid(application.processIdentifier)
                keys.up.postToPid(application.processIdentifier)
                return nil
            }
        }
        guard enabled && type == .scrollWheel else {
            cancelAnimation()
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else {
            cancelAnimation()
            return Unmanaged.passUnretained(event)
        }
        ScrollReverser.apply(to: event)
        // 가로 입력과 수정 키 조합은 앱 고유의 이동·확대 동작을 보존합니다.
        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        guard event.flags.intersection(modifiers).isEmpty,
              event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 0,
              event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 0 else {
            cancelAnimation()
            return Unmanaged.passUnretained(event)
        }
        let pixels = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        guard pixels != 0 else { return Unmanaged.passUnretained(event) }
        if output == nil {
            output = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)
        }
        guard let output else { return Unmanaged.passUnretained(event) }
        output.location = event.location
        output.flags = event.flags
        inputFlags = event.flags
        output.setIntegerValueField(.eventSourceUserData, value: Self.outputMarker)
        smoother.add(pixels: Double(pixels), at: ProcessInfo.processInfo.systemUptime)
        if animationTimer == nil {
            // 첫 이동은 즉시 전달하고 입력이 있는 동안에만 최대 120Hz로 보간합니다.
            let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = 0.001
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
            tick()
        }
        return nil
    }

    private func tick() {
        guard let output else { return }
        guard !ScrollModifiers.changed(from: inputFlags, to: CGEventSource.flagsState(.combinedSessionState)) else {
            cancelAnimation()
            return
        }
        let pixels = smoother.step(at: ProcessInfo.processInfo.systemUptime)
        if pixels != 0 {
            output.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: pixels / 10)
            output.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(pixels) / 10)
            output.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: pixels)
            output.timestamp = DispatchTime.now().uptimeNanoseconds
            output.post(tap: .cgSessionEventTap)
        }
        if !smoother.isActive { cancelAnimation() }
    }

    func cancelAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        smoother.reset()
        output = nil
    }

    func stop() {
        cancelAnimation()
        safariButtons.reset()
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        active = false
    }
}
