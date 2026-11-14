import Foundation
import Markdown

public enum DisplayWidth {
    public static func of(_ text: String) -> Int {
        text.reduce(0) { $0 + of($1) }
    }

    static func of(_ ch: Character) -> Int {
        var zero = true
        for s in ch.unicodeScalars {
            let v = s.value
            if wide(v) { return 2 }
            if !(0x0300...0x036F).contains(v), !(0x200B...0x200F).contains(v), !(0xFE00...0xFE0F).contains(v),
                !(0x1160...0x11FF).contains(v), s.properties.generalCategory != .nonspacingMark
            {
                zero = false
            }
        }
        return zero ? 0 : 1
    }

    static func wide(_ v: UInt32) -> Bool {
        (0x1100...0x115F).contains(v) || (0x2E80...0x303E).contains(v) || (0x3041...0x33FF).contains(v)
            || (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v) || (0xA000...0xA4CF).contains(v)
            || (0xA960...0xA97F).contains(v) || (0xAC00...0xD7A3).contains(v) || (0xF900...0xFAFF).contains(v)
            || (0xFE30...0xFE4F).contains(v) || (0xFF00...0xFF60).contains(v) || (0xFFE0...0xFFE6).contains(v)
            || (0x1F300...0x1F64F).contains(v) || (0x1F900...0x1F9FF).contains(v) || (0x20000...0x3FFFD).contains(v)
    }
}
