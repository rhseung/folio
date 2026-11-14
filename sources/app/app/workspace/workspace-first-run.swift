import FolioDomain
import FolioStorage
import Foundation

enum FolderTrouble: Equatable {
    case missing(path: String)
    case downloading(path: String, done: Int, total: Int)

    var path: String {
        switch self {
        case .missing(let path), .downloading(let path, _, _): path
        }
    }
}

extension Workspace {
    func openRemembered() {
        let shown = UserDefaults.standard.string(forKey: Self.pathKey) ?? ""
        var stale = false
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey),
            let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        else {
            folderTrouble = .missing(path: shown)
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        openWhenHere(url, remember: stale)
    }

    // 아직 iCloud에 있는 폴더를 열면 실제 파일 대신 빈 파일을 읽고, 다음 저장이 실제 파일을 덮어쓴다.
    @discardableResult
    func openWhenHere(_ url: URL, remember: Bool = true) -> Bool {
        let path = url.path(percentEncoded: false)
        switch FolderProbe.availability(of: url, download: true) {
        case .ready:
            open(url, remember: remember)
            return true
        case .missing:
            folderTrouble = .missing(path: path)
        case .downloading(let done, let total):
            folderTrouble = .downloading(path: path, done: done, total: total)
            waitForDownload(url, remember: remember)
        }
        return false
    }

    func stopWaiting() {
        folderWait?.cancel()
        folderTrouble = nil
    }

    private func waitForDownload(_ url: URL, remember: Bool) {
        folderWait?.cancel()
        folderWait = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let path = url.path(percentEncoded: false)
                switch FolderProbe.availability(of: url) {
                case .ready: open(url, remember: remember); return
                case .missing: folderTrouble = .missing(path: path); return
                case .downloading(let done, let total): folderTrouble = .downloading(path: path, done: done, total: total)
                }
            }
        }
    }

    var isInFirstRun: Bool { gist == nil || showsFirstRun }

    func finishFirstRun() {
        showsFirstRun = false
    }
}
