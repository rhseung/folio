import FolioActions
import FolioAI
import FolioDomain
import FolioStorage
import Foundation

/// A logged attempt and the study day it counts for.
struct Attempt<Event: LogEvent> {
    var at: Date
    var day: LocalDate
    var event: Event
}

extension Workspace {
    func units(of course: LoadedCourse) -> [FolioDomain.Unit] {
        UnitTree.outline(course.file.units).map(\.unit)
    }

    /// Every unit's cards, in unit order.
    func quizCards(_ course: LoadedCourse) -> [QuizCard] {
        units(of: course).flatMap { (try? course.store.loadQuiz(unit: $0.id).model.cards) ?? [] }
    }

    func attempts<E: LogEvent>(_: E.Type, in course: LoadedCourse) -> [Attempt<E>] {
        ((try? course.store.log.readAll()) ?? []).events(E.self).map {
            Attempt(at: $0.at, day: settings.studyDay(of: $0.at, calendar: calendar), event: $0.event)
        }
    }

    var today: LocalDate { settings.studyDay(of: .now, calendar: calendar) }

    /// Whether `date` falls on today's study day: a class at 23:00 is still "today" at 01:00, before the day boundary.
    func isStudyToday(_ date: Date) -> Bool { settings.studyDay(of: date, calendar: calendar) == today }

    /// Study days from today to `date`, so a D-day doesn't jump at midnight while the day boundary is still ahead.
    func days(to date: Date) -> Int { today.days(until: LocalDate(date, in: calendar)) }

    /// The course summary plus the unit's notes: those tagged with the unit and those of its sessions.
    func cardContext(_ course: LoadedCourse, unit: FolioDomain.Unit) -> [ContextItem] {
        [ContextBuilder.courseSummary(course.file, now: .now)] + notes(for: unit, in: course.id).compactMap { note in
            (try? course.store.read(note)).map { ContextItem(id: "note:\(note.title)", title: "노트 \(note.title)", tier: .focus, text: $0) }
        }
    }
}
