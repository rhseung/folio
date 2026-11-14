import FolioDomain
import FolioStorage
import Foundation

// 읽기 선언이 받는 맥락이다. 액션의 맥락을 감싸 쓰기를 열지 않는다.
public final class ReadContext {
    private let base: ActionContext

    public init(_ base: ActionContext) { self.base = base }

    public var now: Date { base.now }
    public var calendar: Calendar { base.calendar }
    public var today: LocalDate { LocalDate(base.now, in: base.calendar) }

    public func file(_ course: UUID) throws -> CourseFile { try base.file(course) }
    public func store(_ course: UUID) throws -> CourseStore { try base.store(course) }
    public func transcript() throws -> Transcript { try base.transcript() }
    public func catalog() throws -> Catalog { try base.catalog() }
    public func settings() throws -> Settings { try base.settings() }
    public func semesters() throws -> [Semester] { try base.transcript().semesters.sorted { $0.order < $1.order } }
    public func name(of id: UUID) -> String? { base.name(of: id) }
    public func note(_ course: UUID, path: String) throws -> NoteFile { try FolioActions.note(base, course: course, path: path) }

    public func currentSemester() throws -> Semester {
        guard let s = try semesters().current(on: today) else { throw ActionError.notFound(String(localized: .errorNoSemester)) }
        return s
    }

    // 읽지 못한 과목 폴더는 건너뛴다. 명령줄이 과목을 찾는 목록(`Resolver.courses`)도 이 차례를 따른다.
    public func courses() -> [ReadCourse] {
        let catalog = (try? catalog()) ?? Catalog()
        return ((try? base.gist.courseStores()) ?? []).compactMap { s in
            guard let f = try? s.load().model else { return nil }
            return ReadCourse(
                file: f, store: s, code: StandardLayout.courseCode(of: f.course, folder: s.url.lastPathComponent, catalog: catalog))
        }
    }

    // 하나라도 읽지 못하면 실패한다. 학점과 GPA는 빠진 과목 없이 세야 하기 때문이다.
    public func allCourses() throws -> [Course] { try base.gist.allCourses() }

    #if os(macOS)
    public func backups() throws -> [BackupStore.Archive] {
        let folder = URL(filePath: (try settings().backup.folder as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        return BackupStore(gist: base.gist, folder: folder).archives()
    }
    #endif
}
