import Foundation

// 서랍의 두 묶음이다. 이 노트에 아직 넣지 않은 것을 앞에 둔다. 서랍을 여는 일은 대개 새로 만든 그림을 넣으려는 것이라
// 두 묶음 모두 새것부터 놓는다. 거르고 찾아도 묶음은 그대로 두고 맞는 항목만 남긴다.
public struct NoteAssetShelf: Equatable, Sendable {
    public private(set) var unused: [NoteAsset]
    public private(set) var used: [NoteAsset]

    public init(_ assets: [NoteAsset], use: NoteAssetUse, filter: NoteAsset.Filter = .all, search: String = "") {
        let words = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = assets.filter { filter.admits($0.kind) && (words.isEmpty || $0.name.localizedStandardContains(words)) }
            .sorted(by: Self.newerFirst)
        unused = shown.filter { !use.contains($0) }
        used = shown.filter { use.contains($0) }
    }

    public var isEmpty: Bool { unused.isEmpty && used.isEmpty }

    static func newerFirst(_ a: NoteAsset, _ b: NoteAsset) -> Bool {
        switch (a.modified, b.modified) {
        case let (x?, y?) where x != y: return x > y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
