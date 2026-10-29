import Foundation

/// Tells the workspace when data files in the GIST folder change outside the app: the `folio` CLI, or another
/// device through iCloud. Both write through NSFileCoordinator, which is what reaches a file presenter.
final class GISTWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let changed: @Sendable () -> Void

    init(url: URL, changed: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.changed = changed
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    func stop() { NSFileCoordinator.removeFilePresenter(self) }

    func presentedSubitemDidChange(at url: URL) {
        // Notes have the editor's own conflict check; the JSON files and logs feed every screen.
        guard ["json", "jsonl"].contains(url.pathExtension) else { return }
        changed()
    }
}
