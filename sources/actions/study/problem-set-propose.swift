import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem-set propose", "PDF에서 뽑은 문제를 문제 묶음 제안으로 두기. 앱의 문제 페이지에서 검토하고 받는다",
    discussion: """
        파일은 Problem 배열이다. 단원을 적지 않은 문제는 렉처 쪽(lecturePages)이 든 단원에 잇고, 렉처 쪽도 없으면 문제지 자료에 이어진 \
        단원이 하나일 때 그 단원에 잇는다. 받기 전에는 course.json을 바꾸지 않는다. 같은 자료의 제안이 있으면 바꾼다.
        """,
    effect: .creates, done: "{material}에서 뽑은 문제를 제안했습니다",
    examples: [#"folio problem-set propose "EC4207/2024 Midterm.pdf" --file problems.json"#],
    phrases: ["문제 뽑기", "PDF에서 문제 뽑기", "족보 문제 뽑기", "문제 제안"])
public struct ProblemSetPropose {
    @Arg var course: Course.ID
    /// 문제지 자료
    @Arg var material: Material.ID
    /// 풀이 자료. 빼면 같은 폴더에서 해설 표시만 다른 이름의 파일
    var solution: Material.ID?
    /// 묶음 제목. 빼면 파일 이름
    var title: String?
    /// 출처: past_exam, textbook, exercise, assignment. 빼면 자료의 폴더로 정한다
    var source: ProblemSource?
    /// 문제 JSON 파일(Problem 배열). -이면 표준 입력
    @CLIName("file") @FromFile var problems: [Problem]

    public func run(_ ctx: ActionContext) throws {
        let file = try ctx.file(course)
        let sheet = file.materials[try index(material, in: file.materials, .valueMaterial)]
        if let solution { _ = try index(solution, in: file.materials, .valueMaterial) }
        guard !problems.isEmpty else { throw ActionError.rule(String(localized: .errorProblemDraftEmpty)) }
        let answers = solution ?? ProblemExtraction.solution(for: sheet, in: file.materials)?.id
        let linked = ProblemExtraction.linked(problems, units: file.units, sheet: sheet)
        let add = ProblemSetAdd(
            id: UUID(), course: course, title: title ?? ProblemExtraction.title(of: sheet),
            source: source ?? ProblemExtraction.source(of: sheet),
            material: sheet.id, solution: answers, problems: linked)
        let old = try ctx.problemDraft(course, material: sheet.id)
        // 초안은 자료마다 하나라서 새 초안은 자료의 ID를 쓴다. 그래야 두 기기가 같은 자료를 뽑아도 초안 파일이 하나다.
        let draft = StudyDraft(
            id: old?.id ?? sheet.id, device: ctx.device, at: ctx.now, kind: .problems, title: ProblemExtraction.title(of: sheet),
            materialId: sheet.id, unitIds: Array(Set(linked.flatMap(\.unitIds))).sorted { $0.uuidString < $1.uuidString },
            proposal: ActionProposal(id: UUID(), command: ProblemSetAdd.command, input: try JSONValue(add)))
        try ctx.saveDraft(course, draft, replacing: old)
        ctx.made(draft.id)
    }
}
