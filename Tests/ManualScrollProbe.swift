// 실행 중인 MouseWheelFix를 통과한 이벤트를 받는 수동 검증 전용 앱입니다.
// swiftc Tests/ManualScrollProbe.swift -o .build/verification/ScrollProbe
import AppKit

final class ProbeScrollView: NSScrollView {
    weak var report: NSTextField?
    var count = 0
    var continuous = 0
    var tagged = 0
    var total = 0.0
    var first = 0.0
    var last = 0.0

    override func scrollWheel(with event: NSEvent) {
        count += 1
        continuous += event.hasPreciseScrollingDeltas ? 1 : 0
        tagged += event.cgEvent?.getIntegerValueField(.eventSourceUserData) == 0x4D5746534D4F4F54 ? 1 : 0
        total += event.scrollingDeltaY
        if first == 0 { first = event.timestamp }
        last = event.timestamp
        super.scrollWheel(with: event)
        update()
    }

    func update() {
        report?.stringValue = String(format: "이벤트 %d · 연속 %d · 앱 출력 %d\n세로 합계 %.1f · 구간 %.1fms · 문서 위치 %.1f", count, continuous, tagged, total, (last - first) * 1000, contentView.bounds.origin.y)
    }

    @objc func reset() {
        count = 0; continuous = 0; tagged = 0; total = 0; first = 0; last = 0
        contentView.scroll(to: NSPoint(x: 0, y: 1600))
        reflectScrolledClipView(contentView)
        update()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 660, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "MouseWheelFix 스크롤 검증"
let label = NSTextField(wrappingLabelWithString: "")
label.frame = NSRect(x: 20, y: 475, width: 520, height: 52)
window.contentView?.addSubview(label)
let scroll = ProbeScrollView(frame: NSRect(x: 20, y: 20, width: 620, height: 440))
scroll.hasVerticalScroller = true
scroll.report = label
let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 580, height: 5000))
text.string = (1...160).map { "\($0)    마우스 휠 방향과 부드러운 이동 확인" }.joined(separator: "\n\n")
text.font = .systemFont(ofSize: 15)
text.isEditable = false
scroll.documentView = text
window.contentView?.addSubview(scroll)
let button = NSButton(title: "초기화", target: scroll, action: #selector(ProbeScrollView.reset))
button.frame = NSRect(x: 550, y: 486, width: 90, height: 28)
button.bezelStyle = .rounded
window.contentView?.addSubview(button)
scroll.reset()
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
app.run()
