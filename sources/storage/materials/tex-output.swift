import CryptoKit
import FolioDomain
import FolioTectonic
import Foundation

public enum TexOutput {
    public static func folder(for source: URL) -> URL {
        let key = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory.appending(path: "folio-tex").appending(path: key)
    }
}
