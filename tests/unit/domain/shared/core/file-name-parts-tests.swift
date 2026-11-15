import Testing

@testable import FolioDomain

struct FileNamePartsTests {
    static func parts(_ name: String, isFolder: Bool = false) -> String {
        let parts = FileNameParts(name, isFolder: isFolder)
        return parts.stem + "|" + parts.suffix
    }

    @Test func splitsTheExtension() {
        #expect(Self.parts("05_Matchings.pdf") == "05_Matchings|.pdf")
        #expect(Self.parts("archive.tar.gz") == "archive.tar|.gz")
        #expect(Self.parts("report.download") == "report|.download")
    }

    @Test func keepsNamesWithoutAnExtensionWhole() {
        #expect(Self.parts("HW03") == "HW03|")
        #expect(Self.parts("robot.v2", isFolder: true) == "robot.v2|")
        #expect(Self.parts(".gitignore") == ".gitignore|")
        #expect(Self.parts("Lecture 3. Matchings") == "Lecture 3. Matchings|")
        #expect(Self.parts("notes.verylongtail") == "notes.verylongtail|")
    }
}
