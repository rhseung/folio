import FolioCore
import Foundation

// 단원 행의 둘째 줄과 단원 페이지가 그리는 진척이다.
public struct UnitProgress: Sendable, Equatable {
    public var unitId: UUID
    public var done: Bool
    // 단원의 렉처 쪽 구간에서 본 쪽과 전체 쪽이다.
    public var pagesSeen: Int
    public var pagesTotal: Int
    // 단원에 이은 자료에서 본 쪽이다. 쪽 수를 모르므로 본 쪽만 센다.
    public var otherPagesSeen: Int
    public var notes: Int
    public var problemsSolved: Int
    public var problemsTotal: Int
    public var problemsWrong: Int
    public var cardsFlipped: Int
    public var cardsTotal: Int
    public var cardsUnknown: Int
    public var readiness: UnitReadiness
}
