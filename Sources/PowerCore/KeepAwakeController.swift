import Foundation
import IOKit.pwr_mgt

public final class KeepAwakeController {
    public var onChange: (() -> Void)?
    public private(set) var duration: TimeInterval?
    public private(set) var endDate: Date?
    private(set) var assertionID: IOPMAssertionID?
    private var expirationTimer: Timer?

    public init() {}

    public var isActive: Bool { assertionID != nil }

    public func start(duration: TimeInterval?) throws {
        try stop()
        var identifier: IOPMAssertionID = 0
        // 시스템 자체의 만료도 설정하여 앱 타이머가 늦어져도 절전 방지가 끝납니다.
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            "MouseWheelFix Keep Awake" as CFString,
            nil, nil, nil, duration ?? 0,
            kIOPMAssertionTimeoutActionRelease as CFString, &identifier
        )
        guard result == kIOReturnSuccess else { throw powerError(result) }
        assertionID = identifier
        self.duration = duration
        endDate = duration.map { Date().addingTimeInterval($0) }
        if let duration {
            let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                self?.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            expirationTimer = timer
        }
        onChange?()
    }

    public func refresh() {
        guard let assertionID else { return }
        if IOPMAssertionCopyProperties(assertionID)?.takeRetainedValue() == nil {
            clear()
        } else if let endDate, Date() >= endDate {
            // 만료 시점에 시스템 해제와 타이머가 경합하면 여기서 직접 해제합니다.
            do { try stop() } catch { onChange?() }
        }
    }

    public func stop() throws {
        if let assertionID {
            let result = IOPMAssertionRelease(assertionID)
            if result != kIOReturnSuccess && IOPMAssertionCopyProperties(assertionID)?.takeRetainedValue() != nil {
                throw powerError(result)
            }
        }
        clear()
    }

    private func clear() {
        expirationTimer?.invalidate()
        expirationTimer = nil
        assertionID = nil
        duration = nil
        endDate = nil
        onChange?()
    }

    private func powerError(_ code: IOReturn) -> NSError {
        NSError(domain: "MouseWheelFix.Power", code: Int(code), userInfo: [
            NSLocalizedDescriptionKey: "macOS가 잠자기 방지 요청을 처리하지 못했습니다. (코드 \(code))"
        ])
    }

    deinit {
        expirationTimer?.invalidate()
        if let assertionID { IOPMAssertionRelease(assertionID) }
    }
}
