import Foundation

public enum L10n {
    // 배포 앱은 Contents/Resources에서, Swift 패키지 실행은 생성된 번들에서 읽습니다.
    private static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "MouseWheelFix_AppLocalization", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    public static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: Locale.current, arguments: arguments)
    }
}
