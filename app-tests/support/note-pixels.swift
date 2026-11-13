import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// A picture of a note view: 8-bit RGBA in sRGB, rows top down, one pixel a point. Drawn over the page color, so ink is
/// whatever differs from the page, however the view draws its own background.
struct Pixels: Equatable {
    let width: Int
    let height: Int
    var data: [UInt8]
    /// The page's red, green and blue.
    let page: [UInt8]

    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Byte by byte: the tests run unoptimized, where the synthesized comparison of a whole note takes seconds.
    static func == (a: Pixels, b: Pixels) -> Bool {
        a.width == b.width && a.height == b.height && a.page == b.page
            && a.data.withUnsafeBytes { x in b.data.withUnsafeBytes { y in memcmp(x.baseAddress, y.baseAddress, x.count) == 0 } }
    }

    init(_ image: CGImage, page: CGColor) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        var rgb: [UInt8] = [0, 0, 0]
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: Self.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let whole = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(page)
            context.fill(whole)
            if let first = context.data?.assumingMemoryBound(to: UInt8.self) { rgb = [first[0], first[1], first[2]] }
            context.draw(image, in: whole)
        }
        self.data = data
        self.page = rgb
    }

    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(image, page: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    }

    private init(width: Int, height: Int, data: [UInt8], page: [UInt8]) {
        (self.width, self.height, self.data, self.page) = (width, height, data, page)
    }

    var image: CGImage? {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: Self.space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func write(to url: URL) throws {
        guard let image, let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Antialiased edges and a box's faint tint stay under this; text, rules and borders go over it.
    static let inkLevel = 40

    /// Inked pixels in `rect`, cut to the picture.
    func ink(in rect: CGRect) -> Int {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isNull, !r.isEmpty else { return 0 }
        let (pr, pg, pb, level) = (Int(page[0]), Int(page[1]), Int(page[2]), Self.inkLevel)
        // Through a buffer, for the same reason as `==`.
        return data.withUnsafeBufferPointer { d in
            var count = 0
            for y in Int(r.minY)..<Int(r.maxY) {
                var i = (y * width + Int(r.minX)) * 4
                for _ in Int(r.minX)..<Int(r.maxX) {
                    if abs(Int(d[i]) - pr) > level || abs(Int(d[i + 1]) - pg) > level || abs(Int(d[i + 2]) - pb) > level { count += 1 }
                    i += 4
                }
            }
            return count
        }
    }

    /// Pixels that differ from `other` by more than `tolerance` in a channel, and a picture of where: this one faded,
    /// with the differences in red.
    func difference(from other: Pixels, tolerance: Int = 32) -> (count: Int, picture: Pixels)? {
        guard width == other.width, height == other.height else { return nil }
        var out = data
        var count = 0
        data.withUnsafeBufferPointer { a in
            other.data.withUnsafeBufferPointer { b in
                out.withUnsafeMutableBufferPointer { o in
                    var i = 0
                    while i < a.count {
                        if abs(Int(a[i]) - Int(b[i])) > tolerance || abs(Int(a[i + 1]) - Int(b[i + 1])) > tolerance || abs(Int(a[i + 2]) - Int(b[i + 2])) > tolerance {
                            count += 1
                            (o[i], o[i + 1], o[i + 2], o[i + 3]) = (255, 0, 0, 255)
                        } else {
                            for c in 0..<3 { o[i + c] = UInt8((Int(a[i + c]) + 3 * 255) / 4) }
                        }
                        i += 4
                    }
                }
            }
        }
        return (count, Pixels(width: width, height: height, data: out, page: page))
    }
}

/// The note views' reference screens in `references/notes`, made on CI's runner and compared against there.
///
/// Fonts draw a little differently from one macOS to the next, so a picture is compared only where it was made: the
/// runner's macOS is written to `machine.txt` beside the pictures. Elsewhere the comparison is skipped, unless
/// `FOLIO_NOTE_SCREENS_STRICT` is set, as on CI, where a new runner image must fail rather than stop checking.
///
/// A missing or different picture fails the test and leaves the new one (and where it differs, `<name>-diff.png`)
/// in `FOLIO_NOTE_SCREENS`, which CI uploads as the `note-screens` artifact. `mise run note-screens -- <run>` copies the
/// new pictures in as references.
enum NoteScreens {
    static let references = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "references/notes")
    static let environment = ProcessInfo.processInfo.environment
    static let out = environment["FOLIO_NOTE_SCREENS"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
    static let strict = !(environment["FOLIO_NOTE_SCREENS_STRICT"] ?? "").isEmpty
    static let machine = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    static var recorded: String? {
        (try? String(contentsOf: references.appending(path: "machine.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Differences a font update could make stay under this share of the picture; a missing line of text, a block
    /// moved by a point or a box drawn in another color go well over it.
    static let allowed = 0.0002

    static func check(_ shot: Pixels, _ name: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let file = references.appending(path: "\(name).png")
        guard let reference = Pixels(contentsOf: file) else {
            keep(shot, name)
            Issue.record("No reference screen \(name).png. \(whereKept)", sourceLocation: sourceLocation)
            return
        }
        guard recorded == machine else {
            keep(shot, name)
            if strict {
                Issue.record("References were made on \(recorded ?? "an unknown machine"), this is \(machine). \(whereKept)", sourceLocation: sourceLocation)
            }
            return
        }
        guard let (count, picture) = shot.difference(from: reference) else {
            keep(shot, name)
            Issue.record("\(name) is \(shot.width)x\(shot.height), its reference \(reference.width)x\(reference.height). \(whereKept)", sourceLocation: sourceLocation)
            return
        }
        let limit = max(20, Int(Double(shot.width * shot.height) * allowed))
        guard count > limit else { return }
        keep(shot, name)
        keep(picture, "\(name)-diff")
        Issue.record("\(name) differs from its reference in \(count) pixels (allowed \(limit)). \(whereKept)", sourceLocation: sourceLocation)
    }

    private static var whereKept: String {
        out.map { "The new picture is in \($0.path(percentEncoded: false)) (CI: the note-screens artifact)." } ?? "Set FOLIO_NOTE_SCREENS to keep it."
    }

    private static func keep(_ shot: Pixels, _ name: String) {
        guard let out else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? shot.write(to: out.appending(path: "\(name).png"))
        try? Data((machine + "\n").utf8).write(to: out.appending(path: "machine.txt"))
    }
}
