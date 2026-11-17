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

    // 픽셀만 줄이고 크기는 원본을 열었을 때와 같게 둔다. 말풍선은 `size`를 보고 맞추므로, 줄인 픽셀 수로 크기를 정하면 작은 도식까지 작게 보인다.
    static func picture(at url: URL) -> (image: PlatformImage, bytes: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: largestEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var width = properties[kCGImagePropertyPixelWidth] as? Int ?? image.width
        var height = properties[kCGImagePropertyPixelHeight] as? Int ?? image.height
        // 원본의 픽셀 크기는 회전하기 전의 것이고 줄인 그림은 EXIF 방향대로 돌린 것이라, 방향이 다르면 바꾼다.
        if (width > height) != (image.width > image.height) { swap(&width, &height) }
        let bytes = image.bytesPerRow * image.height
        #if os(macOS)
        // `NSImage(contentsOf:)`처럼 DPI로 pt를 정한다. 144dpi 화면 캡처는 픽셀의 절반 크기다.
        let dpi = properties[kCGImagePropertyDPIWidth] as? Double ?? 72
        let points = 72 / (dpi > 0 ? dpi : 72)
        return (NSImage(cgImage: image, size: CGSize(width: Double(width) * points, height: Double(height) * points)), bytes)
        #else
        return (UIImage(cgImage: image, scale: CGFloat(image.width) / CGFloat(max(width, 1)), orientation: .up), bytes)
        #endif
    }
}
