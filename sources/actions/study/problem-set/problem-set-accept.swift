import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem-set accept", "자료에서 뽑은 문제 제안을 문제 묶음으로 받기",
    discussion: "문제 파일을 주면 제안의 문제 대신 그 문제를 받는다. 다른 기기에서 이미 받은 제안이면 제안만 치운다.",
    done: "{material}에서 뽑은 문제를 받았습니다",
    examples: [
        #"folio problem-set accept "EC4207/2024 Midterm.pdf""#,
        #"folio problem-set accept "EC4207/2024 Midterm.pdf" --title "2024 중간" --file kept.json"#,
    ],
    phrases: ["문제 제안 받기", "뽑은 문제 받기"])
public struct ProblemSetAccept {
    @Arg var course: Course.ID
    /// 문제지 자료
    @Arg var material: Material.ID
    /// 묶음 제목. 빼면 제안의 제목
    var title: String?
    /// 받을 문제 JSON 파일(Problem 배열). 빼면 제안의 문제 전부
    @CLIName("file") @FromFile var problems: [Problem]?

    public func run(_ ctx: ActionContext) throws {
        var draft = try ctx.requireProblemDraft(course, material: material)
        if let problems { draft.problems = problems }
        if let title { draft.proposal.input["title"] = .string(title) }
        guard !draft.problems.isEmpty else { throw ActionError.rule(String(localized: .errorProblemDraftEmpty)) }
        guard let add = Actions.action(draft.proposal) else {
            throw ActionError.rule(String(localized: .errorProblemDraftUnreadable(draft.title)))
        }
        // 제안의 ID를 남겨 두 기기가 같은 초안을 받아도 묶음이 하나만 생긴다.
        let outer = ctx.proposal
        ctx.proposal = draft.proposal
        defer { ctx.proposal = outer }
        do {
            try ctx.refuseAppliedProposal()
            try add.run(ctx)
        } catch let e as ActionError where e == .applied {}
        try ctx.discardDraft(course, draft.id)
    }
}
