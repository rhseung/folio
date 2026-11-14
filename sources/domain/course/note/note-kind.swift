import Foundation

public enum NoteKind: String, Codable, Sendable, CaseIterable {
    case rough, review
    case examSummary = "exam_summary"
    // 단원 노트는 예전에 주제 노트였다. 파일에는 `topic`으로 적혀 있고, 마이그레이션하지 않고 그대로 읽는다.
    case unit = "topic"
    case free
}
