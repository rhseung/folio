import Foundation

public enum InlineMark: Sendable {
    case bold, italic

    var width: Int {
        switch self {
        case .bold: 2
        case .italic: 1
        }
    }
}

extension SourceEditing {
    // 고른 글을 `**`나 `*`로 감싸거나 이미 감싼 표시를 벗긴다. `*`가 셋 이어진 `***글***`은 굵게이면서 기울임이므로
    // 이어진 `*`의 수(최대 3)를 비트로 읽는다. 굵게는 2, 기울임은 1의 비트다.
    public static func toggle(_ mark: InlineMark, in text: NSString, selection: NSRange) -> Edit {
        let n = mark.width
        let star = UInt16(UInt8(ascii: "*"))
        func run(from start: Int, step: Int, limit: Int) -> Int {
            var count = 0, i = start
            while count < 3, i >= 0, i < text.length, i != limit, text.character(at: i) == star {
                count += 1
                i += step
            }
            return count
        }
        let range = trimmed(selection, in: text)
        let start = range.location, end = NSMaxRange(range)

        let outside = min(run(from: start - 1, step: -1, limit: -1), run(from: end, step: 1, limit: text.length))
        if outside & n != 0 {
            let inner = text.substring(with: range)
            return Edit(
                range: NSRange(location: start - n, length: range.length + 2 * n), text: inner, caret: start - n,
                selected: range.length)
        }
        if range.length >= 2 * n {
            let inside = min(run(from: start, step: 1, limit: end), run(from: end - 1, step: -1, limit: start - 1))
            if inside & n != 0, range.length > 2 * n || inside == n {
                let inner = text.substring(with: NSRange(location: start + n, length: range.length - 2 * n))
                return Edit(range: range, text: inner, caret: start, selected: inner.utf16.count)
            }
        }
        let marker = String(repeating: "*", count: n)
        let inner = text.substring(with: range)
        return Edit(range: range, text: marker + inner + marker, caret: start + n, selected: range.length)
    }

    // `** 글**`은 CommonMark에서 강조가 되지 않으므로 고른 범위 양 끝의 공백은 표시 밖에 둔다.
    private static func trimmed(_ selection: NSRange, in text: NSString) -> NSRange {
        var start = selection.location, end = NSMaxRange(selection)
        let spaces = CharacterSet.whitespacesAndNewlines
        func isSpace(_ i: Int) -> Bool { UnicodeScalar(text.character(at: i)).map(spaces.contains) ?? false }
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }
        return selection.length > 0 && start == end ? selection : NSRange(location: start, length: end - start)
    }
}
