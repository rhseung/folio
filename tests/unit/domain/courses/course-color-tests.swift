import Testing

@testable import FolioDomain

struct CourseColorTests {
    @Test func namesPassThroughAndEmptyFallsBackByPosition() {
        #expect(CourseColor.token("teal", position: 0) == "teal")
        #expect(CourseColor.token("graphite", position: 0) == "graphite")
        #expect(CourseColor.token("", position: 2) == "orange")
        #expect(CourseColor.token("mauve", position: 9) == "blue")
    }

    @Test func theOldGrayReadsAsGraphite() {
        #expect(CourseColor.token("gray", position: 3) == "graphite")
    }

    @Test func graphiteIsOfferedButNeverPickedForAnUnsetColor() {
        #expect(CourseColor.presets == CourseColor.cycle + ["graphite"])
        #expect(CourseColor.cycle == ["violet", "blue", "orange", "green", "pink", "olive", "teal", "red"])
        let picked = Set((0..<64).flatMap { [CourseColor.token("", position: $0), CourseColor.token("#zzzzzz", position: $0)] })
        #expect(picked == Set(CourseColor.cycle))
    }

    @Test func savedHexReadsAsTheNearestPreset() {
        #expect(CourseColor.token("#2F7FE0", position: 0) == "blue")
        #expect(CourseColor.token("#1B2A6B", position: 0) == "blue")
        #expect(CourseColor.token("#C4473A", position: 0) == "red")
        #expect(CourseColor.token("#FFD000", position: 0) == "orange")
        #expect(CourseColor.token("#zzzzzz", position: 1) == "blue")
    }

    @Test func savedGrayHexReadsAsGraphite() {
        #expect(CourseColor.token("#7F7F7F", position: 0) == "graphite")
        #expect(CourseColor.token("#706C66", position: 0) == "graphite")
        #expect(CourseColor.token("#4A4A4A", position: 0) == "graphite")
        #expect(CourseColor.token("#B0B0B0", position: 0) == "graphite")
        #expect(CourseColor.token("#8A8A8A", position: 0) == "graphite")
        #expect(CourseColor.token("#6B7B8C", position: 0) == "graphite")
        #expect(CourseColor.token("#7A6E64", position: 0) == "graphite")
    }

    @Test func mutedColorsKeepTheirHue() {
        #expect(CourseColor.token("#8A8A3C", position: 0) == "olive")
        #expect(CourseColor.token("#4F7A6A", position: 0) == "green")
        #expect(CourseColor.token("#5A6E9A", position: 0) != "graphite")
    }

    @Test func everyColoredPresetHasAnAnchor() {
        #expect(CourseColor.anchors.map(\.name) == CourseColor.cycle)
    }
}
