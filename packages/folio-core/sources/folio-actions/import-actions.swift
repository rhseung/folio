import FolioDomain
import FolioStorage
import Foundation

// One-time imports from Notion, the calendar and hand-written tables (docs/SPEC.md "기존 데이터 이전"). A dry run is the
// plan to review; `ctx.notes` carries what was skipped or needs checking.

/// Course folder name (`EC4207 그래프 이론`) to course id, for payloads that name courses by folder.
func courseIDs(_ ctx: ActionContext) throws -> [String: UUID] {
    Dictionary(try ctx.gist.courseStores().map { ($0.url.lastPathComponent, try $0.load().model.course.id) }, uniquingKeysWith: { a, _ in a })
}

func shortTime(_ d: Date?) -> String { d?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? "-" }

/// Writes transcript.json, catalog.json and the course.json of every matched folder. Never overwrites: refuses when
/// transcript.json or catalog.json exists, and skips folders that already have a course.json.
@Action("import notion", "노션 학기, 강의, 성적을 transcript.json, catalog.json, course.json으로", effect: .creates, done: "노션을 가져왔습니다", phrases: ["노션 가져오기"], cli: .manual)
public struct ImportNotion {
    var export: NotionExport

    public func run(_ ctx: ActionContext) throws {
        let gist = ctx.gist
        for existing in [gist.transcriptURL, gist.catalogURL] where FileManager.default.fileExists(atPath: existing.path) {
            throw ActionError.rule("이미 있어 덮어쓰지 않습니다: \(ctx.relative(existing))")
        }
        let r = NotionImporter.convert(export, gist: try gist.readTree(), device: ctx.device, now: ctx.now)
        let courses = r.transcript.courses + r.courseFiles.values.map(\.course)
        func gpa(_ name: String, _ s: GPACalculator.Summary) {
            ctx.note("\(name): 총 \(s.totalCredits.formatted())학점, 유효 \(s.effectiveCredits.formatted())학점, GPA \(GPACalculator.label(s.gpa))")
        }
        for semester in r.transcript.semesters.sorted(by: { $0.order < $1.order }) {
            gpa(semester.folder?.name ?? "인정학기", GPACalculator.semester(semester, courses: courses, catalog: r.catalog))
        }
        gpa("누적", GPACalculator.cumulative(semesters: r.transcript.semesters, courses: courses, catalog: r.catalog))
        gpa("전공", GPACalculator.major(courses: courses, catalog: r.catalog))

        ctx.record(Change(.added, ctx.relative(gist.catalogURL)))
        ctx.record(Change(.added, ctx.relative(gist.transcriptURL)))
        for (folder, file) in r.courseFiles.sorted(by: { $0.key < $1.key }) {
            let store = CourseStore(url: gist.url.appending(path: folder))
            if FileManager.default.fileExists(atPath: store.courseFileURL.path) {
                ctx.note("\(folder): course.json이 있어 건너뜀")
            } else {
                ctx.record(Change(.added, ctx.relative(store.courseFileURL)))
                ctx.note("\(folder): 평가 항목 \(file.components.count), 점수 \(file.scores.count), 시험 \(file.exams.count), 결석 상한 \(file.policy.attendanceCap.count)")
            }
        }
        for course in r.transcript.courses { ctx.note("폴더 없는 과목(transcript.json): \(course.title)") }
        for w in r.warnings { ctx.note("확인 필요: \(w)") }
        guard !ctx.dryRun else { return }
        _ = try gist.write(r)
        ctx.invalidate()
    }
}

/// Notion lecture notes and score tables, from a dump folder holding `<page id>/index.json`, `notes/`, `assets/` per
/// course. Note ids are Notion page ids, so running it again adds nothing twice.
@Action("import notes", "노션 강의 정리와 점수를 노트, 회차, 성적 항목으로", effect: .creates, done: "노션 강의 정리를 가져왔습니다", phrases: ["노션 강의 정리 가져오기"], cli: .manual)
public struct ImportNotes {
    /// An absolute path.
    var folder: String

    public func run(_ ctx: ActionContext) throws {
        let root = URL(filePath: folder, directoryHint: .isDirectory)
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "index.json").path) }
            .sorted { $0.path < $1.path }
        let dumps = try folders.map { ($0, try JSONDecoder().decode(NotionCourseDump.self, from: Data(contentsOf: $0.appending(path: "index.json")))) }
        // Mentions between imported pages become wikilinks.
        var links: [String: String] = [:]
        for (_, dump) in dumps { for n in dump.notes { links[n.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")] = n.title } }
        for (dumpFolder, dump) in dumps {
            guard ctx.hasFolder(dump.coursePageId) else {
                if !dump.notes.isEmpty || !dump.scores.isEmpty { ctx.note("\(dump.title): 과목 폴더가 없어 건너뜀 (노트 \(dump.notes.count), 점수 \(dump.scores.count))") }
                continue
            }
            let store = try ctx.store(dump.coursePageId)
            let existing = Set(try store.notes().compactMap(\.meta.id))
            let r = NotionNotesImporter.merge(dump, into: try ctx.file(dump.coursePageId), existingNotes: existing, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            ctx.note("\(dump.title): 회차 +\(r.sessionsAdded), 노트 +\(r.notes.count), 평가 항목 +\(r.componentsAdded), 점수 +\(r.scoresAdded), 그림 \(dump.images.filter { $0.file != nil }.count)")
            for w in r.warnings { ctx.note("\(dump.title) 확인: \(w)") }
            for plan in r.notes where !existing.contains(plan.id) {
                ctx.record(Change(.added, try ctx.relative(dump.coursePageId, "\(CourseFolder.notes.rawValue)/\(plan.title).md")))
            }
            if !ctx.dryRun { try store.writeNotionNotes(r.notes, dump: dump, folder: dumpFolder, links: links) }
            try ctx.edit(dump.coursePageId) { $0 = r.file }
        }
    }
}

/// Class meetings from the calendar become sessions; days in the span without a meeting become cancelled, and review
/// notes named after a session get linked to it.
@Action("import calendar", "캘린더의 수업을 회차로", effect: .creates, done: "캘린더 수업을 가져왔습니다", phrases: ["캘린더 수업 가져오기", "시간표 가져오기"], cli: .manual)
public struct ImportCalendar {
    var meetings: [CalendarMeeting]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        let semesters = try ctx.transcript().semesters
        for (name, group) in Dictionary(grouping: meetings, by: \.course).sorted(by: { $0.key < $1.key }) {
            guard let id = ids[name] else {
                ctx.note("\(name): 과목 폴더가 없어 건너뜀 (\(group.count)회)")
                continue
            }
            let store = try ctx.store(id)
            let file = try ctx.file(id)
            guard let start = semesters.first(where: { $0.id == file.course.semesterId })?.start else {
                ctx.note("\(name): 학기 시작일이 없어 건너뜀")
                continue
            }
            let r = CalendarImporter.merge(group, into: file, semesterStart: start, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            let notes = try store.notes()
            let links = CalendarImporter.noteLinks(sessions: r.file.sessions, notes: notes.compactMap { n in n.meta.id.map { ($0, n.title, n.meta.sessionId) } })
            ctx.note("\(name): 회차 +\(r.added.count), 시각·주제 보정 \(r.filled.count), 휴강 \(r.cancelled.count), 노트 연결 \(links.count)")
            if !r.schedule.isEmpty {
                ctx.note("\(name) 시간표: " + r.schedule.map { "\(ClassTime.weekdayNames[$0.weekday - 1]) \(String(format: "%02d:%02d-%02d:%02d", $0.startMinute / 60, $0.startMinute % 60, $0.endMinute / 60, $0.endMinute % 60)) \($0.room)" }.joined(separator: ", "))
            }
            for s in r.added {
                // A lab's unit title already holds its topic.
                let label = r.file.units(of: s).first?.title ?? s.topic
                ctx.note("+ \(s.name(among: r.file.sessions)) \(shortTime(s.date))\(label.isEmpty ? "" : " · \(label)")")
            }
            for s in r.filled { ctx.note("~ \(s.name(among: r.file.sessions)) \(shortTime(s.date))\(s.topic.isEmpty ? "" : " · \(s.topic)")") }
            for s in r.cancelled { ctx.note("휴강 \(s.name(among: r.file.sessions)) \(shortTime(s.date))") }
            var result = r.file
            for l in links {
                guard var note = notes.first(where: { $0.meta.id == l.note }), let i = result.sessions.firstIndex(where: { $0.id == l.session }) else { continue }
                ctx.note("노트 \(result.sessions[i].name(among: result.sessions)) ← \(note.title).md")
                let text = try store.read(note)
                note.meta.sessionId = l.session
                try ctx.io(Change(.changed, ctx.relative(note.url))) { try store.save(note, text: text) }
                result.sessions[i].reviewNoteId = l.note
                result.sessions[i].touch(by: ctx.device, at: ctx.now)
            }
            try ctx.edit(id) { $0 = result }
        }
    }
}

/// Exams from the calendar's "시험" calendar. An exam on the same day only fills blanks; one on another day is left
/// alone and reported.
@Action("import exams", "캘린더의 시험을 시험으로", effect: .creates, done: "시험을 가져왔습니다", phrases: ["캘린더 시험 가져오기", "시험 일정 불러오기"], cli: .manual)
public struct ImportExams {
    var exams: [CalendarExam]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        for (name, group) in Dictionary(grouping: exams, by: \.course).sorted(by: { $0.key < $1.key }) {
            guard let id = ids[name] else {
                ctx.note("\(name): 과목 폴더가 없어 건너뜀")
                continue
            }
            let r = CalendarImporter.mergeExams(group, into: try ctx.file(id), calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            for x in r.added { ctx.note("\(name) + \(x.title) \(shortTime(x.start))–\(shortTime(x.end)) \(x.location)") }
            for x in r.filled { ctx.note("\(name) ~ \(x.title) \(shortTime(x.start))–\(shortTime(x.end)) \(x.location)\(x.memo.isEmpty ? "" : " · \(x.memo)")") }
            for c in r.conflicts { ctx.note("\(name) 다름 \(c.exam.title): 파일 \(shortTime(c.exam.start)), 캘린더 \(shortTime(c.calendar.start)). 그대로 둠") }
            if r.added.isEmpty && r.filled.isEmpty && r.conflicts.isEmpty { ctx.note("\(name): 바뀐 것 없음") }
            if !r.added.isEmpty || !r.filled.isEmpty { try ctx.edit(id) { $0 = r.file } }
        }
    }
}

/// Units matched by title: only missing ones are added, and session links are only added.
@Action("import units", "단원 표를 단원으로", effect: .creates, done: "단원을 가져왔습니다", phrases: ["단원 표 가져오기"], cli: .manual)
public struct ImportUnits {
    var files: [UnitFile]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        for units in files {
            guard let id = ids[units.course] else {
                ctx.note("\(units.course): 과목 폴더가 없어 건너뜀")
                continue
            }
            let r = UnitImporter.merge(units.units, into: try ctx.file(id), device: ctx.device, now: ctx.now)
            ctx.note("\(units.course): 단원 +\(r.added.count), 회차 연결 +\(r.linked.count)")
            for title in r.added { ctx.note("+ \(title)") }
            if !r.unknownSessions.isEmpty { ctx.note("\(units.course) 없는 회차: \(r.unknownSessions.joined(separator: ", "))") }
            if !r.added.isEmpty || !r.linked.isEmpty { try ctx.edit(id) { $0 = r.file } }
        }
    }
}

/// Graduation requirement categories into catalog.json, and the student's admission year and programs into
/// transcript.json.
@Action("import requirements", "졸업 요건 분류와 학생 정보", done: "졸업 요건을 가져왔습니다", phrases: ["졸업 요건 가져오기"], cli: .manual)
public struct ImportRequirements {
    var file: RequirementFile

    public func run(_ ctx: ActionContext) throws {
        let catalog = try ctx.catalog()
        let codes = catalog.codes
        for prefix in Set(file.categories.compactMap(\.program) + (file.programs ?? []).map(\.code)) where RequirementImporter.code(prefix, in: codes) == nil {
            throw ActionError.rule("강의 코드 표에 \(prefix)가 없습니다")
        }
        let r = RequirementImporter.merge(file.categories, into: catalog.categories, codes: codes, device: ctx.device, now: ctx.now)
        let fmt = { (c: FolioDomain.Category) in
            let parent = c.parentId.flatMap { id in r.categories.first { $0.id == id }?.name }.map { " ⊂ \($0)" } ?? ""
            let credits = [c.minCredits.map { "최소 \($0.formatted())" }, c.maxCredits.map { "최대 \($0.formatted())" }, c.minCount.map { "\($0)과목" },
                           c.maxSharedCredits.map { "이중 계산 \($0.formatted())" }].compactMap { $0 }.joined(separator: ", ")
            let program = c.programId.flatMap { id in codes.first { $0.id == id }?.prefix }.map { " (\($0))" } ?? ""
            return "\(c.name) [\(c.group)]\(program)\(parent) \(credits)"
        }
        for name in r.added { ctx.note("+ " + fmt(r.categories.first { $0.name == name }!)) }
        for name in r.changed {
            let after = r.categories.first { $0.name == name }!
            let before = catalog.categories.first { $0.id == after.id }!
            ctx.note("~ " + fmt(after) + (before.name != after.name ? "  (이름: \(before.name))" : "") + "  이전: " + fmt(before))
        }
        for name in r.untouched { ctx.note("그대로: \(name)") }
        try ctx.editCatalog { $0.categories = r.categories }
        try ctx.editTranscript { t in
            if let year = file.admissionYear { t.graduation.admissionYear = year }
            if let programs = file.programs {
                t.graduation.programs = programs.map { StudentProgram(codeId: RequirementImporter.code($0.code, in: codes)!.id, kind: $0.kind) }
            }
        }
    }
}

/// A year's handbook (학사편람) area table into catalog.json, replacing the same year. With `accept`, the suggested
/// categories are set on the courses too; otherwise they wait for approval in the app.
@Action("import handbook", "학사편람 분류 표", done: "학사편람을 가져왔습니다", phrases: ["학사편람 가져오기"], cli: .manual)
public struct ImportHandbook {
    var handbook: Handbook
    var accept: Bool = false

    public func run(_ ctx: ActionContext) throws {
        var catalog = try ctx.catalog()
        let unknown = Set(handbook.areas.values).subtracting(catalog.categories.map(\.name))
        guard unknown.isEmpty else { throw ActionError.rule("catalog.json에 없는 분류: \(unknown.sorted().joined(separator: ", "))") }
        catalog.handbooks.removeAll { $0.year == handbook.year }
        catalog.handbooks.append(handbook)
        catalog.handbooks.sort { $0.year < $1.year }
        for (name, n) in Dictionary(grouping: handbook.areas.values, by: { $0 }).mapValues(\.count).sorted(by: { $0.key < $1.key }) {
            ctx.note("\(handbook.year) \(name): \(n)과목")
        }
        let courses = try ctx.gist.allCourses()
        let suggestions = HandbookClassifier.suggest(courses: courses, semesters: try ctx.transcript().semesters, catalog: catalog)
        for s in suggestions {
            ctx.note("제안 \(courses.first { $0.id == s.courseId }!.title) \(s.code) → \(catalog.category(s.categoryId)!.name)")
        }
        try ctx.editCatalog { $0.handbooks = catalog.handbooks }
        guard accept else { return }
        let byId = Dictionary(keepingFirst: suggestions.map { ($0.courseId, $0.categoryIds) })
        for id in try courseIDs(ctx).values.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let ids = byId[id] else { continue }
            try ctx.edit(id) { $0.course.categoryIds = ids }
        }
        try ctx.editTranscript { t in
            for i in t.courses.indices {
                guard let ids = byId[t.courses[i].id] else { continue }
                t.courses[i].categoryIds = ids
                t.courses[i].touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}
