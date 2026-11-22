import FolioDomain
import Foundation

// 풀기 시트를 여는 요청이다. 문제를 고르면 그 문제를 바로 풀고, 비우면 단원이나 묶음의 문제로 시트가 고르기부터 시작한다.
struct SolveRequest: Identifiable, Equatable {
    var id = UUID()
    var course: UUID
    var units: [UUID] = []
    var set: UUID?
    var problems: [UUID] = []
    // 계획 항목에서 열면 풀기를 끝낼 때 그 항목을 체크한다(섞어 풀기, 모의시험).
    var planItem: UUID?
    var mode: SolveMode?
}
