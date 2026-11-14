import FolioDomain
import FolioStorage
import Foundation

public struct Change: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case added, changed, removed, moved }
    public var kind: Kind
    public var path: String
    public var item: String?
    public var to: String?
    public var fields: [Field]?

    public struct Field: Codable, Sendable, Equatable {
        public var name: String
        public var before: JSONValue?
        public var after: JSONValue?

        public init(name: String, before: JSONValue?, after: JSONValue?) {
            (self.name, self.before, self.after) = (name, before, after)
        }
    }

    public init(_ kind: Kind, _ path: String, item: String? = nil, to: String? = nil, fields: [Field]? = nil) {
        self.kind = kind
        self.path = path
        self.item = item
        self.to = to
        self.fields = fields
    }
}

extension Change {
    // 열린 노트는 다시 그릴 때에야 다시 쓴 위젯을 보이므로, 노트가 쓰는 위젯도 노트를 건드린 것으로 본다.
    public var touchesNotes: Bool {
        func inNotes(_ path: String?) -> Bool { path?.split(separator: "/").contains { $0 == CourseFolder.notes.rawValue } == true }
        let courseFile = path.split(separator: "/").last == Substring(StandardLayout.courseFile)
        let parts = path.split(separator: "/").map(String.init)
        let widget = zip(parts, parts.dropFirst()).contains { $0 == (StandardLayout.metadataFolder, StandardLayout.widgetsFolder) }
        return inNotes(path) || inNotes(to) || widget || courseFile && item?.hasPrefix(Self.notesItem) == true
    }

    public var touchesQuizzes: Bool {
        let parts = path.split(separator: "/").map(String.init)
        return zip(parts, parts.dropFirst()).contains { $0 == (StandardLayout.metadataFolder, StandardLayout.quizzesFolder) }
            || item == QuizAttemptEvent.type
    }

    // `diff`는 항목을 그것이 든 배열의 JSON 키로 부른다. `CourseFile.notes`는 `notes`로 인코딩된다.
    static let notesItem = "notes/"
}
