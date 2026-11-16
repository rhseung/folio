import AVFoundation
import SwiftUI

struct ImagePane: View {
    let url: URL
    @State private var image: Image?
    @State private var size: CGSize = .zero
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFit()
                    .frame(maxWidth: size.width, maxHeight: size.height)
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView(
                    String(localized: .fileViewCannotRead), systemImage: "photo", description: Text(url.lastPathComponent))
            } else {
                ProgressView()
            }
        }
        .task(id: url) { await load() }
    }

    func load() async {
        let url = url
        let decoded = await Task.detached { () -> (PlatformImage, CGSize)? in
            guard let data = try? Data(contentsOf: url), let image = PlatformImage(data: data) else { return nil }
            return (image, image.size)
        }.value
        guard let (platform, pixels) = decoded else {
            failed = true
            return
        }
        #if os(macOS)
        image = Image(nsImage: platform)
        #else
        image = Image(uiImage: platform)
        #endif
        size = pixels
    }
}
