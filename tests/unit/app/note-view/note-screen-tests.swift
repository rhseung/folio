import Foundation
import Testing

@testable import Folio

struct NoteShot: Sendable, CustomTestStringConvertible {
    let kind: NoteBench.Kind
    let dark: Bool
    let width: Int

    var name: String { "\(kind.rawValue)-\(dark ? "dark" : "light")-\(width)" }
    var testDescription: String { name }

    static let widths = [900, 480]
    static let all = NoteBench.Kind.allCases.flatMap { kind in
        [false, true].flatMap { dark in widths.map { NoteShot(kind: kind, dark: dark, width: $0) } }
    }
    static let light = all.filter { !$0.dark }

    @MainActor func bench(_ text: String) -> NoteBench { NoteBench(kind, text, width: CGFloat(width), dark: dark) }
}

@MainActor @Suite(.serialized, .timeLimit(.minutes(5)))
struct NoteScreenTests {
    @Test(arguments: NoteShot.all)
    func everyConstruct(_ shot: NoteShot) async {
        let bench = shot.bench(NoteBench.allMarkdown)
        await bench.settle()
        NoteScreens.check(await bench.wholeNote(), "\(shot.name)-all")
    }

    @Test(arguments: NoteShot.all)
    func aLongNoteOpenedAndAtItsEnd(_ shot: NoteShot) async {
        let bench = shot.bench(NoteBench.longNote)
        await bench.settle()
        NoteScreens.check(bench.snapshot(), "\(shot.name)-long-open")
        await bench.scrollToEnd()
        NoteScreens.check(bench.snapshot(), "\(shot.name)-long-end")
    }
}
