import Foundation

// `-` 하나만 윗줄보다 들여 쓴 줄은 목록 항목을 시작하는 중(Enter 뒤 Tab)이지만, CommonMark는 이 줄을 setext 밑줄로
// 읽어 윗줄을 제목으로 만든다. 그래서 대시를 길이가 같은 비슷한 글자로 바꿔 오프셋과 줄이 원문과 맞게 한다.
public enum DraftItem {
    public static let lookAlike: Character = "\u{2010}"

    public static func dashes(in text: String) -> [Int] {
        var out: [Int] = []
        var offset = 0
        var previous: Substring?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let previous, !previous.allSatisfy(\.isWhitespace), line.trimmingCharacters(in: .whitespaces) == "-" {
                let indent = line.prefix { $0 == " " || $0 == "\t" }
                if indent.count > previous.prefix(while: { $0 == " " || $0 == "\t" }).count {
                    out.append(offset + indent.utf16.count)
                }
            }
            previous = line
            offset += line.utf16.count + 1
        }
        return out
    }

    public static func mask(_ text: String) -> String {
        let at = dashes(in: text)
        guard !at.isEmpty else { return text }
        let out = NSMutableString(string: text)
        for i in at { out.replaceCharacters(in: NSRange(location: i, length: 1), with: String(lookAlike)) }
        return out as String
    }
}
