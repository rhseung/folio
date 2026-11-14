import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

@Action(
    "problem-set add", "문제 번호로 문제 묶음 만들기", effect: .creates, done: "문제 묶음을 저장했습니다",
    phrases: ["문제 묶음 만들기", "연습문제 등록"], cli: .manual(reason: "제목과 문제 번호로 문제 묶음(ProblemSet) 전체를 만든다"))
public struct ProblemSetSave {
    @Arg var course: Course.ID
    var set: ProblemSet

    public func run(_ ctx: ActionContext) throws {
        var set = set
        set.touch(by: ctx.device, at: ctx.now)
        try ctx.edit(course) { f in
            if let i = f.problemSets.firstIndex(where: { $0.id == set.id }) { f.problemSets[i] = set } else { f.problemSets.append(set) }
        }
        ctx.made(set.id)
    }
}
