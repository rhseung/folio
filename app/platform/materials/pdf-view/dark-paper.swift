import CoreImage
import Observation
import PDFKit
import SwiftUI

#if os(macOS)
// PDF의 다크 모드를 색 행렬 하나로 만든다. 색마다 색상은 그대로 두고 밝기만 뒤집으며(빨강은 빨강으로 남는다), 흰 종이와 검은 글자는 순수한 검정과 흰색 대신 테마의 다크 카드와 잉크 색이 된다. 뒤집기는
// 모든 채널에 `v + (1 - 2 luma(v))`이다. luma만으로 만들었으므로 색을 회색 축 방향으로만 옮겨 채도를 지킨다. 또 자기 자신의 역함수라서, `source(of:)`가 원하는 출력을 내는 입력을
// 이것으로 구한다. layer 필터는 선형 광도에서 돌므로 행렬을 tone curve로 감싸 sRGB 값에서 동작하게 한다. 토큰의 hex 값이 sRGB이고, sRGB에서는 뒤집은 중간 회색이 여전히 중간 회색으로
// 보인다.
struct DarkPaper {
    static let luma = SIMD3<Double>(0.299, 0.587, 0.114)
    static let theme = DarkPaper(paper: Swatch.card.dark, ink: Swatch.text.dark)

    let paper: SIMD3<Double>, ink: SIMD3<Double>

    init(paper: UInt32, ink: UInt32) {
        self.paper = Self.rgb(paper)
        self.ink = Self.rgb(ink)
    }

    static func rgb(_ hex: UInt32) -> SIMD3<Double> {
        SIMD3(Double(hex >> 16 & 0xFF), Double(hex >> 8 & 0xFF), Double(hex & 0xFF)) / 255
    }

    static func flip(_ v: SIMD3<Double>) -> SIMD3<Double> {
        v + SIMD3(repeating: 1 - 2 * (luma * v).sum())
    }

    func apply(_ v: SIMD3<Double>) -> SIMD3<Double> {
        paper + (ink - paper) * Self.flip(v)
    }

    func source(of hex: UInt32) -> NSColor {
        let v = Self.flip((Self.rgb(hex) - paper) / (ink - paper))
        return NSColor(srgbRed: v.x, green: v.y, blue: v.z, alpha: 1)
    }

    var filters: [CIFilter] {
        let scale = ink - paper
        func row(_ i: Int) -> CIVector {
            var weights = -2 * Self.luma
            weights[i] += 1
            weights *= scale[i]
            return CIVector(x: weights.x, y: weights.y, z: weights.z, w: 0)
        }
        let matrix = CIFilter(name: "CIColorMatrix")!
        matrix.setValue(row(0), forKey: "inputRVector")
        matrix.setValue(row(1), forKey: "inputGVector")
        matrix.setValue(row(2), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: ink.x, y: ink.y, z: ink.z, w: 0), forKey: "inputBiasVector")
        return [
            CIFilter(name: "CILinearToSRGBToneCurve")!, matrix, CIFilter(name: "CIColorClamp")!, CIFilter(name: "CISRGBToneCurveToLinear")!,
        ]
    }
}
#endif
