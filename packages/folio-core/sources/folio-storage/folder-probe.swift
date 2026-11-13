import FolioDomain
import Foundation

/// Looks at a folder before the app opens it: what it holds (`FolderKind`) and whether its files are on this device.
public enum FolderProbe {
    /// The folder's first two levels by name. `FolderTree(contentsOf:)` walks the whole tree, which on a large iCloud
    /// folder took seconds on the first screen and asked iCloud for every placeholder on the way.
    public static func outline(of url: URL) throws -> FolderTree {
        func read(_ url: URL, levels: Int) throws -> FolderTree {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            guard isFolder else { return FolderTree(name: url.lastPathComponent, content: .file(size: 0)) }
            guard levels > 0 else { return FolderTree(name: url.lastPathComponent, content: .folder([])) }
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
                .map { try read($0, levels: levels - 1) }
                .sorted { $0.name < $1.name }
            return FolderTree(name: url.lastPathComponent, content: .folder(children))
        }
        return try read(url, levels: 2)
    }

    /// With `download`, asks iCloud for each file the app reads as it opens the folder that isn't here yet.
    public static func availability(of url: URL, download: Bool = false) -> FolderAvailability {
        let manager = FileManager.default
        var isFolder: ObjCBool = false
        guard manager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isFolder), isFolder.boolValue else {
            return .missing
        }
        let flags = launchFiles(in: url).map { file in
            let here = isDownloaded(file)
            if !here, download { try? manager.startDownloadingUbiquitousItem(at: file) }
            return here
        }
        return FolderAvailability(exists: true, downloaded: flags)
    }

    /// The files `Workspace.reload` reads, where they exist here or as an iCloud placeholder.
    static func launchFiles(in root: URL) -> [URL] {
        let metadata = StandardLayout.metadataFolder
        var files = [StandardLayout.transcriptFile, StandardLayout.settingsFile, StandardLayout.catalogFile]
            .map { root.appending(path: metadata).appending(path: $0) }
        func folders(in url: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        }
        let semesters = folders(in: root).filter { SemesterFolder(name: $0.lastPathComponent) != nil }
        let credited = folders(in: root.appending(path: StandardLayout.creditedFolder))
        for parent in semesters + credited {
            for course in folders(in: parent) where StandardLayout.isCourseFolderName(course.lastPathComponent) {
                files.append(course.appending(path: metadata).appending(path: StandardLayout.courseFile))
            }
        }
        return files.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) || placeholder(of: $0) != nil }
    }

    /// A file iCloud hasn't downloaded may be listed as `.<name>.icloud` beside where it will be.
    static func placeholder(of file: URL) -> URL? {
        let stub = file.deletingLastPathComponent().appending(path: ".\(file.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: stub.path(percentEncoded: false)) ? stub : nil
    }

    static func isDownloaded(_ file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return false }
        // Outside iCloud there is no status: the file is simply here.
        guard let status = (try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        else { return true }
        return status == .current || status == .downloaded
    }
}
