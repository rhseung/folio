import Foundation

// 다른 앱에서 받은 파일의 임시 사본이다. 파일 고르기와 끌어 놓기로 받은 URL은 받은 순간에만 읽을 수 있으므로 바로 복사해 둔다.
enum ReceivedFile {
    static func copy(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        // folio:not-an-action a temporary copy, outside the GIST folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appending(path: url.lastPathComponent)
        // folio:not-an-action a temporary copy, outside the GIST folder
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }

    // 들여올 때 쓸 이름으로 바꾼 사본을 `body`에 넘기고 지운다. 들여오기가 파일 이름을 그대로 쓰기 때문이다.
    static func renamed(_ url: URL, to name: String, _ body: (URL) -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        // folio:not-an-action a temporary copy, outside the GIST folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // folio:not-an-action a temporary copy, outside the GIST folder
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appending(path: name)
        // folio:not-an-action a temporary copy, outside the GIST folder
        try FileManager.default.copyItem(at: url, to: copy)
        body(copy)
    }
}
