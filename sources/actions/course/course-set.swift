import FolioDomain
import FolioStorage
import Foundation

@Action(
    "course set", "과목의 학점, 평가 방식, 색, 아이콘, 성적, 교수, 분류, 학과 인정 바꾸기. 준 것만 바꾼다", done: "과목 '{course}'을(를) 바꿨습니다",
    phrases: ["교수님", "교수 이름", "학점 수정", "학점 바꾸기", "받은 성적", "학점 변경", "과목 색", "교수 지정", "성적 입력", "평가 방식"],
    cli: .manual(reason: "입력이 바꿀 항목(Field)의 목록이라, 옵션마다 항목 하나를 만들고 색 프리셋과 none을 검사한다"))
public struct CourseSet {
    public enum Field: Codable, Sendable, Equatable {
        case memo(String), credits(Double), gradingMode(GradingMode), instructors([UUID]), categories([UUID]), color(String), icon(String?),
            schedule([ClassTime]), reviews(Bool), finalGrade(UUID?), sharingApproved(Bool)
        // `folio actions --schema`가 모든 케이스를 나열하도록 CaseIterable을 붙인다. Codable 합성은 여전히 이 키를 쓴다.
        enum CodingKeys: CodingKey, CaseIterable {
            case memo, credits, gradingMode, instructors, categories, color, icon, schedule, reviews, finalGrade, sharingApproved
        }
    }
    @Arg var course: Course.ID
    var fields: [Field]

    func apply(to c: inout Course) {
        for field in fields {
            switch field {
            case .memo(let v): c.memo = v
            case .credits(let v): c.credits = v
            case .gradingMode(let v): c.gradingMode = v
            case .instructors(let v): c.instructorIds = v
            case .categories(let v): c.categoryIds = v
            case .color(let v): c.color = v
            // course.json에 `""`를 두지 않고 키를 빼도록 빈 이름도 지운다.
            case .icon(let v): c.icon = v?.isEmpty == false ? v : nil
            case .schedule(let v):
                c.schedule = v.map {
                    var t = $0; t.link = OnlineLink.stored(t.link); return t
                }
            case .reviews(let v): if v != (c.reviews != false) { c.reviews = v ? nil : false }
            case .finalGrade(let v): c.finalGrade = v
            case .sharingApproved(let v): c.sharingApproved = v ? true : nil
            }
        }
    }

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { apply(to: &$0.course) }
    }
}

extension CourseSet {
    public init(course: Course.ID, _ fields: [Field]) { self.init(course: course, fields: fields) }
}
