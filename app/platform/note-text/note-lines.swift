import FolioDomain
import FolioMarkdown
import Markdown

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 문단마다 가장 큰 글꼴과 줄 간격으로 줄 높이 하나를 정한다. 그래야 코드 구간이나 흐린 기호가 줄을 밀지 않고 문단의 모든 줄 높이가 같다. TextKit 2는 이 높이의 줄 바닥에 텍스트를 놓고 위쪽 간격은
// 비워 둔다. TextKit 2가 알리는 캐럿은 줄 전체 높이이므로 `caret`이 텍스트 높이로 자른다. `lineSpacing`만 쓰면 빈 줄의 캐럿이 텍스트가 있는 줄보다 간격만큼 더 길었다.
@MainActor enum NoteLines {
    static func fix(_ text: NSMutableAttributedString) {
        let ns = text.string as NSString
        var at = 0
        while at < ns.length {
            let p = ns.paragraphRange(for: NSRange(location: at, length: 0))
            at = NSMaxRange(p)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            text.enumerateAttribute(.font, in: p) { value, _, _ in
                guard let font = value as? PlatformFont else { return }
                ascent = max(ascent, font.ascender)
                descent = max(descent, -font.descender)
            }
            guard ascent > 0,
                let style = (text.attribute(.paragraphStyle, at: p.location, effectiveRange: nil) as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle
            else { continue }
            let natural = ascent + descent
            let height = ((natural + style.lineSpacing) / 2).rounded() * 2
            style.lineSpacing = 0
            style.minimumLineHeight = height
            style.maximumLineHeight = height
            text.addAttribute(.paragraphStyle, value: style, range: p)
            text.addAttribute(.noteCaret, value: natural.rounded(), range: p)
        }
    }

    static func caret(_ rect: CGRect, at offset: Int, in text: NSAttributedString) -> CGRect {
        let height =
            afterLastBreak(offset, in: text)
            ? bodyLine[.noteCaret] as? CGFloat
            : text.attribute(.noteCaret, at: min(offset, text.length - 1), effectiveRange: nil) as? CGFloat
        guard let height, height < rect.height else { return rect }
        return CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height)
    }

    static func afterLastBreak(_ offset: Int, in text: NSAttributedString) -> Bool {
        offset >= text.length && (text.length == 0 || (text.string as NSString).character(at: text.length - 1) == 0x0A)
    }

    static var bodyLine: [NSAttributedString.Key: Any] {
        let line = NSMutableAttributedString(
            string: "\n",
            attributes: [
                .font: NoteLook.font(NoteLook.body), .foregroundColor: NoteLook.text, .paragraphStyle: SourceStyler.paragraph(),
            ])
        fix(line)
        return line.attributes(at: 0, effectiveRange: nil)
    }
}
