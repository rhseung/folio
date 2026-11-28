import Foundation

// 노트에 정리류 콜아웃(정리, 명제, 따름정리, 보조정리처럼 증명이 붙는 종류)이 있는지 줄만 훑어 본다. 시험 계획이 노트를 저장할
// 때마다 과목의 정리 노트 모두에 묻는 물음이라, 수식 보호와 구문 분석을 거치는 `ParsedNote`를 쓰지 않는다. 콜아웃의 머리는
// 인용의 첫 줄이고, 코드 울타리 안의 줄은 본문이 아니다.
public enum CalloutScan {
    public static func hasProvable(_ text: String, callouts: CalloutTable = .standard) -> Bool {
        var fence: String?
        var quoted = false
        for row in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = row.drop { $0 == " " || $0 == "\t" }
            if let open = fence {
                if line.hasPrefix(open) { fence = nil }
                continue
            }
            if let mark = ["```", "~~~"].first(where: line.hasPrefix) {
                fence = mark
                quoted = false
                continue
            }
            guard line.first == ">" else {
                quoted = false
                continue
            }
            if !quoted, let header = CalloutHeader(line: String(line.dropFirst().drop { $0 == " " })), callouts.provable(header.type) {
                return true
            }
            quoted = true
        }
        return false
    }
}
