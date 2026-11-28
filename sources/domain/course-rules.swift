import FolioCore
import Foundation

// 앱은 규칙을 어기는 값을 숨기지만 `folio run`은 엔티티 전체를 받아 어느 필드에든 닿는다. 그래서 어느 액션이 썼든
// 저장하는 파일 전체에서 규칙을 검사한다.

extension Course {
    static func members<Doc: Sendable>() -> [Member<Doc, Course>] {
        [
            NonEmpty(\.title, String(localized: .courseTitleEmpty)),
            Check("Course.credits", String(localized: .ruleCourseCredits)) { c, _ in c.credits >= 0 },
            Check("Course.schedule", String(localized: .ruleCourseSchedule)) { c, _ in
                c.schedule.allSatisfy {
                    (1...7).contains($0.weekday) && $0.startMinute >= 0 && $0.endMinute <= 24 * 60 && $0.endMinute > $0.startMinute
                }
            },
            Check("Course.scheduleLink", String(localized: .ruleCourseScheduleLink)) { c, _ in
                c.schedule.allSatisfy { $0.link.map { OnlineLink.url($0) != nil } ?? true }
            },
            Ref(\.semesterId, to: Semester.self, onDelete: .restrict),
            Ref(\.syllabusMaterialId, to: Material.self, as: String(localized: .modelLabelSyllabus), onDelete: .nullify),
            Check("Course.semester", String(localized: .ruleCourseSemester)) { c, _, w in
                guard let t = w.transcript, let s = c.semesterId else { return true }
                return t.semesters.contains { $0.id == s }
            },
            Check("Course.codes", String(localized: .ruleCourseCodes)) { c, _, w in
                w.catalog.map { cat in c.codes.allSatisfy { cat.code($0) != nil } } ?? true
            },
            Check("Course.categories", String(localized: .ruleCourseCategories)) { c, _, w in
                w.catalog.map { cat in c.categoryIds.allSatisfy { cat.category($0) != nil } } ?? true
            },
            Check("Course.instructors", String(localized: .ruleCourseInstructors)) { c, _, w in
                w.catalog.map { cat in c.instructorIds.allSatisfy { id in cat.people.contains { $0.id == id } } } ?? true
            },
            Check("Course.finalGrade", String(localized: .ruleCourseFinalGrade)) { c, _, w in
                guard let cat = w.catalog, let g = c.finalGrade else { return true }
                return cat.grades(for: c.gradingMode).contains { $0.id == g }
            },
            Check("Course.targetGrade", String(localized: .ruleCourseTargetGrade)) { c, _, w in
                guard let cat = w.catalog, let g = c.targetGrade else { return true }
                return cat.grades(for: c.gradingMode).contains { $0.id == g }
            },
            Check("Course.sharing", String(localized: .ruleCourseSharing)) { c, _, w in
                guard let cat = w.catalog, c.categoryIds.allSatisfy({ cat.category($0) != nil }) else { return true }
                return !GPACalculator.blocksSharing(c, categoryIds: c.categoryIds, catalog: cat)
            },
        ]
    }
}

extension Session {
    var materialIds: [UUID] {
        get { materials.map(\.materialId) }
        set { materials = materials.filter { newValue.contains($0.materialId) } }
    }
}

extension ExamPlanItem {
    var noteTarget: UUID? {
        get { target.kind == .note ? target.id : nil }
        set { if target.kind == .note { target.id = newValue } }
    }

    var unitTarget: UUID? {
        get { target.kind == .makeNote ? target.id : nil }
        set { if target.kind == .makeNote { target.id = newValue } }
    }

    // 앱이 놓은 항목은 제목을 저장하지 않으므로 대상에서 만든 이름으로 부른다.
    static func name(_ item: ExamPlanItem, in file: CourseFile) -> String { file.title(of: item) }
}

extension ProblemSet {
    var problemUnitIds: [UUID] {
        get { problems.flatMap(\.unitIds) }
        set { for i in problems.indices { problems[i].unitIds = problems[i].unitIds.filter(newValue.contains) } }
    }
}

extension CourseFile: Document {
    public static let model = Model<CourseFile>(place: String(localized: .modelPlaceCourse)) {
        One(\.course, noun: ItemKind.course.noun, name: \.title) { Course.members() }
        Items(\.materials, noun: ItemKind.material.noun, name: \.path) {
            Ref(\.sourceOf, to: Material.self, onDelete: .nullify)
            Ref(\.solutionOf, to: Material.self, onDelete: .nullify)
            Refs(\.sessionIds, to: Session.self, onDelete: .nullify)
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
            Refs(\.examIds, to: Exam.self, onDelete: .nullify)
        }
        Items(\.units, noun: ItemKind.unit.noun, name: \.title) {
            NonEmpty(\.title, String(localized: .ruleUnitTitleEmpty))
            Ref(\.parentId, to: Unit.self, as: String(localized: .modelLabelParentUnit), onDelete: .reparent)
            Refs(\.lectureMaterialIds, to: Material.self, onDelete: .nullify)
            Check("Unit.pages", String(localized: .ruleUnitPages)) { u, _ in
                u.lecturePages.allSatisfy { $0.firstPage >= 1 && $0.firstPage <= $0.lastPage }
            }
        }
        Items(\.sessions, noun: ItemKind.session.noun, name: { s, f in f.title(of: s, calendar: .current) }) {
            Refs(\.addedUnitIds, to: Unit.self, onDelete: .nullify)
            Refs(\.removedUnitIds, to: Unit.self, onDelete: .nullify)
            Refs(\.materialIds, to: Material.self, onDelete: .nullify)
            Ref(\.roughNoteId, to: NoteEntry.self, onDelete: .nullify)
            Ref(\.reviewNoteId, to: NoteEntry.self, onDelete: .nullify)
            Check("Session.noteKind", String(localized: .ruleSessionNoteKind)) { s, f in
                [(s.roughNoteId, NoteKind.rough), (s.reviewNoteId, .review)].allSatisfy { id, kind in
                    id.map { id in f.notes.first { $0.id == id }.map { $0.kind == kind } ?? true } ?? true
                }
            }
            Check("Session.time", String(localized: .ruleSessionTime)) { s, _ in s.end.map { $0 > s.date } ?? true }
            Check("Session.link", String(localized: .ruleSessionLink)) { s, _ in s.link.map { OnlineLink.url($0) != nil } ?? true }
            Check("Session.pages", String(localized: .ruleSessionPages)) { s, _ in
                s.materials.allSatisfy { m in
                    (m.firstPage ?? 1) >= 1 && (m.lastPage ?? 1) >= 1 && (m.firstPage ?? 1) <= (m.lastPage ?? Int.max)
                }
            }
        }
        Items(\.exams, noun: ItemKind.exam.noun, name: \.title) {
            NonEmpty(\.title, String(localized: .ruleExamTitleEmpty))
            Check("Exam.time", String(localized: .ruleExamTime)) { e, _ in
                switch (e.start, e.end) {
                case (nil, .some): false
                case (let s?, let t?): t > s
                default: true
                }
            }
            Ref(\.componentId, to: GradeComponent.self, onDelete: .nullify)
            Refs(\.addedScopeUnitIds, to: Unit.self, as: String(localized: .modelLabelScopeUnit), onDelete: .nullify)
            Refs(\.removedScopeUnitIds, to: Unit.self, as: String(localized: .modelLabelScopeUnit), onDelete: .nullify)
            Check("Exam.planPeriod", String(localized: .ruleExamPlanPeriod)) { e, _ in e.planPeriod?.isValid ?? true }
        }
        Items(\.exams, \.plan, noun: ItemKind.examPlanItem.noun, name: ExamPlanItem.name) {
            Check("ExamPlanItem.title", String(localized: .ruleExamPlanItemTitleEmpty)) { i, _ in
                i.target.kind != .custom || !i.title.trimmingCharacters(in: .whitespaces).isEmpty
            }
            Check("ExamPlanItem.target", String(localized: .ruleExamPlanItemTarget)) { i, _ in
                switch i.target.kind {
                case .note: i.target.id != nil && i.target.stage != nil
                case .makeNote: i.target.id != nil
                case .mock, .custom: true
                }
            }
            Ref(\.noteTarget, to: NoteEntry.self, onDelete: .cascade)
            Ref(\.unitTarget, to: Unit.self, onDelete: .cascade)
        }
        Items(\.assignments, noun: ItemKind.assignment.noun, name: \.title) {
            NonEmpty(\.title, String(localized: .ruleAssignmentTitleEmpty))
            Ref(\.componentId, to: GradeComponent.self, onDelete: .nullify)
            Check("Assignment.componentGroup", String(localized: .ruleAssignmentComponentGroup)) { a, f in
                a.componentGroup.map { g in f.components.contains { $0.group == g } } ?? true
            }
            Ref(\.problemMaterialId, to: Material.self, as: String(localized: .modelLabelProblemMaterial), onDelete: .nullify)
            Refs(\.submissionMaterialIds, to: Material.self, as: String(localized: .modelLabelSubmissionMaterial), onDelete: .nullify)
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
            Check("Assignment.submittedAt", String(localized: .ruleAssignmentSubmittedAt)) { a, _ in
                a.submittedAt == nil || a.status == .submitted || a.status == .graded
            }
            Check("Assignment.lateRule", String(localized: .ruleLateRule)) { a, _ in a.lateRule?.isValid ?? true }
        }
        Items(\.components, noun: ItemKind.gradeComponent.noun, name: \.name) {
            NonEmpty(\.name, String(localized: .ruleGradeComponentNameEmpty))
            Check("GradeComponent.weight", String(localized: .ruleGradeComponentWeight)) { c, _ in (0...100).contains(c.weight) }
            Check("GradeComponent.count", String(localized: .ruleGradeComponentCount)) { c, _ in
                switch c.aggregation {
                case .dropLowest(let n), .bestOf(let n): n >= 1
                default: true
                }
            }
            Check("GradeComponent.expected", String(localized: .ruleGradeComponentExpected)) { c, _ in (c.expectedCount ?? 1) >= 1 }
            Check("GradeComponent.single", String(localized: .ruleGradeComponentSingle)) { c, f in
                c.aggregation != .single || f.scores.count(where: { $0.componentId == c.id }) <= 1
            }
        }
        Items(
            \.scores, noun: ItemKind.scoreEntry.noun,
            name: { s, f in
                s.title.isEmpty ? (f.components.first { $0.id == s.componentId }?.name ?? s.id.uuidString) : s.title
            }
        ) {
            Check("ScoreEntry.max", String(localized: .ruleScoreEntryMax)) { s, _ in s.max > 0 }
            Ref(\.componentId, to: GradeComponent.self, onDelete: .cascade)
            Ref(\.examId, to: Exam.self, onDelete: .nullify)
            Ref(\.assignmentId, to: Assignment.self, onDelete: .cascade)
            Check("ScoreEntry.source", String(localized: .ruleScoreEntrySource)) { s, _ in s.assignmentId == nil || s.examId == nil }
            Check("ScoreEntry.unique", String(localized: .ruleScoreEntryUnique)) { s, f in
                !f.hasScore(s.source, in: s.componentId, other: s.id)
            }
        }
        Items(
            \.attendance, noun: String(localized: .modelNounAttendance),
            name: { a, f in f.sessions.first { $0.id == a.sessionId }.map { f.title(of: $0, calendar: .current) } ?? a.id.uuidString }
        ) {
            Ref(\.sessionId, to: Session.self, onDelete: .restrict)
            Check("Attendance.cancelled", String(localized: .ruleAttendanceCancelled)) { a, f in
                f.sessions.first { $0.id == a.sessionId }?.isCancelled != true
            }
        }
        Items(\.problemSets, noun: ItemKind.problemSet.noun, name: \.title) {
            NonEmpty(\.title, String(localized: .ruleProblemSetTitleEmpty))
            Check("ProblemSet.problems", String(localized: .ruleProblemSetProblems)) { p, _ in !p.problems.isEmpty }
            Ref(\.materialId, to: Material.self, as: String(localized: .modelLabelProblemMaterial), onDelete: .nullify)
            Ref(\.solutionMaterialId, to: Material.self, as: String(localized: .modelLabelSolutionMaterial), onDelete: .nullify)
            Refs(\.problemUnitIds, to: Unit.self, onDelete: .nullify)
        }
        Items(\.recordings, noun: ItemKind.recording.noun, name: \.file) {
            Ref(\.sessionId, to: Session.self, onDelete: .nullify)
        }
        Items(\.notes, noun: ItemKind.note.noun, name: \.path) {
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
            Ref(\.examId, to: Exam.self, onDelete: .nullify)
            Check("NoteEntry.path", String(localized: .ruleNotePath)) { n, f in f.notes.count { $0.path == n.path } == 1 }
            Check("NoteEntry.units", String(localized: .ruleNoteUnits)) { n, _ in n.kind == .unit || n.unitIds.isEmpty }
        }
        Rule("NoteEntry.session") { f, _ in
            let pointers = f.sessions.compactMap(\.roughNoteId)
            let counts = Dictionary(pointers.map { ($0, 1) }, uniquingKeysWith: +)
            return f.notes.filter { (counts[$0.id] ?? 0) > 1 }.map { ($0.id, String(localized: .ruleNoteSession($0.path))) }
        }
        // 쌍마다 위반을 하나만 내고 늦은 수업에 붙인다. 범위를 더하는 저장은 그 쌍 하나로만 실패하고, 메시지가 두 수업을
        // 모두 말하므로 사용자가 어느 쪽을 고치고 있든 다른 쪽이 메시지에 있다.
        Rule("Session.progressOverlap") { f, _ in
            f.progressOverlaps().map { o in
                let file = f.materials.first { $0.id == o.material }.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? ""
                return (
                    o.later.session.id,
                    String(
                        localized: .ruleSessionProgressOverlap(
                            file, f.day(of: o.earlier.session, calendar: .current), Session.pagesLabel(o.earlier.pages),
                            f.day(of: o.later.session, calendar: .current), Session.pagesLabel(o.later.pages)))
                )
            }
        }
        Pair(\.sessions, \.materialIds, \.materials, \.sessionIds)
        Rule("GradePolicy.topGradeRatio", String(localized: .ruleGradePolicyTopGradeRatio)) { f, _ in
            f.policy.topGradeRatio.map { $0 > 0 && $0 < 1 } ?? true
        }
        Rule("GradePolicy.minAttendanceRatio", String(localized: .ruleGradePolicyMinAttendanceRatio)) { f, _ in
            f.policy.minAttendanceRatio.map { $0 > 0 && $0 <= 1 } ?? true
        }
        Rule("GradePolicy.latesPerAbsence", String(localized: .ruleGradePolicyLatesPerAbsence)) { f, _ in
            (f.policy.latesPerAbsence ?? 1) >= 1
        }
        Rule("GradePolicy.lateRule", String(localized: .ruleLateRule)) { f, _ in f.policy.lateRule?.isValid ?? true }
        Rule("GradePolicy.attendanceCap", String(localized: .ruleGradePolicyAttendanceCap)) { f, _ in
            f.policy.attendanceCap.allSatisfy { $0.absences >= 1 }
        }
        Rule("GradePolicy.grades") { f, w in
            guard let cat = w.catalog else { return [] }
            let ids = f.policy.attendanceCap.map(\.maxGrade) + f.policy.cutoffs.map(\.grade)
            return ids.filter { cat.grade($0)?.points == nil }.map { ($0, String(localized: .ruleGradePolicyGrades("\($0)"))) }
        }
    }
}

extension Transcript: Document {
    public static let model = Model<Transcript>(place: String(localized: .modelPlaceTranscript)) {
        Items(\.semesters, noun: ItemKind.semester.noun, name: { s, _ in s.name }) {
            Check("Semester.dates", String(localized: .ruleSemesterDates)) { s, _ in
                guard let a = s.start, let b = s.end else { return true }
                return a <= b
            }
            Check("Semester.examWeeks", String(localized: .ruleSemesterExamWeeks)) { s, _ in
                let last = s.weekCount ?? Int.max
                return [s.midtermWeek, s.finalWeek].compactMap { $0 }.allSatisfy { (1...last).contains($0) }
            }
            Check("Semester.creditedHours", String(localized: .ruleSemesterCreditedHours)) { s, _ in (s.creditedHours ?? 0) >= 0 }
            Check("Semester.source", String(localized: .ruleSemesterSource)) { s, _ in
                s.source.map { s.term == .credited && StandardLayout.isCreditedSourceName($0) } ?? true
            }
        }
        Items(\.unfiledCourses, noun: ItemKind.course.noun, name: \.title) { Course.members() }
        Rule("Transcript.creditedSources") { t, _ in
            let credited = t.semesters.filter { $0.term == .credited && $0.source != nil }
            return credited.filter { s in credited.contains { $0.id != s.id && $0.source == s.source } }
                .map { ($0.id, String(localized: .ruleTranscriptCreditedSources($0.source ?? ""))) }
        }
        Rule("Transcript.targetGPA", String(localized: .ruleTranscriptTargetGpa)) { t, w in
            t.targetGPA.map { $0 >= 0 && $0 <= (w.catalog?.maxPoints ?? Catalog.defaultMaxPoints) } ?? true
        }
        Rule("GraduationRule.range", String(localized: .ruleGraduationRuleRange)) { t, _ in
            t.graduation.totalCredits >= 0 && t.graduation.minGPA >= 0
        }
        Rule("GraduationRule.programs") { t, w in
            guard let cat = w.catalog else { return [] }
            return t.graduation.programs.filter { cat.code($0.codeId) == nil }
                .map { ($0.codeId, String(localized: .ruleGraduationRulePrograms("\($0.codeId)"))) }
        }
    }
}

extension Semester {
    public var name: String {
        let term =
            switch term {
            case .spring: String(localized: .semesterTermSpring)
            case .summer: String(localized: .semesterTermSummer)
            case .fall: String(localized: .semesterTermFall)
            case .winter: String(localized: .semesterTermWinter)
            case .credited: String(localized: .semesterTermCredited)
            }
        return "\(year) \(term)"
    }

    var weekCount: Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        func date(_ d: LocalDate?) -> Date? {
            d.flatMap { calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day)) }
        }
        guard let a = date(start), let b = date(end) else { return nil }
        return SessionPlanner.week(of: b, anchor: a, calendar: calendar)
    }
}

extension Catalog: Document {
    public static let model = Model<Catalog>(place: String(localized: .modelPlaceCatalog)) {
        Items(\.codes, noun: ItemKind.courseCode.noun, name: \.prefix) {
            NonEmpty(\.prefix, String(localized: .ruleCourseCodePrefixEmpty))
        }
        Items(\.categories, noun: ItemKind.category.noun, name: \.name) {
            NonEmpty(\.name, String(localized: .ruleCategoryNameEmpty))
            Ref(\.parentId, to: Category.self, as: String(localized: .modelLabelParentCategory), onDelete: .nullify)
        }
        Items(\.letterGrades, noun: ItemKind.letterGrade.noun, name: \.symbol) {
            NonEmpty(\.symbol, String(localized: .ruleLetterGradeSymbolEmpty))
        }
        Items(\.people, noun: ItemKind.person.noun, name: \.name) {
            NonEmpty(\.name, String(localized: .rulePersonNameEmpty))
        }
    }
}

extension Settings: Document {
    public static let model = Model<Settings>(place: String(localized: .modelPlaceSettings)) {
        Rule("Settings.dayBoundary", String(localized: .ruleSettingsDayBoundary)) { s, _ in
            SettingItem.dayBoundary.range.contains(s.dayBoundaryMinutes)
        }
        Rule("Settings.classMinutes", String(localized: .ruleSettingsClassMinutes)) { s, _ in (10...300).contains(s.classMinutes) }
        Rule("Settings.study", String(localized: .ruleSettingsStudy)) { s, _ in
            SettingItem.studyReadyPercent.range.contains(s.study.readyPercent)
                && SettingItem.studyMinProblems.range.contains(s.study.minProblems)
                && SettingItem.studyMockMinutes.range.contains(s.study.mockMinutes)
                && SettingItem.studyPlanShownDays.range.contains(s.study.planShownDays)
        }
        Rule("Settings.assignmentLeadHours", String(localized: .ruleSettingsAssignmentLeadHours)) { s, _ in
            (s.notifications[.assignmentDue].leadHours ?? []).allSatisfy { SettingItem.assignmentLeadHours.range.contains($0) }
        }
        Rule("Settings.assignmentKinds", String(localized: .ruleSettingsAssignmentKinds)) { s, _ in
            let prefixes = s.assignmentKindTable.map(\.prefix)
            return !prefixes.isEmpty && s.assignmentKindTable.allSatisfy(\.isValid) && Set(prefixes).count == prefixes.count
        }
    }
}

extension CardFile: Document {
    public static let model = Model<CardFile>(place: String(localized: .modelPlaceUnit)) {
        Items(\.cards, noun: ItemKind.studyCard.noun, name: \.front) {
            NonEmpty(\.front, String(localized: .ruleCardFrontEmpty))
            NonEmpty(\.back, String(localized: .ruleCardBackEmpty))
            Check("Card.unit", String(localized: .ruleCardUnit)) { c, f in c.unitId == f.unitId }
        }
    }
}
