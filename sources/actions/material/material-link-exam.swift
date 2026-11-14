import FolioDomain
import FolioStorage
import Foundation

@Action(
    "material link-exam", "자료를 시험에 연결하거나 떼기. 시험 폴더 밖의 자료(Study, Inherited)를 그 시험에 모은다",
    done: "자료 '{material}'과(와) 시험 '{exam}'의 연결을 바꿨습니다",
    examples: ["folio material link-exam EC4207/Study/Problems.pdf 중간고사", "folio material link-exam EC4207/Study/Problems.pdf 중간고사 --off"],
    phrases: ["자료 시험 연결", "시험 대비 자료 연결", "족보 시험에 붙이기"])
public struct MaterialLinkExam {
    /// 과목
    @Arg var course: Course.ID
    /// 자료
    @Arg var material: Material.ID
    /// 같은 과목의 시험
    @Arg var exam: Exam.ID
    /// 연결 떼기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(material, in: f.materials, .valueMaterial)
            _ = try index(exam, in: f.exams, .valueExam)
            f.setMaterial(material, exam: exam, linked: linked)
        }
    }
}
