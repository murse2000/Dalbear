import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import ScrollCore

final class SafariNavigationTests: XCTestCase {
    func testBothButtonsNavigateOnlyOncePerPress() {
        for (button, direction): (Int64, SafariNavigation) in [(3, .back), (4, .forward)] {
            var router = SafariButtonRouter()
            XCTAssertEqual(router.handle(type: .otherMouseDown, button: button, enabled: true, bundleIdentifier: "com.apple.Safari"), .navigate(direction))
            XCTAssertEqual(router.handle(type: .otherMouseDown, button: button, enabled: true, bundleIdentifier: "com.apple.Safari"), .suppress)
            XCTAssertEqual(router.handle(type: .otherMouseUp, button: button, enabled: true, bundleIdentifier: "com.apple.Safari"), .suppress)
            XCTAssertEqual(router.handle(type: .otherMouseDown, button: button, enabled: true, bundleIdentifier: "com.apple.Safari"), .navigate(direction))
        }
    }

    func testChromeOtherAppsAndDisabledOptionPassThrough() {
        for bundle: String? in ["com.google.Chrome", "com.apple.finder", nil] {
            var router = SafariButtonRouter()
            XCTAssertEqual(router.handle(type: .otherMouseDown, button: 3, enabled: true, bundleIdentifier: bundle), .passThrough)
            XCTAssertEqual(router.handle(type: .otherMouseUp, button: 3, enabled: true, bundleIdentifier: bundle), .passThrough)
        }
        var router = SafariButtonRouter()
        XCTAssertEqual(router.handle(type: .otherMouseDown, button: 4, enabled: false, bundleIdentifier: "com.apple.Safari"), .passThrough)
    }

    func testMiddleAndOtherButtonsAndScrollingPassThrough() {
        var router = SafariButtonRouter()
        for button: Int64 in [0, 1, 2, 5, 6] {
            XCTAssertEqual(router.handle(type: .otherMouseDown, button: button, enabled: true, bundleIdentifier: "com.apple.Safari"), .passThrough)
        }
        XCTAssertEqual(router.handle(type: .scrollWheel, button: 3, enabled: true, bundleIdentifier: "com.apple.Safari"), .passThrough)
    }

    func testReleaseIsConsumedAfterAppOrOptionChanges() {
        var router = SafariButtonRouter()
        _ = router.handle(type: .otherMouseDown, button: 3, enabled: true, bundleIdentifier: "com.apple.Safari")
        XCTAssertEqual(router.handle(type: .otherMouseUp, button: 3, enabled: false, bundleIdentifier: "com.google.Chrome"), .suppress)
        XCTAssertEqual(router.handle(type: .otherMouseDown, button: 3, enabled: true, bundleIdentifier: "com.google.Chrome"), .passThrough)
        // 다른 앱에서 누른 버튼을 Safari에서 놓아도 새 탐색을 시작하지 않습니다.
        XCTAssertEqual(router.handle(type: .otherMouseUp, button: 3, enabled: true, bundleIdentifier: "com.apple.Safari"), .passThrough)
    }

    func testResetAndSimultaneousButtons() {
        var router = SafariButtonRouter()
        _ = router.handle(type: .otherMouseDown, button: 3, enabled: true, bundleIdentifier: "com.apple.Safari")
        XCTAssertEqual(router.handle(type: .otherMouseDown, button: 4, enabled: true, bundleIdentifier: "com.apple.Safari"), .navigate(.forward))
        router.reset()
        XCTAssertEqual(router.handle(type: .otherMouseDown, button: 3, enabled: true, bundleIdentifier: "com.apple.Safari"), .navigate(.back))
    }

    func testShortcutKeyPairsUseOnlyCommand() throws {
        for (direction, code) in [(SafariNavigation.back, kVK_ANSI_LeftBracket), (.forward, kVK_ANSI_RightBracket)] {
            let keys = try XCTUnwrap(direction.makeKeyEvents())
            XCTAssertEqual(keys.down.type, .keyDown)
            XCTAssertEqual(keys.up.type, .keyUp)
            for key in [keys.down, keys.up] {
                XCTAssertEqual(key.flags, .maskCommand)
                XCTAssertEqual(key.getIntegerValueField(.keyboardEventKeycode), Int64(code))
            }
        }
    }
}
