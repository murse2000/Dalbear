import Carbon.HIToolbox
import CoreGraphics

public enum SafariNavigation: Equatable {
    case back
    case forward

    public func makeKeyEvents() -> (down: CGEvent, up: CGEvent)? {
        let code = CGKeyCode(self == .back ? kVK_ANSI_LeftBracket : kVK_ANSI_RightBracket)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        return (down, up)
    }
}

public struct SafariButtonRouter {
    public enum Action: Equatable {
        case passThrough
        case suppress
        case navigate(SafariNavigation)
    }

    private var pressed: UInt8 = 0

    public init() {}

    public mutating func handle(type: CGEventType, button: Int64, enabled: Bool, bundleIdentifier: String?) -> Action {
        guard button == 3 || button == 4 else { return .passThrough }
        let bit = UInt8(1 << (button - 3))
        if type == .otherMouseUp {
            guard pressed & bit != 0 else { return .passThrough }
            pressed &= ~bit
            return .suppress
        }
        guard type == .otherMouseDown else { return .passThrough }
        // 이미 변환한 누름의 반복과 놓음은 앱이 바뀌어도 전달하지 않습니다.
        if pressed & bit != 0 { return .suppress }
        guard enabled && bundleIdentifier == "com.apple.Safari" else { return .passThrough }
        pressed |= bit
        return .navigate(button == 3 ? .back : .forward)
    }

    public mutating func reset() { pressed = 0 }
}
