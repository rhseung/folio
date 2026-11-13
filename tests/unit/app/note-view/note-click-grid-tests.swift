import Foundation
import Testing

@testable import Folio

@MainActor @Suite(.serialized, .timeLimit(.minutes(5)))
struct NoteClickGridTests {
    static let step: CGFloat = 40

    static func grid(_ size: CGSize, step: CGFloat = step) -> [[CGPoint]] {
        stride(from: step / 2, to: size.width, by: step).map { x in
            stride(from: step / 2, to: size.height, by: step).map { CGPoint(x: x, y: $0) }
        }
    }

    static func places(_ bench: NoteBench, _ check: (String) async -> Void) async {
        await bench.settle()
        await check("opened")
        await bench.scrollToEnd()
        let end = bench.scrollY
        await check("at the end")
        await bench.scroll(to: (end / 2).rounded())
        await check("halfway")
    }

    @Test(arguments: NoteShot.light)
    func everyPointHitsTheNote(_ shot: NoteShot) async {
        let bench = shot.bench(NoteBench.longNote)
        await Self.places(bench) { place in
            let points = Self.grid(bench.size).flatMap { $0 }
            let missed = points.compactMap { p -> String? in
                switch bench.hit(at: p) {
                case .note, .scroller: nil
                case .other(let what): "(\(Int(p.x)), \(Int(p.y))) \(what)"
                }
            }
            #expect(
                missed.isEmpty, "\(shot.name) \(place): \(missed.count) of \(points.count) points missed the note, as \(missed.prefix(6))")
        }
    }

    // 제목 위의 간격과 문단 아래의 간격을 합쳐도, 어느 줄도 곁의 점에서 이보다 멀리 있지 않다.
    static let reach: CGFloat = 56

    // 점마다 텍스트 뷰에 mouse-down을 온전히 보내므로, 캐럿 격자를 클릭 격자보다 성기게 둔다.
    static let caretStep: CGFloat = 80

    @Test(arguments: NoteShot.widths)
    func aClickPutsTheCaretWhereItLands(_ width: Int) async {
        let bench = NoteBench(.edit, NoteBench.longNote, width: CGFloat(width))
        await Self.places(bench) { place in
            bench.focus()
            let length = (bench.text as NSString).length
            // 입력기는 글의 맨 끝 자리에 대한 rect를 주지 않으므로 마지막 글자를 쓴다. 패널 밖에 있는 글도 마찬가지이며, 이때 노트의 끝은 모든 점보다 아래에 있다.
            let last = bench.rect(of: (bench.text as NSString).rangeOfCharacter(from: .newlines.inverted, options: .backwards))
            let end = last.maxY > 0 && last.minY < bench.size.height ? last.maxY : .infinity
            var wrong: [String] = []
            for column in Self.grid(bench.size, step: Self.caretStep) {
                var above = 0
                for p in column {
                    guard bench.hit(at: p) == .note else { continue }
                    // 캐럿을 노트의 먼 끝에서 시작하므로, 아무 일도 하지 않는 클릭은 캐럿을 닿지 않는 곳에 남긴다. 선택 영역은 두지 않는다. 선택 영역 안을 클릭하면 드래그가 시작되는지
                    // 기다리느라 테스트가 시간 초과로 끝났다.
                    bench.placeCaret(at: above < length / 2 ? length : 0)
                    let scrolled = bench.scrollY
                    bench.click(at: p)
                    let at = "(\(Int(p.x)), \(Int(p.y)))"
                    if abs(bench.scrollY - scrolled) > 0.5 {
                        wrong.append("\(at) moved the page by \(bench.scrollY - scrolled)")
                        bench.jump(to: scrolled)
                    }
                    guard let caret = bench.caret else {
                        wrong.append("\(at) selected text")
                        continue
                    }
                    if p.y > end {
                        if caret.location != length {
                            wrong.append("\(at) past the end, below \(Int(end)), put the caret at \(caret.location) of \(length)")
                        }
                    } else {
                        let off = p.y < caret.rect.minY ? caret.rect.minY - p.y : max(0, p.y - caret.rect.maxY)
                        if off > Self.reach { wrong.append("\(at) put the caret \(Int(off)) points away, at \(Int(caret.rect.minY))") }
                    }
                    if caret.location < above { wrong.append("\(at) put the caret at \(caret.location), before \(above) above it") }
                    above = caret.location
                }
            }
            #expect(wrong.isEmpty, "\(width) \(place): \(wrong.count) clicks went wrong, as \(wrong.prefix(6))")
        }
    }
}
