import FolioActions
import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct NoteDiagramCheckTests {
    static let course = ActionTests.graphTheory
    static let note = "Notes/09-08(화) 매칭.md"
    // 2026-11-19 노트에서 앱이 깨뜨린 도식이다. 줄마다 그려도 마름모 둘째 줄의 긴 수식이 꼭짓점 쪽 변에 닿는다.
    static let broken = #"""
        ```mermaid
        flowchart TD
          S["$f(t) = \det(A - tI)$"] --> Q1{"splits?"}
          Q1 -- "아니요" --> N1["not diagonalizable<br/>(Thm 5.6)"]
          Q1 -- "예" --> Q2{"근이 겹치는 $\lambda$마다<br/>$n - \operatorname{rank}(A - \lambda I) = m_\lambda$?"}
          Q2 -- "아니요" --> N2["not diagonalizable<br/>(Thm 5.9)"]
          Q2 -- "예" --> Y["diagonalizable<br/>각 $E_\lambda$의 기저를 모아 $Q$, $Q^{-1}AQ = D$"]
        ```
        """#
    static let fine = """
        ```mermaid
        flowchart TD
          A[시작] --> B{조건?}
          B -- 예 --> C[끝]
          B -- 아니요 --> D[다시]
          D --> A
        ```
        """
    let device = UUID()
    let gist: GISTStore
    let store: CourseStore

    init() throws {
        gist = GISTStore(url: try Fixture.standard.copyToTemp())
        store = try ActionContext(gist: gist, device: device).store(Self.course)
    }

    func run(_ action: some Action) throws {
        try action.run(ActionContext(gist: gist, device: device, now: Date(timeIntervalSince1970: 1_790_000_000)))
    }

    func text() throws -> String { try store.readText(Self.note) }

    func refusal(_ action: some Action) -> String? {
        do { try run(action) } catch let error as ActionError { return error.description } catch { return "\(error)" }
        return nil
    }

    @Test func aDiagramWhoseLabelsSpillOutOfTheirShapesIsNotWritten() throws {
        let before = try text()
        let body = "# 대각화\n\n" + Self.broken + "\n"
        let message = try #require(refusal(NoteWrite(course: Self.course, note: Self.note, text: body, expected: nil, typed: false)))
        #expect(message.contains("mermaid 도식 1(3번째 줄)"))
        #expect(message.contains(#"n - \operatorname{rank}("#))
        #expect(message.contains("polygon"))
        #expect(message.contains("note figure add"))
        #expect(try text() == before)
    }

    @Test func aDiagramWithShortPlainLabelsIsWritten() throws {
        let body = "# 흐름\n\n" + Self.fine + "\n"
        try run(NoteWrite(course: Self.course, note: Self.note, text: body, expected: nil, typed: false))
        #expect(try text() == body)
    }

    // `<br/>`로 나눈 수식 라벨은 줄마다 놓인다. 줄을 이어 한 줄로 두던 때는 이 상자를 넘었다.
    @Test func aMultiLineLabelWithMathStaysInItsBox() throws {
        let body = #"""
            ```mermaid
            flowchart TD
              A["diagonalizable<br/>각 $E_\lambda$의 기저를 모아 $Q$"] --> B[끝]
            ```

            """#
        try run(NoteWrite(course: Self.course, note: Self.note, text: body, expected: nil, typed: false))
        #expect(try text() == body)
    }

    @Test func editAndAddCheckTheDiagramsTheyBring() throws {
        #expect(refusal(NoteEdit(course: Self.course, note: Self.note, replacements: [], append: Self.broken)) != nil)
        #expect(refusal(NoteAdd(course: Self.course, title: "대각화", body: Self.broken)) != nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL("Notes/대각화.md").path))
        try run(NoteAdd(course: Self.course, title: "흐름", body: Self.fine))
    }

    // 이미 있던 도식이 깨져 있어도 다른 곳을 고치는 쓰기는 막지 않는다. 편집 보기의 저장은 검사하지 않는다.
    @Test func onlyNewDiagramsAreCheckedAndTheEditorIsNot() throws {
        let body = "# 대각화\n\n" + Self.broken + "\n"
        try run(NoteWrite(course: Self.course, note: Self.note, text: body, expected: nil, typed: true))
        #expect(try text() == body)
        try run(NoteEdit(course: Self.course, note: Self.note, replacements: [.init(old: "# 대각화", new: "# 대각화 판정")], append: nil))
        #expect(try text().hasPrefix("# 대각화 판정\n"))
    }
}
