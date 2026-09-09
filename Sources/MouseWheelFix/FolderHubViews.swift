import AppKit
import QuartzCore
import QuickLookThumbnailing

final class FolderHubPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FolderWorkspaceButton: NSButton {
    var onHover: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
}

final class FolderCollectionView: NSCollectionView {
    var onKey: ((NSEvent) -> Bool)?
    var makeMenu: (() -> NSMenu)?
    var openItem: ((Int, NSEvent.ModifierFlags) -> Void)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        if let index, event.clickCount == 2 || event.modifierFlags.contains(.command) {
            openItem?(index.item, event.modifierFlags)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let index = indexPathForItem(at: convert(event.locationInWindow, from: nil)), !selectionIndexPaths.contains(index) {
            selectionIndexPaths = [index]
        }
        // Control 클릭은 원본 앱처럼 AirDrop을 엽니다. 우클릭은 파일 메뉴입니다.
        if event.type == .leftMouseDown, event.modifierFlags.contains(.control), let index = selectionIndexPaths.first {
            openItem?(index.item, event.modifierFlags)
            return nil
        }
        return makeMenu?()
    }
}

final class FolderFileItem: NSCollectionViewItem {
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 7
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(image)
        imageView = image
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        view.addSubview(label)
        textField = label
    }

    func configure(name: String, icon: NSImage, list: Bool, width: CGFloat) {
        representedObject = nil
        imageView?.image = icon
        textField?.stringValue = name
        textField?.alignment = list ? .left : .center
        imageView?.frame = list ? NSRect(x: 8, y: 4, width: 24, height: 24) : NSRect(x: 22, y: 34, width: 44, height: 44)
        textField?.frame = list ? NSRect(x: 42, y: 6, width: width - 50, height: 21) : NSRect(x: 3, y: 2, width: 82, height: 30)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(name)
        view.toolTip = name
        updateSelection()
    }

    func loadThumbnail(_ url: URL) {
        representedObject = url
        let request = QLThumbnailGenerator.Request(fileAt: url, size: NSSize(width: 44, height: 44), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            DispatchQueue.main.async {
                guard let self, self.representedObject as? URL == url, let thumbnail else { return }
                self.imageView?.image = thumbnail.nsImage
            }
        }
    }

    override var isSelected: Bool { didSet { updateSelection() } }
    private func updateSelection() {
        view.layer?.backgroundColor = (isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3) : .clear).cgColor
    }
}

final class BearPawView: NSView, CAAnimationDelegate {
    private let motionLayer = CALayer()
    private var angle: CGFloat = 0
    private var moving = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func drawPaw() {
        // 팔 뿌리를 경계 위까지 연장하고 발끝은 회전 중에도 창 안에 둡니다.
        NSColor(calibratedRed: 0.22, green: 0.13, blue: 0.08, alpha: 1).setFill()
        let arm = NSBezierPath()
        arm.move(to: NSPoint(x: 46, y: 160))
        arm.line(to: NSPoint(x: 74, y: 160))
        arm.curve(to: NSPoint(x: 78, y: 29), controlPoint1: NSPoint(x: 69, y: 110), controlPoint2: NSPoint(x: 70, y: 55))
        arm.curve(to: NSPoint(x: 42, y: 29), controlPoint1: NSPoint(x: 82, y: 10), controlPoint2: NSPoint(x: 38, y: 10))
        arm.curve(to: NSPoint(x: 46, y: 160), controlPoint1: NSPoint(x: 50, y: 55), controlPoint2: NSPoint(x: 51, y: 110))
        arm.close()
        arm.fill()
        NSBezierPath(ovalIn: NSRect(x: 40, y: 13, width: 40, height: 34)).fill()
        let toes = [NSRect(x: 31, y: 22, width: 17, height: 18), NSRect(x: 37, y: 9, width: 18, height: 19), NSRect(x: 51, y: 5, width: 18, height: 19), NSRect(x: 65, y: 9, width: 18, height: 19), NSRect(x: 72, y: 22, width: 17, height: 18)]
        for toe in toes { NSBezierPath(ovalIn: toe).fill() }
        NSColor(calibratedRed: 0.65, green: 0.43, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 48, y: 23, width: 24, height: 18)).fill()
        for toe in toes { NSBezierPath(ovalIn: toe.insetBy(dx: 5, dy: 5)).fill() }
    }

    func appear() {
        stopMotion()
        wantsLayer = true
        if motionLayer.superlayer == nil {
            // AppKit이 관리하는 뷰 레이어와 곰발의 회전 레이어를 분리합니다.
            let picture = NSImage(size: bounds.size)
            picture.lockFocus()
            drawPaw()
            picture.unlockFocus()
            motionLayer.contents = picture.cgImage(forProposedRect: nil, context: nil, hints: nil)
            motionLayer.contentsScale = window?.backingScaleFactor ?? 2
            motionLayer.bounds = bounds
            motionLayer.anchorPoint = CGPoint(x: 0.5, y: 120.0 / 160.0)
            motionLayer.position = CGPoint(x: bounds.midX, y: 120)
            layer?.addSublayer(motionLayer)
        }
        moving = true
        // 내려오면서 바로 좌우 움직임을 시작해 등장과 흔들림을 연결합니다.
        let animation = CASpringAnimation(keyPath: "transform.translation.y")
        animation.fromValue = 130
        animation.toValue = 0
        animation.mass = 1
        animation.stiffness = 150
        animation.damping = 21
        animation.duration = animation.settlingDuration
        motionLayer.add(animation, forKey: "곰발 내려오기")
        sway()
    }

    private func sway() {
        guard moving else { return }
        let layer = motionLayer
        let target = angle >= 0 ? CGFloat.random(in: -0.72 ... -0.46) : CGFloat.random(in: 0.46 ... 0.72)
        let duration = max(0.65, Double(abs(target - angle)) * Double.random(in: 0.85 ... 1.05))
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = angle
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.37, 0, 0.63, 1)
        animation.delegate = self
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeRotation(target, 0, 0, 1)
        // 목표값과 애니메이션을 같은 트랜잭션에 적용해 중간 프레임의 순간 이동을 막습니다.
        layer.add(animation, forKey: "곰발 좌우 움직임")
        angle = target
        CATransaction.commit()
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        // 완료 시점에 다음 움직임을 연결해 타이머 지연으로 멈추지 않게 합니다.
        if flag && moving { sway() }
    }

    func stopMotion() {
        moving = false
        angle = 0
        motionLayer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        motionLayer.transform = CATransform3DIdentity
        CATransaction.commit()
    }
}
