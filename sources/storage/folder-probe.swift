import FolioDomain
import Foundation

public enum FolderProbe {
    // `FolderTree(contentsOf:)`는 트리 전체를 읽는데, 큰 iCloud 폴더에서는 첫 화면에 몇 초가 걸렸고 지나가는
    // 자리표시자마다 iCloud에 내려받기를 요청했다.
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
        let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
            .map { try read($0, levels: $0.lastPathComponent == StandardLayout.creditedFolder ? 2 : 1) }
            .sorted { $0.name < $1.name }
        return FolderTree(name: url.lastPathComponent, content: .folder(children))
    }

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

    // iCloud가 내려받지 않은 파일은 제자리 옆에 `.<name>.icloud`로 보일 수 있다.
    static func placeholder(of file: URL) -> URL? {
        let stub = file.deletingLastPathComponent().appending(path: ".\(file.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: stub.path(percentEncoded: false)) ? stub : nil
    }

    static func isDownloaded(_ file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return false }
        guard let status = (try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus
        else { return true }
        return status == .current || status == .downloaded
    }
}
