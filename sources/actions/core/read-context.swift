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
    public func name(of id: UUID) -> String? { base.name(of: id) }
}
