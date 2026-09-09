import CoreGraphics

public enum ScrollModifiers {
    public static func changed(from input: CGEventFlags, to current: CGEventFlags) -> Bool {
        // 이벤트별 시스템 비트를 제외하고 실제 수정 키 상태만 비교합니다.
        let keys: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskHelp]
        return input.intersection(keys) != current.intersection(keys)
    }
}
