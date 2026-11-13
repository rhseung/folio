import FolioDomain
import FolioStorage
import Foundation

enum FolderTrouble: Equatable {
    /// Gone, moved, or on a drive that isn't connected. `path` is where it last was.
    case missing(path: String)
    /// In iCloud but not on this device yet: the app opens it on its own once its files are here.
    case downloading(path: String, done: Int, total: Int)

    var path: String {
        switch self {
        case .missing(let path), .downloading(let path, _, _): path
        }
    }
}

extension Workspace {
    /// Opens the remembered folder only once it can be read.
    func openRemembered() {
        let shown = UserDefaults.standard.string(forKey: Self.pathKey) ?? ""
        var stale = false
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey),
              let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else {
            folderTrouble = .missing(path: shown)
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        openWhenHere(url, remember: stale)
    }

    /// Opens `url` now if the files it opens with are on this device, or once iCloud has brought them; false while it
    /// waits or the folder is gone (`folderTrouble` says which). Opening one still in iCloud would read empty files in
    /// place of the real ones, which the next save would write over.
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

    /// Gives up on a folder `openWhenHere` is waiting for.
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

    func finishFirstRun() {
        showsFirstRun = false
    }
}
