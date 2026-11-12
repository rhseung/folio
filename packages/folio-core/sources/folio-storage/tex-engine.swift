import CryptoKit
import FolioDomain
import FolioTectonic
import Foundation

/// Builds a `.tex` with Tectonic, chosen over a TeX Live install because it fetches only the packages a document
/// uses (#41). It is linked into the app as a library (FolioTectonic, tectonic/), the same on the iPad, which lets no
/// app start another program, and on the Mac. Nothing is written next to the source: the PDF lands in `outDir` and the
/// caller places it.
public struct TexEngine: Sendable {
    public struct Build: Sendable, Equatable {
        public var pdf: URL?
        public var issues: [TexIssue]
        public var errors: [TexIssue] { issues.filter { $0.severity == .error } }
    }

    /// The fetched packages and formats. Caches, so the system may empty it and the next build fetches them again; on
    /// the Mac it is the folder a Homebrew Tectonic uses, so the two share what they fetched.
    public let cache: URL

    public init(cache: URL) {
        self.cache = cache
    }

    public static let shared = TexEngine(cache: URL.cachesDirectory.appending(path: "Tectonic"))

    /// Blocks until Tectonic is done, which can take minutes the first time a package is fetched; the app calls it
    /// off the main thread. Builds run one at a time.
    public func compile(_ source: URL, into outDir: URL, at now: Date, calendar: Calendar) throws -> Build {
        let epoch = TexBuildTime.sourceDateEpoch(at: now, calendar: calendar)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let pdf = outDir.appending(path: source.deletingPathExtension().lastPathComponent + ".pdf")
        // Online, Tectonic checks its package bundle on every build, which took a homework from half a second to
        // nine. Packages it already fetched are enough for most rebuilds; only a missing one needs the network. An empty
        // cache (a new install, or one the system cleared) has no bundle index to work offline from at all.
        let cached = hasCache
        var run = try run(source, outDir: outDir, pdf: pdf, epoch: epoch, cachedOnly: cached)
        var issues = TexLog.issues(run.output)
        if cached, !run.made || Self.hasErrors(issues), Self.missesAFile(run.output) {
            run = try self.run(source, outDir: outDir, pdf: pdf, epoch: epoch, cachedOnly: false)
            issues = TexLog.issues(run.output)
        }
        if !run.made, !Self.hasErrors(issues) {
            issues.insert(TexIssue(.error, message: run.output.split(whereSeparator: \.isNewline).last.map(String.init) ?? "Tectonic"), at: 0)
        }
        // Past an error Tectonic still writes a PDF, but with the broken parts left out; placed beside the source it
        // would replace a good one, possibly the copy to hand in.
        return Build(pdf: run.made && !Self.hasErrors(issues) ? pdf : nil, issues: issues)
    }

    private var hasCache: Bool {
        ["bundles", "formats"].allSatisfy { !((try? FileManager.default.contentsOfDirectory(atPath: cache.appending(path: $0).path)) ?? []).isEmpty }
    }

    private static func hasErrors(_ issues: [TexIssue]) -> Bool { issues.contains { $0.severity == .error } }

    /// Written by every build next to its PDF in the output folder, never beside the source, where it would be one more
    /// file in the course folder.
    public static func synctex(for source: URL) -> URL {
        outputFolder(for: source).appending(path: source.deletingPathExtension().lastPathComponent + ".synctex.gz")
    }

    /// A package or `\input` file Tectonic hasn't fetched yet, which an online build may find.
    static func missesAFile(_ output: String) -> Bool {
        output.contains("not found") || output.contains("failed to open input file")
    }

    private func run(_ source: URL, outDir: URL, pdf: URL, epoch: Int, cachedOnly: Bool) throws -> (output: String, made: Bool) {
        try? FileManager.default.removeItem(at: pdf)
        // A build that dies before writing its own would otherwise leave the last one, made for other text.
        try? FileManager.default.removeItem(at: pdf.deletingPathExtension().appendingPathExtension("synctex.gz"))
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        // A build time fixed to the day (`TexBuildTime`) keeps the PDF's bytes the same for an unchanged source, so
        // there is nothing new for iCloud to sync or for `course.json` to rehash. It is the build date rather than
        // deterministic mode, which gives the same PDF but blanks the file names in the SyncTeX data, leaving no way to
        // tell which file a clicked line is in. Errors don't stop the build, so one build lists all of them. `\input`
        // and `\includegraphics` paths are relative to the document's folder.
        var log: UnsafeMutablePointer<CChar>?
        let code = folio_tectonic_compile(source.path, outDir.path, cache.path, cachedOnly ? 1 : 0, Int64(epoch), &log)
        let text = log.map { String(cString: $0) } ?? ""
        folio_tectonic_free_string(log)
        return (text, code == 0 && FileManager.default.fileExists(atPath: pdf.path))
    }

    /// The SyncTeX data for `shown`, the PDF on screen. It belongs to the last build in the output folder, so it is
    /// only taken when that build's PDF is the shown one: a PDF built on another device, or a build that failed after
    /// it, would send clicks to the wrong lines.
    public static func syncTeX(for source: URL, showing shown: URL) -> SyncTeX? {
        let built = outputFolder(for: source).appending(path: source.deletingPathExtension().lastPathComponent + ".pdf")
        guard let ours = try? Data(contentsOf: built), let theirs = try? Data(contentsOf: shown), ours == theirs,
              let packed = try? Data(contentsOf: synctex(for: source)), let data = try? Gzip.inflate(packed) else { return nil }
        return SyncTeX(text: String(decoding: data, as: UTF8.self))
    }

    public static func outputFolder(for source: URL) -> URL { TexOutput.folder(for: source) }
}

/// Where a build of a `.tex` leaves its PDF. The build actions take a PDF only from here, so a file passed in can't put
/// itself over a course PDF.
public enum TexOutput {
    /// One folder per source, reused by every build of it, so builds don't pile up in the temporary folder.
    public static func folder(for source: URL) -> URL {
        let key = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory.appending(path: "folio-tex").appending(path: key)
    }
}

/// Tectonic writes SyncTeX data gzipped. Foundation inflates only a bare DEFLATE stream, so the gzip header and
/// trailer (RFC 1952) are stepped over here instead of adding a package for them.
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
