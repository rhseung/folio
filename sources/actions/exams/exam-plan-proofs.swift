import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

// 정리류 블록이 있는 정리 노트를 파일에서 읽는다. 계획은 이 노트에만 증명 단계를 둔다. 앱이 다시 놓을지 볼 때와 액션이 놓을 때
// 같은 판단을 쓰도록 한 곳에 둔다.
public enum ExamPlanProofs {
    // `.tex` 노트에는 콜아웃이 없어 증명 단계를 두지 않는다. 읽지 못한 노트도 증명이 없는 것으로 본다.
    public static func read(_ notes: [NoteEntry], store: CourseStore, settings: Settings) -> Set<UUID> {
        let callouts = CalloutTable(settings)
        return Set(
            notes.filter { NoteFormat(path: $0.path) == .markdown }.compactMap { note in
                let file = NoteFile(url: store.fileURL(note.path), meta: NoteMeta(id: note.id))
                guard let text = try? store.read(file) else { return nil }
                return CalloutScan.hasProvable(text, callouts: callouts) ? note.id : nil
            })
    }
}
