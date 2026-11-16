import Foundation

// 링크가 가리키는 항목을 부르는 이름이다. 창 제목, 툴바 탭, 칸의 위치 표시, 노트에 넣는 링크의 이름이 함께 쓴다.
// 녹음과 과목 페이지의 이름은 앱의 문구라서 무엇을 부를지만 정하고 문구는 앱이 만든다.
public enum LinkName: Equatable, Sendable {
    case item(String)
    // 녹음은 그 회차 날짜의 다시 듣기다. 회차가 없는 녹음은 날짜 없이 부른다.
    case replay(day: String?)
    case page(AppLink.CoursePage)

    // 항목 자신의 이름이다. 과목 페이지는 항목이 아니라 과목 안의 자리라서, 탭은 과목 이름을 보인다.
    public var namesItem: Bool {
        switch self {
        case .item, .replay: true
        case .page: false
        }
    }

    // 장소와 학기는 항목 이름이 없다. 과목 안 종류는 그 과목 문서에서, 사람은 목록에서 찾는다. 찾지 못하면 nil이다.
    public init?(_ link: AppLink, in file: CourseFile?, people: [Person], calendar: Calendar) {
        let id = link.id
        let name: LinkName? =
            switch link.kind {
            case .today, .grades, .requirements, .people, .codes, .settings, .whatsNew, .lms, .semester: nil
            case .person: people.first { $0.id == id }.map { .item($0.name) }
            case .course: file == nil ? nil : link.page.map(LinkName.page)
            case .session: file.flatMap { f in f.sessions.first { $0.id == id }.map { .item(f.title(of: $0, calendar: calendar)) } }
            case .unit: file?.units.first { $0.id == id }.map { .item($0.title) }
            case .note: file?.notes.first { $0.id == id }.map { .item((Self.fileName($0.path) as NSString).deletingPathExtension) }
            case .material: file?.materials.first { $0.id == id }.map { .item(Self.fileName($0.path)) }
            case .assignment: file?.assignments.first { $0.id == id }.map { .item($0.title) }
            case .exam: file?.exams.first { $0.id == id }.map { .item($0.title) }
            case .problemSet: file?.problemSets.first { $0.id == id }.map { .item($0.title) }
            case .recording: file.flatMap { f in f.recordings.first { $0.id == id }.map { .replay(of: $0, in: f, calendar: calendar) } }
            case .card: file == nil ? nil : .page(.cards)
            }
        guard let name else { return nil }
        self = name
    }

    public static func replay(of recording: Recording, in file: CourseFile, calendar: Calendar) -> LinkName {
        .replay(day: recording.sessionId.flatMap { id in file.sessions.first { $0.id == id } }.map { file.day(of: $0, calendar: calendar) })
    }

    private static func fileName(_ path: String) -> String { (path as NSString).lastPathComponent }
}
