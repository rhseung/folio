import Foundation

public enum PageText {
    // PDFKit은 쪽 글에서 그림과 도형 자리에 이 문자를 넣는다. 이 문자를 낱말로 세면 라벨이 붙은 도표 하나가 글 이백
    // 낱말로 읽혔고, 글에 남겨 두면 발췌가 낱말 대신 이 문자로 채워졌다.
    public static let figure: Character = "\u{FFFC}"
    public static let titleLines = 4

    public static func words(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0 == figure }).count
    }

    public static func figures(_ text: String) -> Int {
        text.reduce(0) { $1 == figure ? $0 + 1 : $0 }
    }

    public static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let words = line.split(whereSeparator: { $0.isWhitespace || $0 == figure })
            return words.isEmpty ? nil : words.joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    // 그림 자리 문자만 있는 줄은 슬라이드의 줄로 세지 않는다. 도표의 그림 자리 문자가 쪽 맨 앞에 나와서 제목 앞의
    // 줄 수를 다 써 버린 일이 있었다.
    public static func title(_ lines: [(text: String, size: Double)]) -> String? {
        var best: (size: Double, title: String)?
        var counted = 0
        for line in lines {
            let text = line.text.trimmingCharacters(in: blank)
            guard !text.isEmpty else { continue }
            if line.size > (best?.size ?? 0) { best = (line.size, text) }
            counted += 1
            if counted >= titleLines { break }
        }
        return best?.title
    }

    public static let blank = CharacterSet.whitespaces.union(CharacterSet(charactersIn: String(figure)))
}

public enum ReadingLimit {
    public static let pages = 30
    public static let titles = 400
    public static let pageText = 40_000
    public static let images = 8
    public static let transcript = 20_000
    // Claude는 이보다 큰 그림을 이 크기 정도로 줄이므로, 더 크게 보내면 업로드 비용만 든다.
    public static let imageEdge = 1568

    public static func clamp(_ asked: ClosedRange<Int>?, count: Int) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        let first = max(asked?.lowerBound ?? 1, 1), last = min(asked?.upperBound ?? count, count)
        return first <= last ? first...last : nil
    }

    public static func served(_ asked: ClosedRange<Int>, most: Int, lengths: [Int] = [], budget: Int = .max) -> ClosedRange<Int> {
        let capped = min(asked.count, max(most, 1))
        var taken = 0, used = 0
        while taken < capped {
            let length = taken < lengths.count ? lengths[taken] : 0
            if taken > 0, used + length > budget { break }
            used += length
            taken += 1
        }
        return asked.lowerBound...(asked.lowerBound + taken - 1)
    }

    public static func next(after served: ClosedRange<Int>, asked: ClosedRange<Int>, most: Int) -> ClosedRange<Int>? {
        guard served.upperBound < asked.upperBound else { return nil }
        let first = served.upperBound + 1
        return first...min(asked.upperBound, first + max(most, 1) - 1)
    }
}

extension LectureTranscript {
    // `from` 시점에 아직 말하는 중인 줄도 넣는다. 링크로 연 시점이 문장 뒤가 아니라 문장 중간부터 시작하게 하기 위해서다.
    // 그 줄은 `from`보다 1초 넘게 이어져야 한다. `next`는 초 단위로 적으므로, 이 조건이 없으면 자른 지점 직전 1초 안에
    // 끝난 줄이 다음 읽기의 처음에 다시 나오고, 긴 줄은 거듭 나온다.
    public func window(from: TimeInterval?, to: TimeInterval?, budget: Int = ReadingLimit.transcript) -> (
        lines: [Line], next: TimeInterval?
    ) {
        let inside = lines.filter { line in
            (from.map { line.start >= $0 || line.end >= $0 + 1 } ?? true) && (to.map { line.start < $0 } ?? true)
        }
        var used = 0
        for (i, line) in inside.enumerated() {
            used += line.text.count + 1
            if i > 0, used > budget { return (Array(inside[..<i]), line.start) }
        }
        return (inside, nil)
    }
}
