@testable import FolioDomain
import Testing

struct CourseColorTests {
    @Test func namesPassThroughAndEmptyFallsBackByPosition() {
        #expect(CourseColor.token("teal", position: 0) == "teal")
        #expect(CourseColor.token("gray", position: 0) == "gray")
        #expect(CourseColor.token("", position: 2) == "orange")
        #expect(CourseColor.token("mauve", position: 9) == "blue")
    }

    @Test func savedHexReadsAsTheNearestPreset() {
        #expect(CourseColor.token("#2F7FE0", position: 0) == "blue")    // the old blue preset
        #expect(CourseColor.token("#1B2A6B", position: 0) == "blue")    // dark navy, not violet
        #expect(CourseColor.token("#C4473A", position: 0) == "red")     // the old red preset
        #expect(CourseColor.token("#FFD000", position: 0) == "orange")
        #expect(CourseColor.token("#7F7F7F", position: 0) == "gray")
        #expect(CourseColor.token("#zzzzzz", position: 1) == "blue")    // not hex: falls back by position
    }

    @Test func everyAnchorIsAPresetOrGray() {
        #expect(CourseColor.anchors.map(\.name) == CourseColor.presets + ["gray"])
    }
}
