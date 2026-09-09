import AppKit

enum DalbearIcon {
    static func menuBarImage() -> NSImage {
        // 메뉴 막대에서는 작은 크기에 맞춘 달과 곰의 단색 심볼을 사용합니다.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let moon = NSBezierPath()
            moon.move(to: NSPoint(x: 10, y: 17))
            moon.curve(to: NSPoint(x: 2, y: 3), controlPoint1: NSPoint(x: 24, y: 11), controlPoint2: NSPoint(x: 15, y: -4))
            moon.curve(to: NSPoint(x: 10, y: 17), controlPoint1: NSPoint(x: 15, y: 0), controlPoint2: NSPoint(x: 18, y: 11))
            moon.close()
            moon.fill()
            NSBezierPath(ovalIn: NSRect(x: 2, y: 6, width: 10, height: 9)).fill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 12, width: 4, height: 4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9, y: 12, width: 4, height: 4)).fill()
            // 눈과 코를 투명하게 뚫어 밝고 어두운 메뉴 막대에 모두 대응합니다.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 4, y: 10, width: 1.3, height: 1.3)).fill()
            NSBezierPath(ovalIn: NSRect(x: 8.5, y: 10, width: 1.3, height: 1.3)).fill()
            NSBezierPath(ovalIn: NSRect(x: 6, y: 7.5, width: 2, height: 1.5)).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Dalbear"
        return image
    }
}
