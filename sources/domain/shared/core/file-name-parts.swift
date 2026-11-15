import Foundation

// 긴 파일 이름을 줄일 때 끝까지 남길 확장자를 고른다. 보이는 모양만 나누고 파일 이름은 바꾸지 않는다.
public struct FileNameParts: Equatable, Sendable {
    public let stem: String
    public let suffix: String

    // 확장자로 보지 않는 것: 폴더 이름(`robot.v2`), 빈칸이 든 꼬리(`Lecture 3. Matchings`), 점으로 시작하는 이름(`.gitignore`),
    // 너무 긴 꼬리. 이런 이름은 전체를 하나로 줄인다.
    public init(_ name: String, isFolder: Bool = false) {
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        guard !isFolder, !ext.isEmpty, !stem.isEmpty, ext.count <= Self.longestExtension, !ext.contains(where: \.isWhitespace) else {
            self.stem = name
            suffix = ""
            return
        }
        self.stem = stem
        suffix = "." + ext
    }

    // 흔한 확장자는 8글자를 넘지 않는다(`numbers`, `download`). 그보다 긴 꼬리는 `notes.verylongtail`처럼 이름의 일부로 본다.
    static let longestExtension = 8
}
