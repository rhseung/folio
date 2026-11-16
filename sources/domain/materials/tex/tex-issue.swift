import Foundation

public struct TexIssue: Equatable, Sendable, Codable {
    public enum Severity: String, Equatable, Sendable, Codable { case error, warning }

    public var severity: Severity
    public var file: String?
    public var line: Int?
    public var message: String

    public init(_ severity: Severity, file: String? = nil, line: Int? = nil, message: String) {
        self.severity = severity
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String {
        guard let file else { return message }
        return line.map { "\(file):\($0): \(message)" } ?? "\(file): \(message)"
    }
}
