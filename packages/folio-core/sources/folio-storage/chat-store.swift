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

    /// The course's conversations, most recently updated first.
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

    static let contextTextExtensions: Set<String> = ["md", "tex", "txt", "csv", "py", "c", "cpp", "java", "swift"]

    /// Whether `contextText(ofMaterial:)` can read this file.
    public static func canReadContext(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "pdf" || contextTextExtensions.contains(ext)
    }

    /// Text of a course file for Claude's context: PDF text through PDFKit, text files as they are. Nil for other kinds.
    /// Reading downloads an iCloud placeholder, which is what the spec wants for files handed to Claude.
    public func contextText(ofMaterial path: String) throws -> String? {
        let url = url.appending(path: path)
        if url.pathExtension.lowercased() == "pdf" {
            return PDFDocument(data: try CoordinatedFile.read(url))?.string
        }
        guard Self.contextTextExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return String(decoding: try CoordinatedFile.read(url), as: UTF8.self)
    }

    /// The images `body` embeds, read from the course folder and shrunk to JPEG for Claude. Files outside the course
    /// or that don't decode are left out.
    public func contextImages(of note: NoteFile, body: String, limit: Int = 20) -> [(name: String, data: Data)] {
        let root = url.standardizedFileURL.path + "/"
        return NoteImages.references(in: body).compactMap { ref -> (String, Data)? in
            let candidates: [URL] = switch ref {
            case .path(let p): [note.url.deletingLastPathComponent().appending(path: p)]
            case .name(let n): [noteAssetsURL.appending(path: n), notesURL.appending(path: n), note.url.deletingLastPathComponent().appending(path: n)]
            }
            guard let file = candidates.map(\.standardizedFileURL).first(where: { $0.path.hasPrefix(root) && FileManager.default.fileExists(atPath: $0.path) }),
                  let data = try? CoordinatedFile.read(file), let jpeg = Self.contextJPEG(data) else { return nil }
            return (file.lastPathComponent, jpeg)
        }
        .prefix(limit).map { $0 }
    }

    /// 1568px on the long edge: Claude scales anything larger down to about that, so sending more only costs upload.
    static func contextJPEG(_ data: Data, maxEdge: Int = 1568) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxEdge,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
