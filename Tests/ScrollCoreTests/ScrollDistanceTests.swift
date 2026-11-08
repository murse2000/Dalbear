import CoreGraphics
import XCTest
@testable import ScrollCore

final class ScrollDistanceTests: XCTestCase {
    func testSlowWheelRetainsLineDistanceInBothDirections() {
        for direction: Int64 in [-1, 1] {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: direction)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: direction)
            XCTAssertEqual(ScrollDistance.pixels(for: event), Double(direction * 10))
        }
    }

    func testFiveSlowNotchesStartImmediatelyAndFinishWithFullDistance() {
        var smoother = ScrollSmoother()
        var total: Int64 = 0
        for notch in 0..<5 {
            let time = 1 + Double(notch) * 0.5
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 1)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 1)
            smoother.add(pixels: ScrollDistance.pixels(for: event), at: time)
            let first = smoother.step(at: time)
            XCTAssertGreaterThan(first, 0)
            total += first
            for frame in 1...16 { total += smoother.step(at: time + Double(frame) / 120) }
            XCTAssertFalse(smoother.isActive)
        }
        XCTAssertEqual(total, 50)
    }

    func testAcceleratedAndPixelOnlyInputsKeepTheirDistance() {
        for (lines, points) in [(Int64(1), Int64(15)), (-1, -80), (0, 3), (0, 0)] {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)!
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: lines)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: points)
            XCTAssertEqual(ScrollDistance.pixels(for: event), Double(points))
        }
    }
}
