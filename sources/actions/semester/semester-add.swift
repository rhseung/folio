import FolioDomain
import FolioStorage
import Foundation

@Action(
    "semester add", "학기 추가. 학기 폴더를 만든다. 인정학기는 출처 이름으로 _Credited/<출처> 폴더를 만든다", effect: .creates, done: "학기 '{year} {term}'을(를) 추가했습니다",
    examples: [
        "folio semester add 2027 spring --start 2027-03-02 --end 2027-06-18",
        #"folio semester add 2024 credited --source "군 복무" --credited-hours 9 --dry-run  인정학기"#,
    ],
    phrases: ["학기 추가", "새 학기", "학기 만들기", "인정학기 추가"])
public struct SemesterAdd {
    @New var id: Semester.ID
    /// 연도
    @Arg var year: Int
    /// 학기
    @Arg var term: Term
    /// 개강일. 2027-03-02
    var start: LocalDate?
    /// 종강일
    var end: LocalDate?
    /// 인정학기의 인정 학점
    var creditedHours: Double?
    /// 인정학기의 출처. 영재고 AP. 폴더 이름이 된다
    var source: String?

    public func run(_ ctx: ActionContext) throws {
        var semester = Semester(id: id, device: ctx.device, at: ctx.now, year: year, term: term, start: start, end: end)
        semester.creditedHours = creditedHours
        semester.source = source
        guard term != .credited || source != nil else {
            throw ActionError.rule(String(localized: .errorCreditedNeedsSource(semester.name)))
        }
        try ctx.editTranscript { t in
            guard term == .credited || !t.semesters.contains(where: { $0.year == year && $0.term == term }) else {
                throw ActionError.rule(String(localized: .errorSemesterExists(semester.folder?.name ?? "\(year)")))
            }
            guard !t.semesters.contains(where: { $0.id == id }) else {
                throw ActionError.rule(String(localized: .errorIdTakenSemester("\(id)")))
            }
            t.semesters.append(semester)
        }
        if let folder = semester.coursesFolder {
            try ctx.io(Change(.added, folder + "/")) {
                try FileManager.default.createDirectory(at: ctx.gist.url.appending(path: folder), withIntermediateDirectories: true)
            }
        }
        ctx.made(id)
    }
}
