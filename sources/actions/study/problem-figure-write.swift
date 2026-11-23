import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem figure", "문제집 PDF에 넣을 문제 그림과 답을 그린 풀이용 그림(SVG)을 쓰기. 쓰면 문제지에서 자른 그림 대신 들어간다",
    discussion: "그림은 노트 그림과 같은 규칙으로 마무리하고 검사한다(folio note format). 둘 다 빼면 그릴 것이 없다고 적어 문제집을 만들 때 다시 그리지 않는다.",
    done: "'{number}'의 그림을 썼습니다",
    phrases: ["문제 그림 다시 그리기", "풀이 그림", "답을 그림에 그리기"], panel: true)
public struct ProblemFigureWrite {
    /// 과목
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID
    /// 문제나 지문의 번호(2a, 2)
    @Arg var number: String
    /// 문제의 그림을 다시 그린 SVG. 빼면 문제지에서 자른 그림을 쓴다
    @FromFile("figure.svg") var figure: String?
    /// 같은 그림 위에 답(매칭, 경로, 색칠)을 그린 SVG. 풀이집의 풀이 앞에 들어간다
    @CLIName("solution") @FromFile("solution.svg") var solutionFigure: String?

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try ctx.file(course)
        let s = file.problemSets[try index(set, in: file.problemSets, .valueProblemSet)]
        let wanted = number.trimmingCharacters(in: .whitespaces)
        guard let id = s.problems.first(where: { $0.number == wanted })?.id ?? s.groups.first(where: { $0.number == wanted })?.id
        else { throw ActionError.notFound(String(localized: .errorNotFoundProblem(wanted))) }
        let korean = FigureStyle.allowsKorean(file.course, catalog: try ctx.catalog())
        let finished = try figure.map { try NoteFigureAdd.finish($0, korean: korean) }
        let solution = try solutionFigure.map { try NoteFigureAdd.finish($0, korean: korean) }

        let path = ProblemArt.path(id)
        let old = store.problemArt()[id]
        var doc = old ?? StoredDocument(new: ProblemArt(id: id, device: ctx.device, at: ctx.now))
        doc.model.figure = finished
        doc.model.solutionFigure = solution
        doc.model.updatedAt = ctx.now
        doc.model.updatedBy = ctx.device
        try ctx.io(Change(old == nil ? .added : .changed, try ctx.relative(course, path))) { try store.save(doc) }
    }
}
