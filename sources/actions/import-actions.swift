import FolioDomain
import FolioStorage
import Foundation

func courseIDs(_ ctx: ActionContext) throws -> [String: UUID] {
    Dictionary(
        try ctx.gist.courseStores().map { ($0.url.lastPathComponent, try $0.load().model.course.id) }, uniquingKeysWith: { a, _ in a })
}

func shortTime(_ d: Date?) -> String { d?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? "-" }
func weekdayTime(_ d: Date) -> String { d.formatted(.dateTime.weekday().hour().minute()) }

@Action(
    "import notion", "노션 학기, 강의, 성적을 transcript.json, catalog.json, course.json으로",
    discussion: """
        export.json은 Notion MCP로 읽은 내용을 NotionExport 형식으로 담은 파일이다. transcript.json이나 catalog.json이
        이미 있으면 실행하지 않고(종료 코드 4), course.json이 있는 과목 폴더는 건너뛴다. 학기별 GPA를 노션 값과 비교한다.
        """,
    effect: .creates, done: "노션을 가져왔습니다", examples: ["folio import notion ~/Downloads/export.json --dry-run"], phrases: ["노션 가져오기"])
public struct ImportNotion {
    /// NotionExport JSON
    @Arg @FromFile("export.json") var export: NotionExport

    public func run(_ ctx: ActionContext) throws {
        let gist = ctx.gist
        for existing in [gist.transcriptURL, gist.catalogURL] where FileManager.default.fileExists(atPath: existing.path) {
            throw ActionError.rule(String(localized: .errorImportExists(ctx.relative(existing))))
        }
        let r = NotionImporter.convert(export, gist: try gist.readTree(), device: ctx.device, now: ctx.now)
        let courses = r.courseFiles.values.map(\.course)
        func gpa(_ name: String, _ s: GPACalculator.Summary) {
            ctx.note(
                String(
                    localized: .noteImportNotionGpa(
                        name, s.totalCredits.formatted(), s.effectiveCredits.formatted(), GPACalculator.label(s.gpa))))
        }
        for semester in r.transcript.semesters.sorted(by: { $0.order < $1.order }) {
            gpa(
                semester.folder?.name ?? String(localized: .valueCreditedSemester),
                GPACalculator.semester(semester, courses: courses, catalog: r.catalog))
        }
        gpa(
            String(localized: .valueCumulative),
            GPACalculator.cumulative(semesters: r.transcript.semesters, courses: courses, catalog: r.catalog))
        gpa(String(localized: .valueMajor), GPACalculator.major(courses: courses, catalog: r.catalog))

        ctx.record(Change(.added, ctx.relative(gist.catalogURL)))
        ctx.record(Change(.added, ctx.relative(gist.transcriptURL)))
        for (folder, file) in r.courseFiles.sorted(by: { $0.key < $1.key }) {
            let store = CourseStore(url: gist.url.appending(path: folder))
            if FileManager.default.fileExists(atPath: store.courseFileURL.path) {
                ctx.note(String(localized: .noteImportNotionCourseExists(folder)))
            } else {
                ctx.record(Change(.added, ctx.relative(store.courseFileURL)))
                ctx.note(
                    String(
                        localized: .noteImportNotionCourse(
                            folder, file.components.count, file.scores.count, file.exams.count, file.policy.attendanceCap.count)))
            }
        }
        for w in r.warnings { ctx.note(String(localized: .noteImportCheck(w))) }
        guard !ctx.dryRun else { return }
        _ = try gist.write(r)
        ctx.invalidate()
    }
}

@Action(
    "import notes", "노션 강의 정리와 점수를 노트, 회차, 성적 항목으로",
    discussion: """
        덤프 폴더는 과목마다 <노션 페이지 ID>/index.json, notes/, assets/를 가진다. 노트 ID가 노션 페이지 ID라서 다시
        실행해도 중복되지 않고, 기존 항목에는 덧붙이기만 한다.
        """,
    effect: .creates, done: "노션 강의 정리를 가져왔습니다", examples: ["folio import notes ~/Downloads/notion-dump --dry-run"],
    phrases: ["노션 강의 정리 가져오기"])
public struct ImportNotes {
    /// 덤프 폴더
    @Arg @Folder var folder: String

    public func run(_ ctx: ActionContext) throws {
        let root = URL(filePath: folder, directoryHint: .isDirectory)
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "index.json").path) }
            .sorted { $0.path < $1.path }
        let dumps = try folders.map {
            ($0, try JSONDecoder().decode(NotionCourseDump.self, from: Data(contentsOf: $0.appending(path: "index.json"))))
        }
        var links: [String: String] = [:]
        for (_, dump) in dumps {
            for n in dump.notes { links[n.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "")] = n.title }
        }

        for (dumpFolder, dump) in dumps {
            guard ctx.hasFolder(dump.coursePageId) else {
                if !dump.notes.isEmpty || !dump.scores.isEmpty {
                    ctx.note(String(localized: .noteImportNotesNoFolder(dump.title, dump.notes.count, dump.scores.count)))
                }
                continue
            }
            let store = try ctx.store(dump.coursePageId)
            // 파일이 아니라 항목으로 센다. Folio 밖에서 파일을 지우거나 이름을 바꾼 항목도 id와 경로를 갖고 있어서, 그 노트를
            // 다시 계획하면 둘을 모두 가진 둘째 항목이 생긴다.
            let existing = Set(try ctx.file(dump.coursePageId).notes.map(\.id))
            let r = NotionNotesImporter.merge(
                dump, into: try ctx.file(dump.coursePageId), existingNotes: existing, calendar: ctx.calendar, device: ctx.device,
                now: ctx.now)
            ctx.note(
                String(
                    localized: .noteImportNotesCourse(
                        dump.title, r.sessionsAdded, r.notes.count, r.componentsAdded, r.scoresAdded,
                        dump.images.filter { $0.file != nil }.count)))
            for w in r.warnings { ctx.note(String(localized: .noteImportNotesCheck(dump.title, w))) }

            var urls: [UUID: URL] = [:]
            for plan in r.notes where !existing.contains(plan.id) {
                let url = store.newNoteURL(
                    title: plan.title, format: .markdown, avoiding: Set(urls.values.map { $0.deletingPathExtension().lastPathComponent }))
                urls[plan.id] = url
                ctx.record(Change(.added, ctx.relative(url)))
            }

            if !ctx.dryRun { try store.writeNotionNotes(r.notes, dump: dump, folder: dumpFolder, links: links, at: urls) }
            let paths = urls.mapValues { store.notePath(of: $0) }
            try ctx.edit(dump.coursePageId) { f in
                f = r.file
                for plan in r.notes {
                    if let path = paths[plan.id] {
                        f.notes.append(NoteEntry(id: plan.id, device: ctx.device, at: ctx.now, path: path, meta: plan.meta))
                    }
                }
            }
        }
    }
}

@Action(
    "import calendar", "캘린더의 수업을 회차로",
    discussion: """
        meetings.json은 CalendarMeeting 목록이다. 이미 있는 회차는 빈 시각만 채우고, 범위 안에서 수업이 없는 날의
        회차는 휴강으로 표시하며, 수업 제목과 같은 이름의 복습 노트를 연결한다. lab 번호가 있는 수업은 그 실험의 단원(없으면
        Lab<번호> <수업 제목>으로 만든다)에 연결한다.
        """,
    effect: .creates, done: "캘린더 수업을 가져왔습니다", examples: ["folio import calendar ~/Downloads/meetings.json --dry-run"],
    phrases: ["캘린더 수업 가져오기", "시간표 가져오기"])
public struct ImportCalendar {
    /// CalendarMeeting 목록 JSON
    @Arg @FromFile("meetings.json") var meetings: [CalendarMeeting]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        let semesters = try ctx.transcript().semesters
        for (name, group) in Dictionary(grouping: meetings, by: \.course).sorted(by: { $0.key < $1.key }) {
            guard let id = ids[name] else {
                ctx.note(String(localized: .noteImportCalendarNoFolder(name, group.count)))
                continue
            }
            let store = try ctx.store(id)
            let file = try ctx.file(id)
            guard let start = semesters.first(where: { $0.id == file.course.semesterId })?.start else {
                ctx.note(String(localized: .noteImportCalendarNoStart(name)))
                continue
            }

            let r = CalendarImporter.merge(
                group, into: file, semesterStart: start, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            let notes = store.notes(in: file)
            let links = CalendarImporter.noteLinks(
                sessions: r.file.sessions, titles: r.titles, notes: notes.compactMap { n in n.meta.id.map { ($0, n.title, n.meta) } })
            ctx.note(String(localized: .noteImportCalendarCourse(name, r.added.count, r.filled.count, r.cancelled.count, links.count)))
            if !r.schedule.isEmpty {
                ctx.note(
                    String(
                        localized: .noteImportCalendarSchedule(
                            name,
                            r.schedule.map {
                                "\(ClassTime.weekdayNames[$0.weekday - 1]) \(String(format: "%02d:%02d-%02d:%02d", $0.startMinute / 60, $0.startMinute % 60, $0.endMinute / 60, $0.endMinute % 60)) \($0.room)"
                            }.joined(separator: ", "))))
            }

            let label = { (s: Session) in r.file.units(of: s).first?.title ?? r.titles[s.id] ?? "" }
            for s in r.added {
                ctx.note(
                    "+ \(r.file.reference(of: s, calendar: ctx.calendar)) \(weekdayTime(s.date))\(label(s).isEmpty ? "" : " · \(label(s))")"
                )
            }
            for s in r.filled {
                ctx.note(
                    "~ \(r.file.reference(of: s, calendar: ctx.calendar)) \(weekdayTime(s.date))\(label(s).isEmpty ? "" : " · \(label(s))")"
                )
            }
            for s in r.cancelled {
                ctx.note(
                    String(localized: .noteImportCalendarCancelled(r.file.reference(of: s, calendar: ctx.calendar), weekdayTime(s.date))))
            }

            var result = r.file
            for l in links {
                guard let note = notes.first(where: { $0.meta.id == l.note }), let n = result.notes.firstIndex(where: { $0.id == l.note }),
                    let i = result.sessions.firstIndex(where: { $0.id == l.session })
                else { continue }
                ctx.note(
                    String(
                        localized: .noteImportCalendarNoteLink(result.reference(of: result.sessions[i], calendar: ctx.calendar), note.title)
                    ))
                result.notes[n].kind = .review
                result.notes[n].touch(by: ctx.device, at: ctx.now)
                result.sessions[i].reviewNoteId = l.note
                result.sessions[i].touch(by: ctx.device, at: ctx.now)
            }
            try ctx.edit(id) { $0 = result }
        }
    }
}

@Action(
    "import exams", "캘린더의 시험을 시험으로",
    discussion: """
        exams.json은 구글 캘린더 "시험" 캘린더에서 읽은 CalendarExam 목록이다. 같은 날 시험은 빈 칸만 채우고, 다른 날이면
        바꾸지 않고 알린다.
        """,
    effect: .creates, done: "시험을 가져왔습니다", examples: ["folio import exams ~/Downloads/exams.json --dry-run"],
    phrases: ["캘린더 시험 가져오기", "시험 일정 불러오기"])
public struct ImportExams {
    /// CalendarExam 목록 JSON
    @Arg @FromFile("exams.json") var exams: [CalendarExam]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        for (name, group) in Dictionary(grouping: exams, by: \.course).sorted(by: { $0.key < $1.key }) {
            guard let id = ids[name] else {
                ctx.note(String(localized: .noteImportNoFolder(name)))
                continue
            }
            let r = CalendarImporter.mergeExams(group, into: try ctx.file(id), calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            for x in r.added { ctx.note("\(name) + \(x.title) \(shortTime(x.start))–\(shortTime(x.end)) \(x.location)") }
            for x in r.filled {
                ctx.note(
                    "\(name) ~ \(x.title) \(shortTime(x.start))–\(shortTime(x.end)) \(x.location)\(x.memo.isEmpty ? "" : " · \(x.memo)")")
            }
            for c in r.conflicts {
                ctx.note(
                    String(localized: .noteImportExamsConflict(name, c.exam.title, shortTime(c.exam.start), shortTime(c.calendar.start))))
            }
            if r.added.isEmpty && r.filled.isEmpty && r.conflicts.isEmpty { ctx.note(String(localized: .noteImportExamsUnchanged(name))) }
            if !r.added.isEmpty || !r.filled.isEmpty { try ctx.edit(id) { $0 = r.file } }
        }
    }
}

@Action(
    "import units", "단원 표를 단원으로",
    discussion: """
        파일마다 {"course": <과목 폴더 이름>, "units": [{"title", "sessions": ["11-03"], "children"}]}. 제목으로 맞춰
        없는 단원만 더하고, 회차 연결은 더하기만 한다.
        """,
    effect: .creates, done: "단원을 가져왔습니다", examples: ["folio import units ~/Downloads/EC4207-units.json --dry-run"], phrases: ["단원 표 가져오기"])
public struct ImportUnits {
    /// 단원 JSON
    @Arg @FromFile("units.json", perItem: true) var files: [UnitFile]

    public func run(_ ctx: ActionContext) throws {
        let ids = try courseIDs(ctx)
        for units in files {
            guard let id = ids[units.course] else {
                ctx.note(String(localized: .noteImportNoFolder(units.course)))
                continue
            }
            let r = UnitImporter.merge(units.units, into: try ctx.file(id), calendar: ctx.calendar, device: ctx.device, now: ctx.now)
            ctx.note(String(localized: .noteImportUnitsCourse(units.course, r.added.count, r.linked.count)))
            for title in r.added { ctx.note("+ \(title)") }
            if !r.unknownSessions.isEmpty {
                ctx.note(String(localized: .noteImportUnitsUnknownSessions(units.course, r.unknownSessions.joined(separator: ", "))))
            }
            if !r.added.isEmpty || !r.linked.isEmpty { try ctx.edit(id) { $0 = r.file } }
        }
    }
}

@Action(
    "import requirements", "졸업 요건 분류와 학생 정보", discussion: "강의 코드 표에 없는 코드가 있으면 실행하지 않는다(종료 코드 4).",
    done: "졸업 요건을 가져왔습니다", examples: ["folio import requirements ~/Downloads/requirements.json --dry-run"], phrases: ["졸업 요건 가져오기"])
public struct ImportRequirements {
    /// RequirementFile JSON
    @Arg @FromFile("requirements.json") var file: RequirementFile

    public func run(_ ctx: ActionContext) throws {
        let catalog = try ctx.catalog()
        let codes = catalog.codes
        for prefix in Set(file.categories.compactMap(\.program) + (file.programs ?? []).map(\.code))
        where RequirementImporter.code(prefix, in: codes) == nil {
            throw ActionError.rule(String(localized: .errorImportUnknownCode(prefix)))
        }

        let r = RequirementImporter.merge(file.categories, into: catalog.categories, codes: codes, device: ctx.device, now: ctx.now)
        let fmt = { (c: FolioDomain.Category) in
            let parent = c.parentId.flatMap { id in r.categories.first { $0.id == id }?.name }.map { " ⊂ \($0)" } ?? ""
            let credits = [
                c.minCredits.map { String(localized: .valueCreditsMin($0.formatted())) },
                c.maxCredits.map { String(localized: .valueCreditsMax($0.formatted())) },
                c.minCount.map { String(localized: .valueCourseCount($0)) },
                c.maxSharedCredits.map { String(localized: .valueCreditsShared($0.formatted())) },
            ].compactMap { $0 }.joined(separator: ", ")
            let program = c.programId.flatMap { id in codes.first { $0.id == id }?.prefix }.map { " (\($0))" } ?? ""
            return "\(c.name) [\(c.group)]\(program)\(parent) \(credits)"
        }

        for name in r.added { ctx.note("+ " + fmt(r.categories.first { $0.name == name }!)) }
        for name in r.changed {
            let after = r.categories.first { $0.name == name }!
            let before = catalog.categories.first { $0.id == after.id }!
            ctx.note(
                "~ " + fmt(after) + (before.name != after.name ? String(localized: .noteImportRequirementsRenamed(before.name)) : "")
                    + String(localized: .noteImportRequirementsBefore) + fmt(before))
        }
        for name in r.untouched { ctx.note(String(localized: .noteImportRequirementsUntouched(name))) }

        try ctx.editCatalog { $0.categories = r.categories }
        try ctx.editTranscript { t in
            if let year = file.admissionYear { t.graduation.admissionYear = year }
            if let programs = file.programs {
                t.graduation.programs = programs.map {
                    StudentProgram(codeId: RequirementImporter.code($0.code, in: codes)!.id, kind: $0.kind)
                }
            }
        }
    }
}

@Action(
    "import handbook", "학사편람 분류 표",
    discussion: "같은 해 표는 바꾼다. 과목의 분류 제안을 보여 주며, 앱의 졸업 요건 화면에서 승인하거나 --accept로 바로 적용한다.",
    done: "학사편람을 가져왔습니다",
    examples: [
        "folio import handbook ~/Downloads/handbook-2023.json --dry-run", "folio import handbook ~/Downloads/handbook-2023.json --accept",
    ],
    phrases: ["학사편람 가져오기"])
public struct ImportHandbook {
    /// Handbook JSON
    @Arg @FromFile("handbook.json") var handbook: Handbook
    /// 분류 제안을 과목에 바로 적용
    var accept: Bool = false

    public func run(_ ctx: ActionContext) throws {
        var catalog = try ctx.catalog()
        let unknown = Set(handbook.areas.values).subtracting(catalog.categories.map(\.name))
        guard unknown.isEmpty else {
            throw ActionError.rule(String(localized: .errorImportUnknownCategory(unknown.sorted().joined(separator: ", "))))
        }

        catalog.handbooks.removeAll { $0.year == handbook.year }
        catalog.handbooks.append(handbook)
        catalog.handbooks.sort { $0.year < $1.year }
        for (name, n) in Dictionary(grouping: handbook.areas.values, by: { $0 }).mapValues(\.count).sorted(by: { $0.key < $1.key }) {
            ctx.note(String(localized: .noteImportHandbookArea(handbook.year, name, n)))
        }

        let courses = try ctx.gist.allCourses()
        let suggestions = HandbookClassifier.suggest(courses: courses, semesters: try ctx.transcript().semesters, catalog: catalog)
        for s in suggestions {
            ctx.note(
                String(
                    localized: .noteImportHandbookSuggestion(
                        courses.first { $0.id == s.courseId }!.title, s.code, catalog.category(s.categoryId)!.name)))
        }
        try ctx.editCatalog { $0.handbooks = catalog.handbooks }

        guard accept else { return }
        let byId = Dictionary(keepingFirst: suggestions.map { ($0.courseId, $0.categoryIds) })
        for id in try courseIDs(ctx).values.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let ids = byId[id] else { continue }
            try ctx.edit(id) { $0.course.categoryIds = ids }
        }
    }
}
