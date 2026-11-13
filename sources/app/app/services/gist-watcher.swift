import Foundation

// `folio` CLI와 iCloud를 거친 다른 기기는 모두 `NSFileCoordinator`로 쓰고, file presenter에는 그렇게 쓴 변경만
// 전달된다.
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
        guard ["json", "jsonl"].contains(url.pathExtension) else { return }
        changed()
    }
}
