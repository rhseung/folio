import Foundation

// 문제집 PDF에서 문제 칸의 크기다. half 두 개가 한 쪽에 들어가고 full은 한 쪽을 다 쓴다. 문제 뽑기에서 Claude가 풀이 분량을 보고
// 정한다. 문제 형식으로 정하지 않는 것은 짧은 증명도 반 쪽에 들어가기 때문이다.
public enum ProblemSize: String, Codable, Sendable, CaseIterable {
    case half, full

    // Claude가 크기를 정하지 않은 문제(크기가 생기기 전에 뽑은 문제, Claude가 쓴 문제)의 크기다. 서술은 풀이 분량을 모르므로 쪽을
    // 다 주고, 답이 짧은 형식은 반 쪽을 준다. 서술을 반 쪽에 두면 풀이가 칸을 넘을 수 있지만, 쪽을 다 주면 남을 뿐이다.
    public static func fallback(for format: ProblemFormat) -> ProblemSize {
        format == .written ? .full : .half
    }
}
