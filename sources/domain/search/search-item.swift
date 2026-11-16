import Foundation

public struct SearchItem: Sendable, Hashable {
    public var kind: SearchKind
    public var courseId: UUID
    public var id: UUID
    public var title: String
    public var body: String

    public init(kind: SearchKind, courseId: UUID, id: UUID, title: String, body: String = "") {
        self.kind = kind
        self.courseId = courseId
        self.id = id
        // Apple 파일 시스템은 파일 이름을 분해형(NFD)으로 돌려주는 일이 많고, 입력한 한글은 조합형(NFC)이다. 이
        // 변환이 없으면 입력한 `강의`가 `강의`라는 파일과 맞지 않는다.
        self.title = title.precomposedStringWithCanonicalMapping
        self.body = body.precomposedStringWithCanonicalMapping
    }
}
