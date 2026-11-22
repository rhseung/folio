import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem-set add", "문제 묶음 만들기. 문제는 번호만 주거나 JSON 파일(Problem 배열)로 준다", effect: .creates,
    done: "문제 묶음 '{title}'을(를) 만들었습니다",
    examples: [
        #"folio problem-set add EC4207 "2022 중간" 1 2 3 --source past_exam"#,
        #"folio problem-set add EC4207 "HW3" --source assignment --file problems.json"#,
    ],
    phrases: ["문제 묶음 만들기", "연습문제 등록", "족보 문제 넣기", "문제지 등록"], panel: true)
public struct ProblemSetAdd {
    @New var id: ProblemSet.ID
    @Arg var course: Course.ID
    /// 제목
    @Arg var title: String
    /// 출처: past_exam, textbook, exercise, assignment, claude
    var source: ProblemSource = .exercise
    /// 문제지 자료
    var material: Material.ID?
    /// 풀이 자료
    var solution: Material.ID?
    /// 문제 번호. 1 2 3a
    @Arg var numbers: [String] = []
    /// 문제 JSON 파일(Problem 배열). -이면 표준 입력
    @CLIName("file") @FromFile var problems: [Problem]?

    public func run(_ ctx: ActionContext) throws {
        let all = (problems ?? []) + numbers.map { Problem(number: $0) }
        try ctx.edit(course) { f in
            guard !f.problemSets.contains(where: { $0.id == id }) else {
                throw ActionError.rule(String(localized: .errorIdTakenProblemSet("\(id)")))
            }
            f.problemSets.append(
                ProblemSet(
                    id: id, device: ctx.device, at: ctx.now, title: title.trimmingCharacters(in: .whitespaces), source: source,
                    materialId: material, solutionMaterialId: solution, problems: all))
        }
        ctx.made(id)
    }
}
