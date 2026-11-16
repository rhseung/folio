import FolioCore
import Foundation

public struct DiagnosticEvent: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case crash
        case hang
        case cpu
        case diskWrite
        case memory
    }

    public var kind: Kind
    public var date: Date
    public var appVersion: String?
    // MetricKit이 준 값 그대로다(신호 이름, "3.2 sec" 같은 길이). 번역하지 않는다.
    public var detail: String?
    public var count: Int

    public init(kind: Kind, date: Date, appVersion: String? = nil, detail: String? = nil, count: Int = 1) {
        self.kind = kind
        self.date = date
        self.appVersion = appVersion
        self.detail = detail
        self.count = count
    }
}
