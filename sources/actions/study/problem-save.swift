import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Action(
    "problem save", "JSON 파일의 문제를 묶음에 넣거나 같은 ID의 문제를 바꾸기",
    discussion: "파일은 course.json의 problems와 같은 필드 이름을 쓰는 Problem 배열이다. id가 없는 문제는 새로 넣는다.",
    done: "문제 묶음 '{set}'에 문제 {problems}을(를) 저장했습니다", examples: [#"folio problem save "EC4207/Exercise 1" --file problems.json"#],
    phrases: ["문제 수정", "정답 넣기", "문제 단원 바꾸기"], panel: true)
public struct ProblemSave {
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID
    /// 문제 JSON 파일. -이면 표준 입력
    @CLIName("file") @FromFile var problems: [Problem]

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.problemSets, set) { s in
                for p in problems {
                    if let i = s.problems.firstIndex(where: { $0.id == p.id }) { s.problems[i] = p } else { s.problems.append(p) }
                }
                s.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
