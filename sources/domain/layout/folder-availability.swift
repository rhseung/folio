// 앱이 열 때 읽는 파일(transcript, settings, catalog, 모든 course.json)이 이 기기에 있어야 한다. 아직 내려받지
// 않은 iCloud 폴더의 파일은 자리표시자라서, 읽으면 실제 학기 대신 빈 학기를 보인다.
public enum FolderAvailability: Hashable, Sendable {
    case ready
    case missing
    case downloading(done: Int, total: Int)

    public init(exists: Bool, downloaded: [Bool]) {
        guard exists else { self = .missing; return }
        let done = downloaded.count { $0 }
        self = done == downloaded.count ? .ready : .downloading(done: done, total: downloaded.count)
    }

    public var fraction: Double {
        switch self {
        case .ready: 1
        case .missing: 0
        case .downloading(let done, let total): total == 0 ? 1 : Double(done) / Double(total)
        }
    }
}
