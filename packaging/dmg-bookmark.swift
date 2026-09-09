import Foundation

let image = URL(fileURLWithPath: CommandLine.arguments[1])
let bookmark = try image.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
FileHandle.standardOutput.write(bookmark)
