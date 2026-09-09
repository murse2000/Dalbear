import AppKit

final class DesktopAppearanceController: NSObject {
    var hideNotch = UserDefaults.standard.bool(forKey: "hideNotch") {
        didSet {
            UserDefaults.standard.set(hideNotch, forKey: "hideNotch")
            refresh()
        }
    }
    var roundCorners = UserDefaults.standard.bool(forKey: "roundDesktopCorners") {
        didSet {
            UserDefaults.standard.set(roundCorners, forKey: "roundDesktopCorners")
            refresh()
        }
    }
    var hideNotchOnExternalDisplays = UserDefaults.standard.bool(forKey: "hideNotchOnExternalDisplays") {
        didSet {
            UserDefaults.standard.set(hideNotchOnExternalDisplays, forKey: "hideNotchOnExternalDisplays")
            refresh()
        }
    }
    var roundCornersOnExternalDisplays = UserDefaults.standard.bool(forKey: "roundCornersOnExternalDisplays") {
        didSet {
            UserDefaults.standard.set(roundCornersOnExternalDisplays, forKey: "roundCornersOnExternalDisplays")
            refresh()
        }
    }
    private var windows: [NSWindow] = []

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func refresh() {
        stop()
        guard hideNotch || roundCorners else { return }
        for screen in NSScreen.screens {
            guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            // 주 화면 지정과 관계없이 실제 내장 화면 여부로 구분합니다.
            let isBuiltin = CGDisplayIsBuiltin(displayNumber.uint32Value) != 0
            let showTopBar = hideNotch && (isBuiltin || hideNotchOnExternalDisplays)
            let showCorners = roundCorners && (isBuiltin || roundCornersOnExternalDisplays)
            guard showTopBar || showCorners else { continue }
            let window = DesktopMaskWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            // 배경화면 위, 바탕화면 아이콘과 일반 앱 창 아래에만 표시합니다.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.canHide = false
            let view = DesktopMaskView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.topHeight = showTopBar ? max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) : 0
            view.roundCorners = showCorners
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func stop() {
        for window in windows { window.close() }
        windows.removeAll()
    }
}

private final class DesktopMaskWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DesktopMaskView: NSView {
    var topHeight: CGFloat = 0
    var roundCorners = false

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        if topHeight > 0 {
            NSRect(x: 0, y: bounds.height - topHeight, width: bounds.width, height: topHeight).fill()
        }
        if roundCorners {
            // 상단 검은 띠 아래의 배경화면 네 모서리를 둥글게 만듭니다.
            let desktop = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - topHeight)
            let corners = NSBezierPath(rect: desktop)
            corners.append(NSBezierPath(roundedRect: desktop, xRadius: 12, yRadius: 12))
            corners.windingRule = .evenOdd
            corners.fill()
        }
    }
}
