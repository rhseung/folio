import FolioCore
import FolioDomain
import FolioStorage
import Foundation

// 화면, 계획 짜기, `study show`가 같은 집계를 쓰도록 과목 하나의 카드와 공부 기록을 한 곳에서 읽는다.
func courseStudy(file: CourseFile, store: CourseStore, settings: Settings, calendar: Calendar, now: Date) throws -> CourseStudy {
    let cards = try file.units.flatMap { try store.loadCards(unit: $0.id).model.cards }
    return CourseStudy(file: file, cards: cards, log: try store.log.readAll().studyLog, settings: settings, calendar: calendar, now: now)
}

extension ActionContext {
    func study(_ course: UUID) throws -> CourseStudy {
        try courseStudy(file: file(course), store: store(course), settings: settings(), calendar: calendar, now: now)
    }
}

extension ReadContext {
    func study(_ course: UUID) throws -> CourseStudy {
        try courseStudy(file: file(course), store: store(course), settings: settings(), calendar: calendar, now: now)
    }
}
