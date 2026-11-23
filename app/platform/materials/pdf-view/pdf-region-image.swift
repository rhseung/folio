import FolioDomain
import SwiftUI

// 문제지 PDF의 한 칸(문제의 그림)을 PDF에서 바로 잘라 그린다. 다시 그린 그림이 아니라 원본 쪽의 그 자리다. 누르면 크게 보는
// 시트가 뜬다.
struct PDFRegionImage: View {
    let url: URL?
    let region: ProblemRegion
    // 그림의 이름표(PDF의 10–11pt 글자)를 앱 본문 크기로 읽게 적어도 이만큼 키운다. 자리가 좁으면 그 폭에 맞춰 줄인다.
    var least: CGFloat = 1.5  // design: one-off, 거리가 아니라 확대 배율이다
    // 작은 칸(그림 하나, 70pt 남짓)은 너비나 높이가 이만큼이 될 때까지 더 키운다.
    var readable: CGFloat = Theme.Size.figureReadable
    var zoomable = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @State private var picture: Picture?
    @State private var zoomed = false

    var body: some View {
        let key = Key(
            url: url, region: region, dark: scheme == .dark, displayScale: max(displayScale, 1), least: least, readable: readable)
        Group {
            if let picture {
                let image = Image(decorative: picture.image, scale: CGFloat(picture.image.width) / picture.width).resizable()
                    .scaledToFit().frame(maxWidth: picture.width, alignment: .leading)
                if zoomable {
                    Button {
                        zoomed = true
                    } label: {
                        image.contentShape(.rect)
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(Text(.studyFigureZoom))
                    .accessibilityLabel(Text(.studyFigureZoom))
                } else {
                    image
                }
            } else {
                Color.clear.frame(height: Theme.Size.touchTarget)
            }
        }
        .task(id: key) { picture = await Task.detached(priority: .userInitiated) { Self.render(key) }.value }
        .sheet(isPresented: $zoomed) { RegionZoom(url: url, region: region) }
    }

    private struct Picture: Sendable {
        var image: CGImage
        // 화면에 보이는 가장 큰 너비(pt)다.
        var width: CGFloat
    }

    private struct Key: Equatable, Sendable {
        var url: URL?
        var region: ProblemRegion
        var dark: Bool
        var displayScale: CGFloat
        var least: CGFloat
        var readable: CGFloat
    }

    // 너비와 높이 중 먼저 `readable`에 닿는 쪽까지 키운다. 길쭉한 칸이 한 방향으로 너무 커지지 않게 하기 위해서다.
    nonisolated private static func render(_ key: Key) -> Picture? {
        guard let url = key.url,
            let drawn = PDFRegionRenderer.render(
                url, region: key.region, dark: key.dark, pixelsPerPoint: key.displayScale,
                grow: { size in max(key.least, min(key.readable / size.width, key.readable / size.height)) })
        else { return nil }
        return Picture(image: drawn.crop.image, width: drawn.crop.size.width * drawn.grow)
    }
}

// 그림 하나를 크게 보는 시트다. 그림이 시트보다 크면 스크롤한다.
private struct RegionZoom: View {
    let url: URL?
    let region: ProblemRegion
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.m) {
            Button(.commonClose) { dismiss() }.keyboardShortcut(.cancelAction)
            ScrollView([.horizontal, .vertical]) {
                PDFRegionImage(url: url, region: region, least: 2.5, readable: Theme.Size.figureZoom, zoomable: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(Theme.Space.xl)
        #if os(macOS)
        .frame(minWidth: Theme.Size.figureZoom, minHeight: Theme.Size.figureZoom * 3 / 4)
        #else
        .presentationSizing(.page)
        #endif
        .background(Theme.Palette.page)
    }
}
