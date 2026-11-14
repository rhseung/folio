import Foundation

public enum LocalFile {
    public static func read(_ url: URL) -> Data? { try? CoordinatedFile.read(url) }
    public static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    // 조정된 읽기는 iCloud 자리표시자를 내려받으므로, 파일을 직접 읽는 보기(PDFKit, Quick Look)가 그 자리에서 내용을
    // 찾는다.
    public static func download(_ url: URL) -> URL? {
        guard exists(url) else { return nil }
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { _ in }
        return error == nil ? url : nil
    }
    public static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
