import CoreGraphics
import XCTest
@testable import ScrollCore

final class ScrollModifiersTests: XCTestCase {
    func testSystemFlagsDoNotCancelScrolling() {
        // 실제 휠 검증에서 관측된 추가 시스템 비트는 수정 키 변화가 아닙니다.
        let observedFlags = CGEventFlags(rawValue: 0x20000000)
        XCTAssertFalse(ScrollModifiers.changed(from: [], to: observedFlags))
        XCTAssertFalse(ScrollModifiers.changed(from: observedFlags, to: []))
        XCTAssertFalse(ScrollModifiers.changed(from: [], to: .maskNonCoalesced))
    }

    func testModifierPressAndReleaseCancelScrolling() {
        let keys: [CGEventFlags] = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskHelp]
        for key in keys {
            XCTAssertTrue(ScrollModifiers.changed(from: [], to: key))
            XCTAssertTrue(ScrollModifiers.changed(from: key, to: []))
            XCTAssertFalse(ScrollModifiers.changed(from: key, to: key))
        }
    }
}
