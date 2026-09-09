import Foundation
import XCTest

final class LocalizationTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/AppLocalization/Resources")
    }

    private func strings(_ language: String) throws -> [String: String] {
        let data = try Data(contentsOf: resources.appendingPathComponent("\(language).lproj/Localizable.strings"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
    }

    func testTranslationsCoverBothLanguagesAndPreserveArguments() throws {
        let korean = try strings("ko")
        let english = try strings("en")
        XCTAssertEqual(Set(korean.keys), Set(english.keys))
        let placeholder = try NSRegularExpression(pattern: "%(?:ld|u|@)")
        for key in korean.keys {
            let source = try XCTUnwrap(korean[key])
            let translated = try XCTUnwrap(english[key])
            XCTAssertFalse(translated.isEmpty, key)
            func arguments(_ text: String) -> [String] {
                placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    .map { (text as NSString).substring(with: $0.range) }
            }
            XCTAssertEqual(arguments(source), arguments(translated), key)
        }
        XCTAssertEqual(String(format: try XCTUnwrap(english["선택한 %ld개 항목을 휴지통으로 이동할까요?"]), 3), "Move the selected items (3) to the Trash?")
    }
}
