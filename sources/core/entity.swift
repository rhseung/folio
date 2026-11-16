import Foundation

public typealias DeviceID = UUID

public protocol Entity: Identifiable, Codable, Sendable, Equatable where ID == UUID {
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var updatedBy: DeviceID { get set }
}

extension Entity {
    public mutating func touch(by device: DeviceID, at date: Date) {
        updatedAt = date
        updatedBy = device
    }
}

extension Dictionary {
    // ID는 사람이 복사하고 고치는 파일에서 오므로 키가 겹칠 수 있다. `uniqueKeysWithValues`는 겹친 키에서 앱을
    // 비정상 종료시키므로, 여기서는 첫 값을 쓴다.
    public init<S: Sequence>(keepingFirst pairs: S) where S.Element == (Key, Value) {
        self.init(pairs, uniquingKeysWith: { first, _ in first })
    }
}
