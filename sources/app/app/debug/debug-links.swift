#if os(macOS) && (DEBUG || RESIZE_PROBE)
import FolioDomain
import Foundation

// 스냅숏과 측정이 칸과 탭에 여는 링크다. 가짜 폴더의 항목 ID는 폴더를 만들 때마다 달라서, 환경 변수에는 `folio://` 주소나
// 앱 링크의 종류 이름(`material`, `session`, `note`, `course/quiz`)을 적고 그 과목의 대표 항목으로 푼다.
@MainActor enum DebugLinks {
    static func links(_ text: String, in course: LoadedCourse) -> [AppLink] {
        text.split(separator: ",").compactMap { link(String($0), in: course) }
    }

    static func link(_ text: String, in course: LoadedCourse) -> AppLink? {
        if let link = AppLink(string: text) { return link }
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard let kind = parts.first.flatMap(AppLink.Kind.init(rawValue:)) else { return nil }
        let file = course.file
        switch kind {
        case .course: return .course(course.id, page: parts.dropFirst().first.flatMap(AppLink.CoursePage.init(rawValue:)))
        case .material:
            // 렉처 칸은 회차 진도가 있는 PDF를 먼저 연다. 쪽 열의 구획이 함께 보여야 하기 때문이다.
            let pdfs = file.materials.filter { $0.isPDF }
            let paged = pdfs.first { m in file.sessions.contains { $0.materials.contains { $0.materialId == m.id && $0.pages != nil } } }
            return (paged ?? pdfs.first).map { AppLink(.material, $0.id) }
        case .session:
            let session = file.sessions.first { $0.roughNoteId != nil && !$0.materials.isEmpty } ?? file.sessions.first
            return session.map { AppLink(.session, $0.id) }
        case .note: return file.notes.first.map { AppLink(.note, $0.id) }
        case .unit: return file.units.first.map { AppLink(.unit, $0.id) }
        case .exam: return file.exams.first.map { AppLink(.exam, $0.id) }
        case .assignment: return file.assignments.first.map { AppLink(.assignment, $0.id) }
        case .recording: return file.recordings.first.map { AppLink(.recording, $0.id) }
        case .problemSet: return file.problemSets.first.map { AppLink(.problemSet, $0.id) }
        case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals: return .place(kind)
        case .semester, .card, .person: return nil
        }
    }
}
#endif
