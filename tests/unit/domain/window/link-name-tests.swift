import FolioDomain
import Foundation
import Testing

struct LinkNameTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        c.locale = Locale(identifier: "ko_KR")
        return c
    }()

    @Test func itemsAreNamedFromTheirCourse() {
        let session = Session(device: device, at: now, week: 3, date: now)
        let unit = Unit(device: device, at: now, title: "매칭", order: 0)
        let exam = Exam(device: device, at: now, title: "중간고사")
        let material = Material(device: device, at: now, path: "Lectures/05_Matchings.pdf", status: .classified)
        let recorded = Recording(device: device, at: now, sessionId: session.id, file: "Recordings/a.m4a")
        let loose = Recording(device: device, at: now, sessionId: nil, file: "Recordings/b.m4a")
        let note = NoteEntry(id: UUID(), device: device, at: now, path: "Notes/기말 02 홀의 정리.md", meta: NoteMeta(kind: .unit))
        let file = CourseFile(
            course: Course(device: device, at: now, title: "그래프 이론"), materials: [material], units: [unit], sessions: [session],
            exams: [exam], recordings: [recorded, loose], notes: [note])
        func name(_ link: AppLink) -> LinkName? { LinkName(link, in: file, people: [], calendar: calendar) }

        #expect(name(AppLink(.unit, unit.id)) == .item("매칭"))
        #expect(name(AppLink(.exam, exam.id)) == .item("중간고사"))
        #expect(name(AppLink(.material, material.id, anchor: .page(3))) == .item("05_Matchings.pdf"))
        #expect(name(AppLink(.session, session.id)) == .item(file.title(of: session, calendar: calendar)))
        #expect(name(AppLink(.recording, recorded.id)) == .replay(day: file.day(of: session, calendar: calendar)))
        #expect(name(AppLink(.recording, loose.id)) == .replay(day: nil))
        #expect(name(AppLink(.exam, UUID())) == nil)
        // 노트와 그 카드 칸은 나란히 열리므로 이름이 달라야 한다.
        #expect(name(AppLink(.note, note.id)) == .item("기말 02 홀의 정리"))
        #expect(name(AppLink(.noteCards, note.id)) == .noteCards(note: "기말 02 홀의 정리") && name(AppLink(.noteCards, UUID())) == nil)
        #expect(LinkName.noteCards(note: "a").namesItem)
    }

    @Test func coursePagesAreNotItems() {
        let file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        let course = file.course.id
        #expect(LinkName(.course(course, page: .notes), in: file, people: [], calendar: calendar) == .page(.notes))
        #expect(LinkName(.course(course), in: file, people: [], calendar: calendar) == nil)
        #expect(LinkName(AppLink(.card, UUID()), in: file, people: [], calendar: calendar) == .page(.cards))
        #expect(LinkName(AppLink(.card, UUID()), in: nil, people: [], calendar: calendar) == nil)
        #expect(LinkName.page(.cards).namesItem == false)
        #expect(LinkName.replay(day: nil).namesItem)
    }

    @Test func peopleAndPlaces() {
        let person = Person(device: device, at: now, name: "김교수")
        #expect(LinkName(AppLink(.person, person.id), in: nil, people: [person], calendar: calendar) == .item("김교수"))
        for kind in AppLink.Kind.allCases where kind.isPlace {
            #expect(LinkName(.place(kind), in: nil, people: [person], calendar: calendar) == nil)
        }
    }
}
