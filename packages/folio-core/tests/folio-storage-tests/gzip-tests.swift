import FolioStorage
import Foundation
import Testing

struct GzipTests {
    @Test func inflatesWhatGzipWrote() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "hw.synctex")
        let text = String(repeating: "SyncTeX Version:1\nInput:1:/course/hw.tex\n", count: 50)
        try Data(text.utf8).write(to: file)

        // `-N` keeps the file name in the header, which Tectonic's output has too.
        let gzip = Process()
        gzip.executableURL = URL(filePath: "/usr/bin/gzip")
        gzip.arguments = ["-N", file.path]
        try gzip.run()
        gzip.waitUntilExit()
        let packed = try Data(contentsOf: folder.appending(path: "hw.synctex.gz"))
        #expect(String(decoding: try Gzip.inflate(packed), as: UTF8.self) == text)
        #expect(throws: Gzip.NotGzip.self) { try Gzip.inflate(Data(text.utf8)) }
    }
}
