import IOKit.pwr_mgt
import XCTest
@testable import PowerCore

final class KeepAwakeTests: XCTestCase {
    func testSystemAssertionIsCreatedAndReleased() throws {
        let controller = KeepAwakeController()
        defer { try? controller.stop() }
        try controller.start(duration: nil)
        let identifier = try XCTUnwrap(controller.assertionID)
        let rawProperties = try XCTUnwrap(IOPMAssertionCopyProperties(identifier)?.takeRetainedValue())
        let properties = rawProperties as NSDictionary
        XCTAssertEqual(properties[kIOPMAssertionTypeKey] as? String, kIOPMAssertionTypePreventUserIdleSystemSleep)
        XCTAssertTrue(controller.isActive)
        XCTAssertNil(controller.endDate)
        try controller.stop()
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(IOPMAssertionCopyProperties(identifier))
    }

    func testReplacingSessionReleasesPreviousAssertion() throws {
        let controller = KeepAwakeController()
        defer { try? controller.stop() }
        try controller.start(duration: 1800)
        let previous = try XCTUnwrap(controller.assertionID)
        try controller.start(duration: 3600)
        XCTAssertNil(IOPMAssertionCopyProperties(previous))
        XCTAssertEqual(controller.duration, 3600)
        XCTAssertEqual(try XCTUnwrap(controller.endDate).timeIntervalSinceNow, 3600, accuracy: 2)
    }

    func testTimedSessionExpires() throws {
        let controller = KeepAwakeController()
        defer { try? controller.stop() }
        try controller.start(duration: 1)
        let identifier = try XCTUnwrap(controller.assertionID)
        let ended = expectation(description: "시간이 지나면 실제 전원 요청과 UI 상태가 해제됩니다")
        controller.onChange = { [weak controller] in
            if controller?.isActive == false { ended.fulfill() }
        }
        wait(for: [ended], timeout: 4)
        controller.onChange = nil
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(IOPMAssertionCopyProperties(identifier))
    }

    func testDeinitializationReleasesAssertion() throws {
        var controller: KeepAwakeController? = KeepAwakeController()
        try controller?.start(duration: nil)
        let identifier = try XCTUnwrap(controller?.assertionID)
        controller = nil
        XCTAssertNil(IOPMAssertionCopyProperties(identifier))
    }
}
