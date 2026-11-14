import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

struct Pixels: Equatable {
    let width: Int
    let height: Int
    var data: [UInt8]
    let page: [UInt8]

    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // 테스트는 최적화 없이 돌고, 그때 합성된 비교는 노트 하나에 몇 초가 걸리므로 바이트 단위로 비교한다.
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
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
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
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        self.init(image, page: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    }

    private init(width: Int, height: Int, data: [UInt8], page: [UInt8]) {
        (self.width, self.height, self.data, self.page) = (width, height, data, page)
    }

    var image: CGImage? {
        CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: Self.space,
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

    // 안티에일리어싱 가장자리와 상자의 옅은 색은 이 값보다 낮고, 글자와 선과 테두리는 이 값을 넘는다.
    static let inkLevel = 40

    func ink(in rect: CGRect) -> Int {
        let r = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !r.isNull, !r.isEmpty else { return 0 }
        let (pr, pg, pb, level) = (Int(page[0]), Int(page[1]), Int(page[2]), Self.inkLevel)
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

    func difference(from other: Pixels, tolerance: Int = 32) -> (count: Int, picture: Pixels)? {
        guard width == other.width, height == other.height else { return nil }
        var out = data
        var count = 0
        data.withUnsafeBufferPointer { a in
            other.data.withUnsafeBufferPointer { b in
                out.withUnsafeMutableBufferPointer { o in
                    var i = 0
                    while i < a.count {
                        if abs(Int(a[i]) - Int(b[i])) > tolerance || abs(Int(a[i + 1]) - Int(b[i + 1])) > tolerance
                            || abs(Int(a[i + 2]) - Int(b[i + 2])) > tolerance
                        {
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

// 글꼴은 macOS마다 조금씩 다르게 그려지므로, 그림은 만든 곳에서만 비교한다. 러너의 macOS는 그림 옆의 `machine.txt`에 적는다. 다른 곳에서는 비교를 건너뛰지만, CI처럼
// `FOLIO_NOTE_SCREENS_STRICT`를 켜면 새 러너 이미지에서 검사를 멈추지 않고 실패한다.
enum NoteScreens {
    static let references = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(
        path: "references/notes")
    static let environment = ProcessInfo.processInfo.environment
    static let out = environment["FOLIO_NOTE_SCREENS"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
    static let strict = !(environment["FOLIO_NOTE_SCREENS_STRICT"] ?? "").isEmpty
    static let machine = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    static var recorded: String? {
        (try? String(contentsOf: references.appending(path: "machine.txt"), encoding: .utf8))?.trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    // 글꼴 갱신으로 생기는 차이는 그림의 이 비율보다 작고, 빠진 글 한 줄, 1pt 밀린 블록, 다른 색으로 그린 상자는 이 비율을 훨씬 넘는다.
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
                Issue.record(
                    "References were made on \(recorded ?? "an unknown machine"), this is \(machine). \(whereKept)",
                    sourceLocation: sourceLocation)
            }
            return
        }
        guard let (count, picture) = shot.difference(from: reference) else {
            keep(shot, name)
            Issue.record(
                "\(name) is \(shot.width)x\(shot.height), its reference \(reference.width)x\(reference.height). \(whereKept)",
                sourceLocation: sourceLocation)
            return
        }
        let limit = max(20, Int(Double(shot.width * shot.height) * allowed))
        guard count > limit else { return }
        keep(shot, name)
        keep(picture, "\(name)-diff")
        Issue.record(
            "\(name) differs from its reference in \(count) pixels (allowed \(limit)). \(whereKept)", sourceLocation: sourceLocation)
    }

    private static var whereKept: String {
        out.map { "The new picture is in \($0.path(percentEncoded: false)) (CI: the note-screens artifact)." }
            ?? "Set FOLIO_NOTE_SCREENS to keep it."
    }

    private static func keep(_ shot: Pixels, _ name: String) {
        guard let out else { return }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try? shot.write(to: out.appending(path: "\(name).png"))
        try? Data((machine + "\n").utf8).write(to: out.appending(path: "machine.txt"))
    }
}
