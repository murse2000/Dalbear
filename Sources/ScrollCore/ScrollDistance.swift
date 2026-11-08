import CoreGraphics

public enum ScrollDistance {
    public static func pixels(for event: CGEvent) -> Double {
        let points = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let lines = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        // 저속 휠의 1픽셀 가속값이 물리적인 휠 입력을 사실상 지우지 않게 합니다.
        // 출력의 기존 환산 기준인 한 줄당 10픽셀을 최소 이동량으로 사용합니다.
        let linePixels = lines * 10
        return abs(points) >= abs(linePixels) ? points : linePixels
    }
}
