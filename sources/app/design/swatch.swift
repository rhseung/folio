import FolioDomain
import SwiftUI

struct Swatch {
    let light: UInt32, dark: UInt32

    var color: Color { Color(light: light, dark: dark) }

    static let card = Swatch(light: 0xFFFFFF, dark: 0x272624)
    static let fill = Swatch(light: 0xEDEBE6, dark: 0x33312E)
    static let codeFill = Swatch(light: 0xF5F4F0, dark: 0x33312E)
    static let line = Swatch(light: 0xD9D5CC, dark: 0x3A3835)
    static let lineSoft = Swatch(light: 0xE2DED6, dark: 0x302E2B)
    static let text = Swatch(light: 0x1F1E1C, dark: 0xEEEDEA)
    static let textSecondary = Swatch(light: 0x56524C, dark: 0xBAB6AF)
    static let textTertiary = Swatch(light: 0x7A766F, dark: 0x8F8A83)
}
