#if os(macOS)
import AppKit
import Testing
@testable import Folio

struct DarkPaperTests {
    let paper = DarkPaper.theme
    let grid: [SIMD3<Double>] = {
        let steps = stride(from: 0.0, through: 1.0, by: 0.25)
        return steps.flatMap { r in steps.flatMap { g in steps.map { b in SIMD3(r, g, b) } } }
    }()

    func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Bool { ((a - b) * (a - b)).sum() < 1e-12 }

    @Test func whitePaperAndBlackTypeLandOnTheThemeCardAndInk() {
        #expect(close(paper.apply(.one), DarkPaper.rgb(Swatch.card.dark)))
        #expect(close(paper.apply(.zero), DarkPaper.rgb(Swatch.text.dark)))
    }

    @Test func aRedStaysRed() {
        let red = paper.apply(SIMD3(1, 0, 0))
        #expect(red.x > red.y && red.x > red.z)
    }

    @Test func flippingTwiceGivesTheColorBack() {
        for v in grid { #expect(close(DarkPaper.flip(DarkPaper.flip(v)), v)) }
    }

    // `source(of:)`는 쪽 사이의 간격을 칠한다. 토큰이 바뀌어 어느 채널에서 잉크와 종이 색이 거의 같아지면, 요청하는 색이 그릴 수 있는 범위를 벗어나 간격 색이 틀어진다.
    @Test func theGapColorComesBackThroughTheFilter() throws {
        let hex = Swatch.lineSoft.dark
        let color = try #require(paper.source(of: hex).usingColorSpace(.sRGB))
        let source = SIMD3(Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
        #expect(source.min() >= 0 && source.max() <= 1)
        #expect(close(paper.apply(source), DarkPaper.rgb(hex)))
    }
}
#endif
