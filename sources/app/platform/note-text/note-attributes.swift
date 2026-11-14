import FolioDomain
import FolioMarkdown
import Markdown

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 스타일링마다 색 객체를 새로 만들어 객체로는 같지 않으므로, 그리는 결과로 비교한다.
enum NoteAttributes {
    static func same(_ a: NSAttributedString, _ b: NSAttributedString, in range: NSRange) -> Bool {
        var i = range.location
        while i < NSMaxRange(range) {
            var ra = NSRange(), rb = NSRange()
            let x = a.attributes(at: i, effectiveRange: &ra), y = b.attributes(at: i, effectiveRange: &rb)
            guard same(x, y) else { return false }
            i = min(NSMaxRange(ra), NSMaxRange(rb))
        }
        return true
    }

    static func same(_ x: [NSAttributedString.Key: Any], _ y: [NSAttributedString.Key: Any]) -> Bool {
        x.count == y.count && x.allSatisfy { key, value in y[key].map { same(value, $0) } ?? false }
    }

    static func same(_ x: Any?, _ y: Any?) -> Bool {
        switch (x, y) {
        case (nil, nil): return true
        case let (a as PlatformColor, b as PlatformColor): return a === b || a.cgColor == b.cgColor
        case let (a as NSObject, b as NSObject): return a.isEqual(b)
        default: return false
        }
    }
}
