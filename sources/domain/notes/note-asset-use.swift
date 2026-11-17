import Foundation

// 노트 본문이 쓰는 애셋이다. 파일은 임베드(`![[이름]]`)와 `assets/` 아래를 가리키는 마크다운 링크(`](../assets/이름)`)로,
// 위젯은 `cb-widget` 블록의 `id`로 센다. 다른 코드 블록 안의 글은 예시이므로 세지 않는다.
public struct NoteAssetUse: Equatable, Sendable {
    public private(set) var files: Set<String> = []
    public private(set) var widgets: Set<NoteWidget.ID> = []

    public init(_ body: String) {
        var fence: Fence?
        var block = ""
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let opening = Self.fence(line)
            if let open = fence {
                if let close = opening, close.closes(open) {
                    if open.widget { widgets.formUnion(Self.widgetIds(block)) }
                    fence = nil
                    block = ""
                } else if open.widget {
                    block += line + "\n"
                }
                continue
            }
            if let opening {
                fence = opening
                continue
            }
            files.formUnion(Self.fileNames(line))
        }
        if let open = fence, open.widget { widgets.formUnion(Self.widgetIds(block)) }
    }

    public func contains(_ asset: NoteAsset) -> Bool {
        switch asset.ref {
        case .file(let name): files.contains(name)
        case .widget(let id): widgets.contains(id)
        }
    }

    // FolioMarkdown의 `CBWidget.language`와 같다. Domain은 FolioMarkdown을 import하지 않는다.
    static let widgetLanguage: Substring = "cb-widget"

    private static func fence(_ line: Substring) -> Fence? {
        let indent = line.prefix { $0 == " " }
        guard indent.count <= 3 else { return nil }
        let rest = line.dropFirst(indent.count)
        guard let mark = rest.first, mark == "`" || mark == "~" else { return nil }
        let run = rest.prefix { $0 == mark }
        guard run.count >= 3 else { return nil }
        return Fence(mark: mark, count: run.count, info: rest.dropFirst(run.count).trimmingCharacters(in: .whitespaces)[...])
    }

    private static func fileNames(_ line: Substring) -> [String] {
        var names: [String] = []
        for m in line.matches(of: /\[\[([^\]|#\n]+)/) {
            let target = m.1.trimmingCharacters(in: .whitespaces)
            if let name = target.split(separator: "/").last { names.append(String(name)) }
        }
        for m in line.matches(of: /\]\(\s*(?:<([^>\n]*)>|([^)\s]+))/) {
            let raw = String(m.1 ?? m.2 ?? "")
            let path = (raw.removingPercentEncoding ?? raw).split(separator: "/").map(String.init)
            guard path.count >= 2, path[path.count - 2] == StandardLayout.noteAssetsFolder else { continue }
            names.append(path[path.count - 1])
        }
        return names
    }

    private static func widgetIds(_ block: String) -> [NoteWidget.ID] {
        block.matches(of: /"id"\s*:\s*"([0-9A-Fa-f-]{36})"/).compactMap { UUID(uuidString: String($0.1)) }
    }
}

private struct Fence {
    let mark: Character
    let count: Int
    let info: Substring

    var widget: Bool { info.split(separator: " ").first == NoteAssetUse.widgetLanguage }

    // CommonMark처럼 같은 문자로, 연 것보다 짧지 않게, 정보 문자열 없이 닫는다.
    func closes(_ open: Fence) -> Bool { mark == open.mark && count >= open.count && info.isEmpty }
}
