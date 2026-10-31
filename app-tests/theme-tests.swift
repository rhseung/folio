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
}
