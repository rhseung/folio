import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Folio

@MainActor
struct NoteImagesTests {
    // 휴대폰 사진 크기의 그림을 원본대로 두면 한 장에 약 48MB를 쓴다. 픽셀은 말풍선이 쓰는 만큼으로 줄이고, 크기는 원본 그대로 두는지 본다.
    @Test func photoIsReadAtBubbleSize() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writePicture(width: 4000, height: 3000, to: folder.appending(path: "photo.png"))

        let picture = try #require(NoteImages.picture(at: folder.appending(path: "photo.png")))
        #expect(picture.image.size == CGSize(width: 4000, height: 3000))
        #expect(picture.bytes <= 960 * 720 * 4 + 720 * 64)
        #expect(NoteImages.load("photo.png", base: folder)?.size == CGSize(width: 4000, height: 3000))
    }

    // 줄일 필요가 없는 작은 도식은 원본을 열었을 때와 같은 크기로 보여야 한다.
    @Test func smallPictureKeepsItsSize() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try writePicture(width: 400, height: 300, to: folder.appending(path: "figure.png"))

        let picture = try #require(NoteImages.picture(at: folder.appending(path: "figure.png")))
        #expect(picture.image.size == CGSize(width: 400, height: 300))
    }

    private static func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "note-images-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
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
