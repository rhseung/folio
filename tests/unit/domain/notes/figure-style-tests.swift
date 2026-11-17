import FolioDomain
import Foundation
import Testing

struct FigureStyleTests {
    struct LCh {
        var l, c, h: Double
    }

    // sRGB hex를 OKLCH(밝기, 채도, 색조)로 바꾼다. 식은 Björn Ottosson의 OKLab 정의 그대로다.
    static func oklch(_ hex: String) -> LCh {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        let rgb = [(v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF].map { Double($0) / 255 }
            .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (rgb[0], rgb[1], rgb[2])
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let green = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let blue = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        return LCh(l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, c: hypot(green, blue), h: atan2(blue, green) * 180 / .pi)
    }

    @Test func darkPrimariesAreLighterAndCalmerInTheSameHue() {
        let primaries = FigureStyle.inks.filter { $0.name.hasPrefix("p-") }
        #expect(primaries.count == 6)
        for ink in primaries {
            let (light, dark) = (Self.oklch(ink.light), Self.oklch(ink.dark))
            #expect(dark.l > light.l, "\(ink.name)")
            #expect(dark.c < light.c, "\(ink.name)")
            let turn = abs(dark.h - light.h).truncatingRemainder(dividingBy: 360)
            #expect(min(turn, 360 - turn) < 10, "\(ink.name)")
        }
        #expect(Self.oklch(FigureStyle.ink.dark).l > 0.8)
        #expect(Self.oklch(FigureStyle.paper.dark).l < 0.3)
    }

    @Test func theFigureStyleCarriesBothThemes() {
        let css = FigureStyle.css
        #expect(css.contains(".p-blue{fill:#1A2FFF}.s-p-blue{stroke:#1A2FFF}"))
        let dark = css.split(separator: "@media (prefers-color-scheme: dark)").last.map(String.init) ?? ""
        #expect(dark.contains(".ink{fill:#E6E2DB}") && dark.contains("text{fill:#E6E2DB}"))
        #expect(css.contains(".sm{font-size:12px}") && css.contains(".bd{font-weight:700}"))
        #expect(FigureStyle.variables.contains("--p-red:#E8141C;") && FigureStyle.variables.contains("--figure-math-scale:1.21;"))
    }

    @Test func arrowheadsGrowWithTheLine() {
        let marker = FigureStyle.marker(FigureStyle.inks[4])
        #expect(marker.hasPrefix("<marker id=\"m-p-blue\" viewBox=\"0 0 11.5 8.6\" refX=\"9.9\" refY=\"4.3\""))
        #expect(marker.contains("markerWidth=\"5.75\" markerHeight=\"4.3\" markerUnits=\"strokeWidth\""))
        #expect(marker.contains("d=\"M0,0 L11.5,4.3 L0,8.6 L2.3,4.3 z\" class=\"p-blue\""))
    }

    @Test func theEngineGetsTheWholeTable() throws {
        let table = try JSONSerialization.jsonObject(with: Data(FigureStyle.engineJSON.utf8)) as? [String: Any]
        #expect(table?["css"] as? String == FigureStyle.css)
        #expect((table?["fills"] as? [String])?.count == FigureStyle.inks.count)
        #expect((table?["strokes"] as? [String])?.contains("s-grid") == true)
        #expect((table?["markers"] as? [String: String])?["m-ink"] == FigureStyle.marker(FigureStyle.ink))
        #expect((table?["sizes"] as? [String: Double])?[""] == 14)
    }
}
