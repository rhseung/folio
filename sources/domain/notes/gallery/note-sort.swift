import Foundation

public enum NoteSort: String, CaseIterable, Codable, Sendable {
    case modified, created, title
    // 회차 날짜, 시험일, 단원 목록의 순서다.
    case course
}
