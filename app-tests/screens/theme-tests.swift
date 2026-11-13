import FolioDomain
import Foundation
import Testing

@testable import Folio

struct ThemeTests {
    // CourseColor keeps its own copy of the light values to read an old #RRGGBB; a preset that read as another
    // name would mean the two copies drifted apart.
    @Test func presetsReadAsThemselves() {
        #expect(CourseAccent.presets.map(\.name) == CourseColor.presets)
        for preset in CourseAccent.presets {
            #expect(CourseColor.token(String(format: "#%06X", preset.accent.light), position: 0) == preset.name)
        }
    }

    // A `.prominent` button writes white on the fill; 4.5:1 is what body text needs.
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
