import FolioDomain
import FolioMarkdown
import ImageIO
import Markdown

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum NoteImages {
    // 말풍선은 그림을 480x320pt 안에 그린다. 노트의 그림은 대개 휴대폰 사진(12MP, 풀면 약 48MB)이라, 원본을 두면 그림 몇 장을 지나는 것만으로
    // 수백 MB가 남는다. 그래서 Retina에서 말풍선을 채우는 크기로 줄여 읽고, 캐시는 메모리가 부족하면 시스템이 비우는 `NSCache`에 둔다.
    static let largestEdge = 960
    private static let cache: NSCache<NSURL, Entry> = {
        let cache = NSCache<NSURL, Entry>()
        cache.totalCostLimit = 64 * 1_048_576
        return cache
    }()

    private final class Entry {
        let date: Date?
        let image: PlatformImage
        init(date: Date?, image: PlatformImage) {
            self.date = date
            self.image = image
        }
    }

    static func url(_ source: String, base: URL?) -> URL? {
        let decoded = source.removingPercentEncoding ?? source
        guard !decoded.hasPrefix("http"), let base else { return nil }
        return decoded.hasPrefix("/") ? URL(filePath: decoded) : base.appending(path: decoded)
    }

    static func load(_ source: String, base: URL?) -> PlatformImage? {
        guard let url = url(source, base: base) else { return nil }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let hit = cache.object(forKey: url as NSURL), hit.date == date { return hit.image }
        guard let picture = picture(at: url) else { return nil }
        cache.setObject(Entry(date: date, image: picture.image), forKey: url as NSURL, cost: picture.bytes)
        return picture.image
    }

    // 크기는 pt로 돌려준다. 말풍선은 `size`로 배치하므로, 픽셀 크기 그대로 두면 Retina에서 그림이 두 배로 커진다.
    static func picture(at url: URL) -> (image: PlatformImage, bytes: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: largestEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let bytes = image.bytesPerRow * image.height
        #if os(macOS)
        return (NSImage(cgImage: image, size: CGSize(width: image.width / 2, height: image.height / 2)), bytes)
        #else
        return (UIImage(cgImage: image, scale: 2, orientation: .up), bytes)
        #endif
    }
}
