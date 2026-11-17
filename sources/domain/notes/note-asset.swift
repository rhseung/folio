import Foundation

// 노트 편집기의 애셋 서랍이 보이는 항목이다. 파일은 `Notes/assets` 안의 이름으로, 위젯은 ID로 가리킨다. 위젯의 이름은
// HTML의 `<title>`이고, 없으면 빈 문자열이다.
public struct NoteAsset: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable, CaseIterable {
        case figure
        case widget
        case image
        case file
    }

    public enum Filter: Hashable, Sendable, CaseIterable {
        case all
        case figures
        case widgets
        case files

        public func admits(_ kind: Kind) -> Bool {
            switch self {
            case .all: true
            case .figures: kind == .figure
            case .widgets: kind == .widget
            case .files: kind == .image || kind == .file
            }
        }
    }

    public enum Ref: Hashable, Sendable {
        case file(String)
        case widget(NoteWidget.ID)
    }

    public var ref: Ref
    public var kind: Kind
    public var name: String
    public var modified: Date?

    public var id: Ref { ref }

    public static func file(_ name: String, modified: Date? = nil) -> NoteAsset {
        NoteAsset(ref: .file(name), kind: kind(ofFile: name), name: name, modified: modified)
    }

    public static func widget(_ id: NoteWidget.ID, title: String?, modified: Date? = nil) -> NoteAsset {
        NoteAsset(ref: .widget(id), kind: .widget, name: title ?? "", modified: modified)
    }

    // 그림은 `NoteFigure`가 쓰는 SVG다. 미리보기가 `<img>`로 보이는 다른 형식은 사진처럼 꽉 채워 보인다.
    public static func kind(ofFile name: String) -> Kind {
        let ext = (name as NSString).pathExtension.lowercased()
        if ext == "svg" { return .figure }
        return MaterialFormat(path: name) == .image ? .image : .file
    }
}
