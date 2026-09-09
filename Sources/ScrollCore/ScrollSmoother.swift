import Foundation

/// 입력 개수와 무관하게 남은 거리만 보관하는 세로 스크롤 보간기입니다.
public struct ScrollSmoother {
    public private(set) var remaining = 0.0
    private var lastStep = 0.0
    private var lastInput = 0.0
    private var fraction = 0.0

    public init() {}

    public var isActive: Bool { remaining != 0 || fraction != 0 }

    public mutating func add(pixels: Double, at time: Double) {
        guard pixels != 0 else { return }
        // 방향을 바꾸면 이전 방향의 잔여 이동이 따라오지 않도록 취소합니다.
        if isActive && (remaining + fraction).sign != pixels.sign { reset() }
        if !isActive { lastStep = time - 1.0 / 120.0 }
        remaining += pixels
        lastInput = time
    }

    public mutating func step(at time: Double) -> Int64 {
        guard isActive else { return 0 }
        let elapsed = max(0, time - lastStep)
        lastStep = time
        // 약 32ms의 감쇠로 시작하고 마지막 입력 120ms 후에는 정확히 마칩니다.
        let finishing = time - lastInput >= 0.12
        let distance = finishing ? remaining : remaining * (1 - exp(-elapsed / 0.032))
        remaining -= distance
        fraction += distance
        let pixels = Int64(finishing ? fraction.rounded() : fraction.rounded(.towardZero))
        fraction -= Double(pixels)
        if finishing { reset() }
        return pixels
    }

    public mutating func reset() {
        remaining = 0
        fraction = 0
        lastStep = 0
        lastInput = 0
    }
}
