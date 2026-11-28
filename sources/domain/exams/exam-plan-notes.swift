import FolioCore
import Foundation

// 시험의 정리 노트다. 시험 공부의 단위는 단원이 아니라 범위 단원에 이은 낱개 노트이고, 계획은 이 노트를 이름 순서대로 놓는다.
public struct ExamPlanNotes: Codable, Sendable, Equatable, Hashable {
    public struct Note: Codable, Sendable, Equatable, Hashable {
        public var id: UUID
        // 정리류 블록이 있는 노트다. 증명 단계는 이 노트에만 둔다.
        public var proof: Bool

        public init(id: UUID, proof: Bool = false) {
            self.id = id
            self.proof = proof
        }
    }

    public var notes: [Note]
    // 어떤 정리 노트에도 이어지지 않은 범위 단원이다. 계획의 맨 앞에 "정리 노트 만들기"로 놓인다.
    public var missing: [UUID]

    public init(notes: [Note] = [], missing: [UUID] = []) {
        self.notes = notes
        self.missing = missing
    }
}

extension NoteEntry {
    // 노트의 이름은 파일 이름에서 확장자를 뺀 것이다.
    public var title: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
}

extension CourseFile {
    public func examNotes(of exam: Exam) -> [NoteEntry] { examNotes(scope: Set(scope(of: exam))) }

    // 숫자를 수로 읽어 "기말 02"가 "기말 10"보다 앞이다. 이름이 같으면 경로로 가려 차례가 흔들리지 않게 한다.
    func examNotes(scope: Set<UUID>) -> [NoteEntry] {
        notes.filter { $0.kind == .unit && !scope.isDisjoint(with: $0.unitIds) }.sorted { a, b in
            let order = a.title.localizedStandardCompare(b.title)
            return order == .orderedSame ? a.path < b.path : order == .orderedAscending
        }
    }

    // `proofs`는 정리류 블록이 있는 노트다. 노트 파일을 읽어야 알 수 있어서 액션 층이 읽어 넘긴다.
    public func planNotes(of exam: Exam, proofs: Set<UUID>) -> ExamPlanNotes {
        let scoped = scopeUnits(of: exam)
        let entries = examNotes(scope: Set(scoped.map(\.id)))
        let noted = Set(entries.flatMap(\.unitIds))
        // 부모와 자식이 함께 범위에 있으면 자식만 본다. 부모 단원을 공부하는 일은 자식 단원을 공부하는 일이다. 부모에 이은
        // 노트는 그 자식들을 함께 다루는 노트로 본다.
        let missing = UnitTree.deepest(scoped, in: units).filter { unit in
            !noted.contains(unit.id) && noted.isDisjoint(with: ancestors(of: unit.id))
        }
        return ExamPlanNotes(
            notes: entries.map { ExamPlanNotes.Note(id: $0.id, proof: proofs.contains($0.id)) }, missing: missing.map(\.id))
    }
}
