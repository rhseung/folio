import Foundation

/// How a PDF page's text reads, the same for the lecture splitter (#450) and the panel's `material read` (#85), so
/// what Claude reads of a page doesn't depend on who asked.
public enum PageText {
    /// PDFKit's stand-in for an image or a drawing in a page's text. Counted as a word it made a diagram of labels
    /// read as two hundred words of text, and left in it filled an excerpt in place of the words.
    public static let figure: Character = "\u{FFFC}"
    /// A slide's title sits in its first few lines. Reading the largest type on the whole page would take a big
    /// formula or a diagram's label instead.
    public static let titleLines = 4

    public static func words(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0 == figure }).count
    }

    public static func figures(_ text: String) -> Int {
        text.reduce(0) { $1 == figure ? $0 + 1 : $0 }
    }

    /// The page's text as Claude reads it: figures out, each line's whitespace run together, empty lines dropped.
    public static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let words = line.split(whereSeparator: { $0.isWhitespace || $0 == figure })
            return words.isEmpty ? nil : words.joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    /// The line set in the largest type among the page's first `titleLines` lines, in reading order with each line's
    /// largest font size (0 when it has none). A line of figures only isn't a line of the slide: a diagram's
    /// stand-ins came first on a page and used up the lines before its title.
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

    /// Blank around a line: spaces and figures.
    public static let blank = CharacterSet.whitespaces.union(CharacterSet(charactersIn: String(figure)))
}

/// How much one read hands Claude (#85). A tool's answer stays in the conversation for every later turn, so a whole
/// textbook in one answer would crowd out the rest; past a limit a read stops at a page or a line and says where to
/// go on.
public enum ReadingLimit {
    /// Pages of text per read.
    public static let pages = 30
    /// Pages of titles per read: skimming a deck for where things are.
    public static let titles = 400
    /// Characters of page text per read. A dense textbook page runs to a few thousand.
    public static let pageText = 40_000
    /// Pictures per read, pages or a note's images: about 1,800 tokens each at `imageEdge`.
    public static let images = 8
    /// Characters of transcript per read, about twenty minutes of a lecture.
    public static let transcript = 20_000
    /// The long side of a picture, in pixels: Claude scales anything larger down to about this, so more only costs
    /// upload. The panel's own page and note pictures use the same.
    public static let imageEdge = 1568

    /// `asked` (1-based, all pages when nil) kept to a file of `count` pages. Nil when it misses the file.
    public static func clamp(_ asked: ClosedRange<Int>?, count: Int) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        let first = max(asked?.lowerBound ?? 1, 1), last = min(asked?.upperBound ?? count, count)
        return first <= last ? first...last : nil
    }

    /// The pages one read serves of `asked`: at most `most` from its start, and of those as many as fit in `budget`
    /// characters of text, `lengths` giving each page's from the first. The first page always goes, however long.
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

    /// What to ask for after `served` to go on through `asked`, as many pages as one read takes: nil when done.
    public static func next(after served: ClosedRange<Int>, asked: ClosedRange<Int>, most: Int) -> ClosedRange<Int>? {
        guard served.upperBound < asked.upperBound else { return nil }
        let first = served.upperBound + 1
        return first...min(asked.upperBound, first + max(most, 1) - 1)
    }
}

extension LectureTranscript {
    /// The lines said between `from` and `to` (seconds, either open), cut at a line once `budget` characters are
    /// used; the first line always goes. `next` is where to start the next read when the cut came before `to`. A line
    /// still being spoken at `from` is in, so a moment from a link starts mid-sentence rather than after it.
    public func window(from: TimeInterval?, to: TimeInterval?, budget: Int = ReadingLimit.transcript) -> (lines: [Line], next: TimeInterval?) {
        let inside = lines.filter { line in
            (from.map { line.end > $0 || line.start >= $0 } ?? true) && (to.map { line.start < $0 } ?? true)
        }
        var used = 0
        for (i, line) in inside.enumerated() {
            used += line.text.count + 1
            if i > 0, used > budget { return (Array(inside[..<i]), line.start) }
        }
        return (inside, nil)
    }
}
