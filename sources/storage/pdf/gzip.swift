import CryptoKit
import FolioDomain
import FolioTectonic
import Foundation

// Tectonic은 SyncTeX 데이터를 gzip으로 쓴다. Foundation은 맨 DEFLATE 스트림만 풀므로, 패키지를 더하지 않고 gzip
// 머리와 꼬리(RFC 1952)를 여기서 건너뛴다.
public enum Gzip {
    public struct NotGzip: Error {}

    public static func inflate(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { throw NotGzip() }
        let flags = bytes[3]
        var at = 10
        if flags & 0x04 != 0 {
            guard at + 2 <= bytes.count else { throw NotGzip() }
            at += 2 + Int(bytes[at]) + Int(bytes[at + 1]) << 8
        }
        for flag in [UInt8(0x08), 0x10] where flags & flag != 0 {
            while at < bytes.count, bytes[at] != 0 { at += 1 }
            at += 1
        }
        if flags & 0x02 != 0 { at += 2 }
        guard at < bytes.count - 8 else { throw NotGzip() }
        return try (Data(bytes[at..<(bytes.count - 8)]) as NSData).decompressed(using: .zlib) as Data
    }
}
