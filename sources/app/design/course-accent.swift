import FolioDomain
import SwiftUI

struct CourseAccent: Hashable {
    let light: UInt32, dark: UInt32
    // tint 위에서 읽히도록 `color`보다 어둡게 둔다(카드와 페이지 위의 tint에서 4.5:1).
    let inkLight: UInt32, inkDark: UInt32
    // 흰 글자 뒤에 깔도록 `color`를 흰색 대비 4.5:1까지 어둡게 한다. 다크에서 잉크는 tint 위의 글에 필요한 옅은 색이라
    // 흰 글자가 묻히므로, 잉크로는 채울 수 없다.
    let fillLight: UInt32, fillDark: UInt32

    var color: Color { Color(light: light, dark: dark) }
    var ink: Color { Color(light: inkLight, dark: inkDark) }
    var fill: Color { Color(light: fillLight, dark: fillDark) }
    var tint: Color { color.opacity(Theme.Opacity.tint) }
    var read: Color { color.opacity(Theme.Opacity.onTint) }

    static let gray = CourseAccent(
        light: 0x706C66, dark: 0x9A98A8, inkLight: 0x4A4741, inkDark: 0xC9C7D6, fillLight: 0x706C66, fillDark: 0x747287)

    // 라이트 값은 `CourseColor.anchors`와 같아야 한다.
    static let presets: [(name: String, accent: CourseAccent)] = [
        ("violet", .init(light: 0x8B7CF6, dark: 0xA49CFE, inkLight: 0x5B45BA, inkDark: 0xC2BFFF, fillLight: 0x705DF4, fillDark: 0x685AFD)),
        ("blue", .init(light: 0x3B5BDB, dark: 0x87A7FF, inkLight: 0x2D48C6, inkDark: 0xAEC5FF, fillLight: 0x3B5BDB, fillDark: 0x3067FF)),
        ("orange", .init(light: 0xE9A02C, dark: 0xFFB547, inkLight: 0x7E5101, inkDark: 0xFCC77F, fillLight: 0xA16911, fillDark: 0xA86400)),
        ("green", .init(light: 0x2D7A62, dark: 0x77BBA3, inkLight: 0x0C634C, inkDark: 0x93D4BC, fillLight: 0x2D7A62, fillDark: 0x407F69)),
        ("pink", .init(light: 0xFF3D7F, dark: 0xFF799B, inkLight: 0xAD004C, inkDark: 0xFFADBE, fillLight: 0xE8004F, fillDark: 0xE9003B)),
        ("olive", .init(light: 0x8A8A3C, dark: 0xC9C25A, inkLight: 0x5C5C22, inkDark: 0xE0DA8A, fillLight: 0x787834, fillDark: 0x7B7628)),
        ("teal", .init(light: 0x1D8FA8, dark: 0x4CC3D9, inkLight: 0x125F70, inkDark: 0x8ADCEA, fillLight: 0x1A7E94, fillDark: 0x1F7F91)),
        ("red", .init(light: 0xFF6B4A, dark: 0xFE8165, inkLight: 0xA92602, inkDark: 0xFEB19F, fillLight: 0xE02900, fillDark: 0xDF2A01)),
        (
            "graphite",
            .init(light: 0x6E6B66, dark: 0xA8A49E, inkLight: 0x46433E, inkDark: 0xD2CEC8, fillLight: 0x6E6B66, fillDark: 0x79746C)
        ),
    ]

    static func resolve(token stored: String, position: Int) -> CourseAccent {
        let token = CourseColor.token(stored, position: position)
        return presets.first { $0.name == token }?.accent ?? presets[0].accent
    }
}
