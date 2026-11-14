import FolioStorage
import Foundation

final class Sink: @unchecked Sendable {
    var out: (String) -> Void
    var err: (String) -> Void
    init(out: @escaping (String) -> Void, err: @escaping (String) -> Void) {
        self.out = out
        self.err = err
    }

    @TaskLocal static var current = Sink(out: { print($0) }, err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
}
