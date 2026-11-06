import CryptoKit
import FolioDomain
import Foundation

#if os(macOS)
/// Builds a `.tex` with Tectonic, chosen over a TeX Live install because it fetches only the packages a document
/// uses (#41). Nothing is written next to the source: the PDF lands in `outDir` and the caller places it.
public struct TexEngine: Sendable {
    public struct Build: Sendable, Equatable {
        public var pdf: URL?
        public var issues: [TexIssue]
        public var errors: [TexIssue] { issues.filter { $0.severity == .error } }
    }

    public let executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// An app started from Finder doesn't get the shell's PATH, so Homebrew's folders are tried by name.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> TexEngine? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let given = environment["FOLIO_TECTONIC"] { candidates.append(given) }
        candidates += ["/opt/homebrew/bin/tectonic", "/usr/local/bin/tectonic"]
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/tectonic" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { TexEngine(executable: URL(filePath: $0)) }
    }

    /// Blocks until Tectonic exits, which can take minutes the first time a package is fetched; the app calls it
    /// off the main thread.
    public func compile(_ source: URL, into outDir: URL) throws -> Build {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let pdf = outDir.appending(path: source.deletingPathExtension().lastPathComponent + ".pdf")
        // Online, Tectonic checks its package bundle on every build, which took a homework from half a second to
        // nine. Packages it already fetched are enough for most rebuilds; only a missing one needs the network.
        var run = try run(source, outDir: outDir, pdf: pdf, cachedOnly: true)
        var issues = TexLog.issues(run.output)
        if !run.made || Self.hasErrors(issues), Self.missesAFile(run.output) {
            run = try self.run(source, outDir: outDir, pdf: pdf, cachedOnly: false)
            issues = TexLog.issues(run.output)
        }
        if !run.made, !Self.hasErrors(issues) {
            issues.insert(TexIssue(.error, message: run.output.split(whereSeparator: \.isNewline).last.map(String.init) ?? "tectonic"), at: 0)
        }
        // Past an error Tectonic still writes a PDF, but with the broken parts left out; placed beside the source it
        // would replace a good one, possibly the copy to hand in.
        return Build(pdf: run.made && !Self.hasErrors(issues) ? pdf : nil, issues: issues)
    }

    private static func hasErrors(_ issues: [TexIssue]) -> Bool { issues.contains { $0.severity == .error } }

    /// Written by every build next to its PDF in the output folder, never beside the source, where it would be one more
    /// file in the course folder.
    public static func synctex(for source: URL) -> URL {
        outputFolder(for: source).appending(path: source.deletingPathExtension().lastPathComponent + ".synctex.gz")
    }

    /// A package or `\input` file Tectonic hasn't fetched yet, which an online build may find. With nothing cached at
    /// all, as on the first build, the format file is missing too and the message is different.
    static func missesAFile(_ output: String) -> Bool {
        output.contains("not found") || output.contains("failed to open input file")
    }

    private func run(_ source: URL, outDir: URL, pdf: URL, cachedOnly: Bool) throws -> (output: String, made: Bool) {
        try? FileManager.default.removeItem(at: pdf)
        // A build that dies before writing its own would otherwise leave the last one, made for other text.
        try? FileManager.default.removeItem(at: pdf.deletingPathExtension().appendingPathExtension("synctex.gz"))
        let process = Process()
        process.executableURL = executable
        // A fixed build time keeps the PDF's bytes the same for an unchanged source, so there is nothing new for iCloud
        // to sync or for `course.json` to rehash. It is set through the environment rather than `-Z deterministic-mode`,
        // which gives the same PDF but blanks the file names in the SyncTeX data, leaving no way to tell which file a
        // clicked line is in. Errors don't stop the build, so one build lists all of them.
        process.arguments = ["-X", "compile", "-Z", "continue-on-errors", "--synctex"] + (cachedOnly ? ["--only-cached"] : [])
            + ["--outdir", outDir.path, source.lastPathComponent]
        process.environment = ProcessInfo.processInfo.environment.merging(["SOURCE_DATE_EPOCH": "0"]) { _, fixed in fixed }
        // `\input` and `\includegraphics` paths are relative to the document's folder.
        process.currentDirectoryURL = source.deletingLastPathComponent()
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        // Read before waiting: a full pipe would otherwise stall Tectonic and this call with it.
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (text, process.terminationStatus == 0 && FileManager.default.fileExists(atPath: pdf.path))
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

    /// One folder per source, reused by every build of it, so builds don't pile up in the temporary folder.
    public static func outputFolder(for source: URL) -> URL {
        let key = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory.appending(path: "folio-tex").appending(path: key)
    }
}
#endif

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
