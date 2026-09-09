import CoreGraphics

public enum ScrollReverser {
    public static func apply(to event: CGEvent) {
        // 연속 스크롤은 트랙패드와 터치 방식 입력을 위해 그대로 유지합니다.
        guard event.type == .scrollWheel,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return }

        // 줄 값을 쓰면 다른 단위가 재계산되므로 원래 값을 모두 읽은 뒤 반전합니다.
        let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let points = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -lines)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -points)
        event.setDoubleValueField(
            .scrollWheelEventFixedPtDeltaAxis1,
            value: -fixed
        )
    }
}
