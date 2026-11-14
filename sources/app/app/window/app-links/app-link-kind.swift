import FolioDomain
import Foundation

extension AppLink.Kind {
    // 최상위 장소의 이름과 아이콘이다. 사이드바, 폰 탭, 위치 표시, 창 제목이 모두 이 값을 읽는다. 항목 종류에는 없다.
    var place: (title: String, symbol: String)? {
        switch self {
        case .today: (String(localized: .rootNavToday), "house")
        case .proposals: (String(localized: .rootNavProposals), "tray")
        case .grades: (String(localized: .rootNavGrades), "chart.line.uptrend.xyaxis")
        case .requirements: (String(localized: .rootNavRequirements), "flag")
        case .people: (String(localized: .rootNavPeople), "person")
        case .codes: (String(localized: .rootNavCodes), "number")
        case .settings: (String(localized: .rootNavSettings), "gearshape")
        case .whatsNew: (String(localized: .whatsNewTitle), "sparkles")
        case .semester, .course, .session, .unit, .note, .material, .assignment, .exam, .card, .problemSet, .person, .recording: nil
        }
    }

    // 과목 안 종류를 열면 과목 화면이 고르는 페이지다. 과목 자신은 링크의 페이지를 따른다.
    var coursePage: AppLink.CoursePage? {
        switch self {
        case .note: .notes
        case .session, .recording: .sessions
        case .unit: .units
        case .material: .materials
        case .assignment: .assignments
        case .exam: .exams
        case .card: .cards
        case .problemSet: .problems
        case .course, .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .proposals, .semester, .person: nil
        }
    }

    // 제 화면 없이 목록 페이지의 그 행으로 스크롤해 표시하는 종류다(`\.linkFocus`).
    var focusesRow: Bool {
        switch self {
        case .session, .assignment, .exam, .card, .problemSet: true
        case .note, .material, .unit, .recording, .course, .today, .grades, .requirements, .people, .codes, .settings, .whatsNew,
            .proposals, .semester, .person:
            false
        }
    }

    // 사이드바 위쪽 목록의 차례다. 제안함은 기다리는 제안이 있거나 열려 있을 때만 보인다.
    static let sidebarPlaces: [AppLink.Kind] = [.today, .proposals, .grades, .requirements, .people, .codes, .settings]
}

extension AppLink {
    // 목록과 항목이 나란한 화면이 이 링크에서 고를 항목이다. 그 종류의 항목 링크면 그 ID, 목록이 있는 자리(과목, 사람)의
    // 링크면 고른 것을 풀고(`.some(nil)`), 다른 링크면 고른 것을 그대로 둔다(`nil`).
    func selection(of item: AppLink.Kind) -> UUID?? {
        if kind == item, let id { return .some(id) }
        let list: AppLink.Kind? =
            switch item.home {
            case .course: .course
            case .catalog: .people
            case .app, .transcript, .quiz: nil
            }
        return kind == list ? .some(nil) : nil
    }
}
