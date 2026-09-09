import Foundation

public struct FolderFile {
    public let url: URL
    public let name: String
    public let isFolder: Bool
    public let modified: Date
    public let size: Int

    public init(url: URL) throws {
        let values = try url.resourceValues(forKeys: [.localizedNameKey, .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey])
        self.url = url
        name = values.localizedName ?? url.lastPathComponent
        isFolder = values.isDirectory == true && values.isPackage != true
        modified = values.contentModificationDate ?? .distantPast
        size = values.fileSize ?? 0
    }
}

public enum FolderSort: String, CaseIterable {
    case name, modified, kind, size

    public var title: String {
        switch self {
        case .name: return "이름순"
        case .modified: return "수정일순"
        case .kind: return "종류순"
        case .size: return "크기순"
        }
    }
}

public enum FolderFiles {
    public static func list(_ folder: URL, sort: FolderSort) throws -> [FolderFile] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.localizedNameKey, .isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])
        return try urls.map(FolderFile.init).sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            switch sort {
            case .modified where a.modified != b.modified: return a.modified > b.modified
            case .size where a.size != b.size: return a.size > b.size
            case .kind where a.url.pathExtension != b.url.pathExtension:
                return a.url.pathExtension.localizedStandardCompare(b.url.pathExtension) == .orderedAscending
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    public static func destination(for source: URL, in folder: URL) throws -> URL {
        let origin = source.resolvingSymlinksInPath().standardizedFileURL
        let parent = folder.resolvingSymlinksInPath().standardizedFileURL
        let target = parent.appendingPathComponent(source.lastPathComponent)
        // 폴더를 자기 자신 또는 하위 폴더로 복사·이동하지 않습니다.
        if parent.pathComponents.starts(with: origin.pathComponents) || target == origin {
            throw failure("같은 위치 또는 원본 폴더 내부로 복사하거나 이동할 수 없습니다.")
        }
        if FileManager.default.fileExists(atPath: target.path) {
            throw failure("‘\(source.lastPathComponent)’ 항목이 이미 있습니다. 기존 파일은 변경하지 않았습니다.")
        }
        return target
    }

    public static func transfer(_ sources: [URL], to folder: URL, move: Bool) throws {
        let targets = try sources.map { try destination(for: $0, in: folder) }
        guard Set(targets).count == targets.count else {
            throw failure("선택한 항목 사이에 같은 이름이 있습니다. 파일을 한 번에 옮길 수 없습니다.")
        }
        for (source, target) in zip(sources, targets) {
            if move { try FileManager.default.moveItem(at: source, to: target) }
            else { try FileManager.default.copyItem(at: source, to: target) }
        }
    }

    public static func namedURL(_ name: String, in folder: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains(":"), !name.contains("\0") else {
            throw failure("유효한 파일 또는 폴더 이름을 입력해 주세요.")
        }
        let url = folder.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw failure("같은 이름의 항목이 이미 있습니다.")
        }
        return url
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "MouseWheelFix.FolderHub", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
