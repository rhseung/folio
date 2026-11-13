// `type`은 파일에 저장되는 구분 값이므로 절대 바꾸지 않는다.
public protocol LogEvent: Codable, Sendable {
    static var type: String { get }
}
