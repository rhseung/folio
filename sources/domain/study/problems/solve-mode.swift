import Foundation

public enum SolveMode: String, Codable, Sendable, CaseIterable {
    case typing, handwriting, mock

    // 필기와 모의시험은 문제집 PDF를 손으로 풀어 한 벌을 통째로 낸다(#577). 화면에서는 개념을 확인하는 짧은 문제만 푼다.
    public var onPaper: Bool { self != .typing }

    // 화면에서 풀려던 문제에 서술형이 섞이면 필기로 연다. 서술형은 화면에서 풀지 않기 때문이다(사용자 결정, #577).
    public static func fitting(_ requested: SolveMode?, formats: [ProblemFormat]) -> SolveMode {
        let mode = requested ?? .typing
        return mode == .typing && formats.contains { !$0.onScreen } ? .handwriting : mode
    }
}
