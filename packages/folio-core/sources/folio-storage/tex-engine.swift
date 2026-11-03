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
        if !run.made, Self.missesAFile(run.output) {
            run = try self.run(source, outDir: outDir, pdf: pdf, cachedOnly: false)
        }
        var issues = TexLog.issues(run.output)
        if !run.made, !issues.contains(where: { $0.severity == .error }) {
            issues.insert(TexIssue(.error, message: run.output.split(whereSeparator: \.isNewline).last.map(String.init) ?? "tectonic"), at: 0)
        }
        return Build(pdf: run.made ? pdf : nil, issues: issues)
    }

    /// A package or `\input` file Tectonic hasn't fetched yet, which an online build may find. With nothing cached at
    /// all, as on the first build, the format file is missing too and the message is different.
    static func missesAFile(_ output: String) -> Bool {
        output.contains("not found") || output.contains("failed to open input file")
    }

    private func run(_ source: URL, outDir: URL, pdf: URL, cachedOnly: Bool) throws -> (output: String, made: Bool) {
        try? FileManager.default.removeItem(at: pdf)
        let process = Process()
        process.executableURL = executable
        // Deterministic mode leaves the build time out of the PDF, so rebuilding an unchanged source gives the same
        // bytes and nothing new for iCloud to sync or for `course.json` to rehash.
        process.arguments = ["-X", "compile", "-Z", "deterministic-mode"] + (cachedOnly ? ["--only-cached"] : [])
            + ["--outdir", outDir.path, source.lastPathComponent]
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

    /// One folder per source, reused by every build of it, so builds don't pile up in the temporary folder.
    public static func outputFolder(for source: URL) -> URL {
        let key = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory.appending(path: "folio-tex").appending(path: key)
    }
}
#endif
