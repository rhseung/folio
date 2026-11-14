import FolioDomain
import Foundation
import Testing

@testable import Folio

struct ThemeTests {
    // `CourseColor`는 옛 #RRGGBB를 읽으려고 라이트 값의 사본을 따로 가진다. 프리셋이 다른 이름으로 읽힌다면 두 사본이 서로 어긋났다는 뜻이다.
    @Test func presetsReadAsThemselves() {
        #expect(CourseAccent.presets.map(\.name) == CourseColor.presets)
        for preset in CourseAccent.presets {
            #expect(CourseColor.token(String(format: "#%06X", preset.accent.light), position: 0) == preset.name)
        }
    }

    // `.prominent` 버튼은 채운 색 위에 흰 글자를 쓰고, 본문 글자에는 4.5:1의 대비가 필요하다.
    @Test func whiteReadsOnEveryFill() {
        func luminance(_ hex: UInt32) -> Double {
            let channel = { (shift: UInt32) -> Double in
                let v = Double((hex >> shift) & 0xFF) / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        for (name, accent) in CourseAccent.presets + [("gray", CourseAccent.gray)] {
            for fill in [accent.fillLight, accent.fillDark] {
                #expect(1.05 / (luminance(fill) + 0.05) >= 4.5, "\(name) \(String(format: "%06X", fill))")
            }
        }
    }
}
