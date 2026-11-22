import CoreImage
import FolioDomain
import PDFKit

// 문제지 PDF의 칸(문제의 그림)을 비트맵으로 그린다. 쪽의 회전과 다크 종이를 PDF 보기와 같게 다룬다.
enum PDFRegionRenderer {
    struct Crop: Sendable {
        var image: CGImage
        // PDF에서 잘라 낸 칸의 크기(pt)다.
        var size: CGSize
    }

    // 칸을 `grow(크기)`배로 키운 크기에 `pixelsPerPoint`의 픽셀로 그린다. 다크면 PDF 보기와 같은 `DarkPaper`로 밝기를 뒤집는다.
    nonisolated static func render(
        _ url: URL, region: ProblemRegion, dark: Bool = false, pixelsPerPoint: CGFloat, grow: (CGSize) -> CGFloat = { _ in 1 }
    ) -> (crop: Crop, grow: CGFloat)? {
        guard let page = PDFDocument(url: url)?.page(at: region.page - 1) else { return nil }
        // 칸은 쪽을 돌려 보이는 모양을 기준으로 한다. `draw(with:to:)`가 쪽의 회전을 적용해 그 모양으로 그린다.
        let box = page.bounds(for: .cropBox)
        let size = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let r = region
        let crop = CGRect(x: r.x * size.width, y: r.y * size.height, width: r.width * size.width, height: r.height * size.height)
        guard crop.width > 0, crop.height > 0 else { return nil }
        let factor = grow(crop.size), scale = factor * pixelsPerPoint
        let width = Int((crop.width * scale).rounded(.up)), height = Int((crop.height * scale).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -crop.minX, y: -(size.height - crop.maxY))
        page.draw(with: .cropBox, to: context)
        guard let drawn = context.makeImage(), let shown = dark ? darkened(drawn) : drawn else { return nil }
        return (Crop(image: shown, size: crop.size), factor)
    }

    nonisolated private static func darkened(_ image: CGImage) -> CGImage? {
        var output = CIImage(cgImage: image)
        for filter in DarkPaper.theme.filters {
            filter.setValue(output, forKey: kCIInputImageKey)
            guard let next = filter.outputImage else { return image }
            output = next
        }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
