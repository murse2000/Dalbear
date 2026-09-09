import XCTest
@testable import ScrollCore

final class ScrollSmootherTests: XCTestCase {
    func testSingleNotchStartsImmediatelyAndPreservesDistance() {
        var smoother = ScrollSmoother()
        smoother.add(pixels: 80, at: 1)
        var total = smoother.step(at: 1)
        XCTAssertGreaterThan(total, 0)
        XCTAssertLessThan(total, 80)
        for frame in 1...16 { total += smoother.step(at: 1 + Double(frame) / 120) }
        XCTAssertEqual(total, 80)
        XCTAssertFalse(smoother.isActive)
        XCTAssertEqual(smoother.step(at: 2), 0)
    }

    func testRapidInputPreservesTotalWithoutGrowingAQueue() {
        var smoother = ScrollSmoother()
        var total: Int64 = 0
        for frame in 0..<1200 {
            let time = Double(frame) / 120
            smoother.add(pixels: -17, at: time)
            let step = smoother.step(at: time)
            XCTAssertLessThanOrEqual(step, 0)
            total += step
        }
        total += smoother.step(at: 11)
        XCTAssertEqual(total, -17 * 1200)
        XCTAssertFalse(smoother.isActive)
    }

    func testDirectionChangeCancelsOldTailImmediately() {
        var smoother = ScrollSmoother()
        smoother.add(pixels: 100, at: 1)
        XCTAssertGreaterThan(smoother.step(at: 1), 0)
        smoother.add(pixels: -20, at: 1.01)
        let immediate = smoother.step(at: 1.01)
        XCTAssertLessThan(immediate, 0)
        XCTAssertEqual(immediate + smoother.step(at: 2), -20)
    }

    func testCancellationAndTinyInput() {
        var smoother = ScrollSmoother()
        smoother.add(pixels: 1, at: 1)
        XCTAssertEqual(smoother.step(at: 1) + smoother.step(at: 1.13), 1)
        smoother.add(pixels: 100, at: 2)
        smoother.reset()
        XCTAssertFalse(smoother.isActive)
        XCTAssertEqual(smoother.step(at: 3), 0)
    }

    func testDelayedFrameFinishesWithoutOvershoot() {
        var smoother = ScrollSmoother()
        smoother.add(pixels: -120, at: 1)
        XCTAssertEqual(smoother.step(at: 2), -120)
        XCTAssertFalse(smoother.isActive)
    }
}
