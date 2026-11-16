import FolioDomain
import FolioMarkdown
import Markdown

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor enum NoteImages {
    private static var cache: [URL: (date: Date?, image: PlatformImage)] = [:]

    static func url(_ source: String, base: URL?) -> URL? {
        let decoded = source.removingPercentEncoding ?? source
        guard !decoded.hasPrefix("http"), let base else { return nil }
        return decoded.hasPrefix("/") ? URL(filePath: decoded) : base.appending(path: decoded)
    }

    static func load(_ source: String, base: URL?) -> PlatformImage? {
        guard let url = url(source, base: base) else { return nil }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let hit = cache[url], hit.date == date { return hit.image }
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return nil }
        #else
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
        #endif
        cache[url] = (date, image)
        return image
    }
}
