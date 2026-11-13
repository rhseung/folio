import FolioDomain
import FolioMarkdown
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

extension Chat: StoredModel {
    public static let schemaVersion = 1
}

extension CourseStore {
    var chatsURL: URL { metadataURL.appending(path: StandardLayout.chatsFolder) }

    public func chats() throws -> [StoredDocument<Chat>] {
        guard FileManager.default.fileExists(atPath: chatsURL.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: chatsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try StoredDocument<Chat>.read(from: $0) }
            .sorted { $0.model.updatedAt > $1.model.updatedAt }
    }

    public func save(_ chat: StoredDocument<Chat>) throws {
        try chat.write(to: chatsURL.appending(path: "\(chat.model.id.uuidString).json"))
    }

    static func isContextText(_ format: MaterialFormat) -> Bool { format == .markdown || format.isText }

    public static func canReadContext(_ path: String) -> Bool {
        let format = MaterialFormat(path: path)
        return format == .pdf || isContextText(format)
    }

    public func contextText(ofMaterial path: String) throws -> String? {
        let url = url.appending(path: path)
        let format = MaterialFormat(path: path)
        if format == .pdf {
            return PDFDocument(data: try CoordinatedFile.read(url))?.string
        }
        guard Self.isContextText(format) else { return nil }
        return String(decoding: try CoordinatedFile.read(url), as: UTF8.self)
    }

    public func contextImages(of note: NoteFile, body: String, limit: Int = 20) -> [(name: String, data: Data)] {
        NoteImages.references(in: body).compactMap { ref -> (String, Data)? in
            guard let file = imageURL(ref, of: note), let data = try? CoordinatedFile.read(file), let jpeg = Self.contextJPEG(data) else {
                return nil
            }
            return (file.lastPathComponent, jpeg)
        }
        .prefix(limit).map { $0 }
    }

    static func contextJPEG(_ data: Data, maxEdge: Int = ReadingLimit.imageEdge) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxEdge,
                ] as CFDictionary)
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
