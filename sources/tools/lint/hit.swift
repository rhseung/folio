import SwiftSyntax

public struct Hit: Hashable, Sendable {
    public let check: String
    public let path: String
    public let line: Int
    // 기준선은 줄이 아니라 이 값으로 자리를 맞춘다. 그래서 위의 줄이 움직여도 자리가 자기 항목을 유지한다.
    public let key: String

    init(_ check: String, _ file: SourceFile, _ line: Int, _ key: String) {
        self.init(check, path: file.path, line, key)
    }

    init(_ check: String, path: String, _ line: Int, _ key: String) {
        self.check = check
        self.path = path
        self.line = line
        self.key = key.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public var entry: String { "\(check)\t\(path)\t\(key)" }
}
