import CoreImage
import FolioDomain
import PDFKit
import SwiftUI

// 문제지 PDF의 한 칸(문제의 그림)을 PDF에서 바로 잘라 그린다. 다시 그린 그림이 아니라 원본 쪽의 그 자리다. 다크 모드에서는
// PDF 보기와 같은 `DarkPaper`로 종이와 잉크의 밝기를 뒤집는다.
struct PDFRegionImage: View {
    let url: URL?
    let region: ProblemRegion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        let scale = Self.pixelsPerPoint(displayScale)
        Group {
            if let image {
                Image(decorative: image, scale: scale).resizable().scaledToFit()
                    .frame(maxWidth: CGFloat(image.width) / scale, alignment: .leading)
            } else {
                Color.clear.frame(height: Theme.Size.touchTarget)
            }
        }
        .task(id: Key(url: url, region: region, dark: scheme == .dark, scale: scale)) {
            let key = Key(url: url, region: region, dark: scheme == .dark, scale: scale)
            image = await Task.detached(priority: .userInitiated) { Self.render(key) }.value
        }
    }

    // 그림을 PDF의 크기보다 키워 보일 때도 흐리지 않게 화면 배율의 1.5배로 그린다.
    private static func pixelsPerPoint(_ displayScale: CGFloat) -> CGFloat { max(displayScale, 1) * 1.5 }

    private struct Key: Equatable, Sendable {
        var url: URL?
        var region: ProblemRegion
        var dark: Bool
        var scale: CGFloat
    }

    nonisolated private static func render(_ key: Key) -> CGImage? {
        guard let url = key.url, let page = PDFDocument(url: url)?.page(at: key.region.page - 1) else { return nil }
        // 칸은 쪽을 돌려 보이는 모양을 기준으로 한다. `draw(with:to:)`가 쪽의 회전을 적용해 그 모양으로 그린다.
        let box = page.bounds(for: .cropBox)
        let size = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
        let r = key.region
        let crop = CGRect(x: r.x * size.width, y: r.y * size.height, width: r.width * size.width, height: r.height * size.height)
        let width = Int((crop.width * key.scale).rounded(.up)), height = Int((crop.height * key.scale).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: key.scale, y: key.scale)
        context.translateBy(x: -crop.minX, y: -(size.height - crop.maxY))
        page.draw(with: .cropBox, to: context)
        guard let drawn = context.makeImage() else { return nil }
        return key.dark ? darkened(drawn) : drawn
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
