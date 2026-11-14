import Foundation

public enum NoteFormat: String, Codable, Sendable, CaseIterable {
    case markdown, tex

    public var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .tex: "tex"
        }
    }

    public init?(path: String) {
        guard let format = Self.allCases.first(where: { $0.fileExtension == (path as NSString).pathExtension.lowercased() }) else {
            return nil
        }
        self = format
    }
}
