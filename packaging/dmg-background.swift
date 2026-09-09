import AppKit

let width = 660
let height = 440
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2, pixelsHigh: height * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let scale = NSAffineTransform()
scale.scale(by: 2)
scale.concat()

let navy = NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.27, alpha: 1)
let muted = NSColor(calibratedRed: 0.40, green: 0.43, blue: 0.47, alpha: 1)
let gold = NSColor(calibratedRed: 0.73, green: 0.53, blue: 0.24, alpha: 1)
NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.94, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// Finder 아이콘 위치와 맞추기 위해 위쪽 기준 좌표를 사용합니다.
func text(_ value: String, top: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    (value as NSString).draw(in: NSRect(x: 24, y: CGFloat(height) - top - size * 1.6, width: 612, height: size * 1.6), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ])
}

text("Dalbear", top: 34, size: 34, color: navy, weight: .bold)
text("내 Mac을 더 편하게.", top: 83, size: 14, color: muted)
for x in [CGFloat(175), CGFloat(485)] {
    NSColor.white.withAlphaComponent(0.8).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 68, y: 440 - 210 - 68, width: 136, height: 136), xRadius: 30, yRadius: 30).fill()
}
gold.setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 293, y: 230))
arrow.line(to: NSPoint(x: 365, y: 230))
arrow.move(to: NSPoint(x: 352, y: 243))
arrow.line(to: NSPoint(x: 365, y: 230))
arrow.line(to: NSPoint(x: 352, y: 217))
arrow.stroke()
text("Dalbear를 응용 프로그램 폴더로 드래그하세요", top: 311, size: 17, color: navy, weight: .medium)
text("복사한 뒤 응용 프로그램 폴더에서 실행해 주세요.", top: 344, size: 12, color: muted)
text("dalbear.com  ·  Apple Silicon  ·  macOS 13+", top: 399, size: 11, color: muted)

NSGraphicsContext.restoreGraphicsState()
bitmap.size = NSSize(width: width, height: height)
try bitmap.representation(using: .tiff, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
