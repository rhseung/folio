import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Folio

@MainActor
struct NoteImagesTests {
    // 휴대폰 사진 크기의 그림을 원본대로 두면 한 장에 약 48MB를 쓴다. 말풍선이 쓰는 크기로 줄여 읽는지 본다.
    @Test func photoIsReadAtBubbleSize() throws {
        let folder = URL.temporaryDirectory.appending(path: "note-images-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "photo.png")
        try writePicture(width: 4000, height: 3000, to: url)

        let picture = try #require(NoteImages.picture(at: url))
        #expect(picture.image.size == CGSize(width: 480, height: 360))
        #expect(picture.bytes <= 960 * 720 * 4 + 720 * 64)
        #expect(NoteImages.load("photo.png", base: folder)?.size == CGSize(width: 480, height: 360))
    }

    private func writePicture(width: Int, height: Int, to url: URL) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
