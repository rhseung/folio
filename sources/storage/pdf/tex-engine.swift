import CryptoKit
import FolioDomain
import FolioTectonic
import Foundation

public struct TexEngine: Sendable {
    public struct Build: Sendable, Equatable {
        public var pdf: URL?
        public var issues: [TexIssue]
        public var errors: [TexIssue] { issues.filter { $0.severity == .error } }
    }

    public let cache: URL

    public init(cache: URL) {
        self.cache = cache
    }

    public static let shared = TexEngine(cache: URL.cachesDirectory.appending(path: "Tectonic"))

    public func compile(_ source: URL, into outDir: URL, at now: Date, calendar: Calendar) throws -> Build {
        let epoch = TexBuildTime.sourceDateEpoch(at: now, calendar: calendar)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let pdf = outDir.appending(path: source.deletingPathExtension().lastPathComponent + ".pdf")

        // 온라인으로 빌드하면 Tectonic이 빌드마다 패키지 번들을 확인해, 과제 하나의 빌드가 0.5초에서 9초로 늘었다.
        // 대부분의 다시 빌드는 이미 받은 패키지로 충분하고, 없는 패키지만 네트워크가 필요하다. 캐시가 비어 있으면(새로
        // 설치했거나 시스템이 비웠으면) 오프라인으로 빌드할 번들 색인이 없다.
        let cached = hasCache
        var run = try run(source, outDir: outDir, pdf: pdf, epoch: epoch, cachedOnly: cached)
        var issues = TexLog.issues(run.output)
        if cached, !run.made || Self.hasErrors(issues), Self.missesAFile(run.output) {
            run = try self.run(source, outDir: outDir, pdf: pdf, epoch: epoch, cachedOnly: false)
            issues = TexLog.issues(run.output)
        }
        if !run.made, !Self.hasErrors(issues) {
            issues.insert(
                TexIssue(.error, message: run.output.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Tectonic"), at: 0)
        }

        // 오류가 있어도 Tectonic은 깨진 부분을 뺀 PDF를 쓴다. 이 PDF를 원본 옆에 두면 멀쩡한 PDF, 어쩌면 제출할 사본을
        // 바꿔 버린다.
        return Build(pdf: run.made && !Self.hasErrors(issues) ? pdf : nil, issues: issues)
    }

    private var hasCache: Bool {
        ["bundles", "formats"].allSatisfy {
            !((try? FileManager.default.contentsOfDirectory(atPath: cache.appending(path: $0).path)) ?? []).isEmpty
        }
    }

    private static func hasErrors(_ issues: [TexIssue]) -> Bool { issues.contains { $0.severity == .error } }

    public static func synctex(for source: URL) -> URL {
        outputFolder(for: source).appending(path: source.deletingPathExtension().lastPathComponent + ".synctex.gz")
    }

    // xdvipdfmx만 읽는 글꼴(첫 `$x$`의 `cmmi10.pfb`)은 PDF를 쓸 때에야 없다는 것이 드러나고, xdvipdfmx는 그것을 자기
    // 문구로 알린다.
    static func missesAFile(_ output: String) -> Bool {
        output.contains("not found") || output.contains("failed to open input file")
            || output.contains("Could not locate a virtual/physical font")
    }

    private func run(_ source: URL, outDir: URL, pdf: URL, epoch: Int, cachedOnly: Bool) throws -> (output: String, made: Bool) {
        try? FileManager.default.removeItem(at: pdf)
        // 그러지 않으면 자기 파일을 쓰기 전에 멈춘 빌드가, 다른 글로 만든 마지막 파일을 남긴다.
        try? FileManager.default.removeItem(at: pdf.deletingPathExtension().appendingPathExtension("synctex.gz"))
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        // 빌드 시각을 날짜로 고정하면(`TexBuildTime`) 바뀌지 않은 원본의 PDF 바이트가 같아서, iCloud가 동기화하거나
        // `course.json`이 다시 해시할 것이 없다. deterministic 모드도 같은 PDF를 주지만 SyncTeX 데이터의 파일 이름을 비워,
        // 클릭한 줄이 어느 파일에 있는지 알 수 없게 된다. 그래서 빌드 날짜를 쓴다. 오류가 빌드를 멈추지 않으므로 한 번의
        // 빌드가 모든 오류를 보인다. `\input`과 `\includegraphics`의 경로는 문서 폴더 기준이다.
        var log: UnsafeMutablePointer<CChar>?
        let code = folio_tectonic_compile(source.path, outDir.path, cache.path, cachedOnly ? 1 : 0, Int64(epoch), &log)
        let text = log.map { String(cString: $0) } ?? ""
        folio_tectonic_free_string(log)
        return (text, code == 0 && FileManager.default.fileExists(atPath: pdf.path))
    }

    // SyncTeX 데이터는 출력 폴더의 마지막 빌드 것이므로 그 빌드의 PDF가 보이는 PDF일 때만 쓴다. 다른 기기에서 빌드한
    // PDF나 그 뒤에 실패한 빌드라면 클릭이 엉뚱한 줄로 간다.
    public static func syncTeX(for source: URL, showing shown: URL) -> SyncTeX? {
        let built = outputFolder(for: source).appending(path: source.deletingPathExtension().lastPathComponent + ".pdf")
        guard let ours = try? Data(contentsOf: built), let theirs = try? Data(contentsOf: shown), ours == theirs,
            let packed = try? Data(contentsOf: synctex(for: source)), let data = try? Gzip.inflate(packed)
        else { return nil }
        return SyncTeX(text: String(decoding: data, as: UTF8.self))
    }

    public static func outputFolder(for source: URL) -> URL { TexOutput.folder(for: source) }
}

public enum TexOutput {
    public static func folder(for source: URL) -> URL {
        let key = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory.appending(path: "folio-tex").appending(path: key)
    }
}

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
