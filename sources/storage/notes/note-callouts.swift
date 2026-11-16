import FolioDomain
import FolioMarkdown

extension CalloutTable {
    // 모르는 `tone`은 `neutral`로 읽는다.
    public init(_ settings: Settings) {
        self.init(
            adding: (settings.callouts ?? []).map {
                CalloutKind($0.name, CalloutKind.Tone(rawValue: $0.tone) ?? .neutral, numbered: $0.numbered, provable: $0.provable)
            })
    }
}

extension NoteWritingGuide {
    // 설정이 없으면(GIST 폴더 없이 읽을 때, 저장소의 스킬 사본) 기본 종류만 적는다.
    public static func text(for settings: Settings?) -> String {
        let table = settings.map(CalloutTable.init) ?? .standard
        return text(callouts: table.names, numbered: table.kinds.filter(\.numbered).map(\.name))
    }
}
