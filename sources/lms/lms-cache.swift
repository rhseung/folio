import CryptoKit
import FolioDomain
import Foundation

// 마지막으로 읽은 LMS 내용을 이 기기의 Caches에 둔다. 앱을 켜면 다음 읽기를 기다리지 않고 보이고, 지워져도 다음
// 읽기가 다시 만든다. GIST 폴더에는 쓰지 않는다. 다른 계정으로 다시 연결했을 때 이전 계정의 내용을 보이지 않도록 계정을
// 함께 적는다. 학번이 파일에 그대로 남지 않도록 해시로 적는다.
public struct LMSCache: Sendable {
    struct Stored: Codable {
        var account: String
        var snapshot: LMSSnapshot
    }

    public let file: URL

    public init(file: URL) { self.file = file }

    public func read(account: String) -> LMSSnapshot? {
        guard let data = try? Data(contentsOf: file), let stored = try? Self.decoder.decode(Stored.self, from: data),
            stored.account == Self.hash(account)
        else { return nil }
        return stored.snapshot
    }

    // 캐시는 다시 만들 수 있으므로 쓰지 못해도 읽기를 실패로 만들지 않는다.
    public func write(_ snapshot: LMSSnapshot, account: String) {
        guard let data = try? Self.encoder.encode(Stored(account: Self.hash(account), snapshot: snapshot)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    public func remove() { try? FileManager.default.removeItem(at: file) }

    static func hash(_ account: String) -> String {
        SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
