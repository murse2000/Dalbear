import CoreGraphics
import XCTest
@testable import ScrollCore

final class ScrollReverserTests: XCTestCase {
    private func event(continuous: Bool = false) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: 3, wheel2: 2, wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 3)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 27)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 3.5)
        return event
    }

    func testReversesAllVerticalUnitsAndPreservesHorizontal() throws {
        let event = try event()
        let horizontal = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let horizontalPoint = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let horizontalFixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        ScrollReverser.apply(to: event)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -27)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -3.5)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), horizontal)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), horizontalPoint)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), horizontalFixed)
        ScrollReverser.apply(to: event)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 27)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 3.5)
    }

    func testPreservesContinuousScrollingAndMomentum() throws {
        let event = try event(continuous: true)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 1)
        ScrollReverser.apply(to: event)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 27)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 3.5)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventMomentumPhase), 1)
    }

    func testPreservesZeroVerticalScroll() throws {
        let event = try event()
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        ScrollReverser.apply(to: event)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 0)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 0)
    }

    func testPreservesOtherEventTypes() throws {
        let event = try event()
        event.type = .mouseMoved
        let original = try XCTUnwrap(event.data) as Data
        ScrollReverser.apply(to: event)
        XCTAssertEqual(try XCTUnwrap(event.data) as Data, original)
    }
}
