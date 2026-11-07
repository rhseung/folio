import Foundation

// Rules every saved file keeps, whichever action wrote it. Checked on the whole file rather than in each action,
// since the app hides what breaks them but `folio run` takes whole entities and can reach any field.

extension Course {
    /// Checks a course record keeps wherever it is stored: in its course file, or in the transcript when it has no folder.
    static func members<Doc: Sendable>() -> [Member<Doc, Course>] {
        [
            NonEmpty(\.title, String(localized: .courseTitleEmpty)),
            Check("Course.credits", String(localized: .ruleCourseCredits)) { c, _ in c.credits >= 0 },
            Check("Course.schedule", String(localized: .ruleCourseSchedule)) { c, _ in
                c.schedule.allSatisfy { (1...7).contains($0.weekday) && $0.startMinute >= 0 && $0.endMinute <= 24 * 60 && $0.endMinute > $0.startMinute }
            },
            Check("Course.scheduleLink", String(localized: .ruleCourseScheduleLink)) { c, _ in
                c.schedule.allSatisfy { $0.link.map { OnlineLink.url($0) != nil } ?? true }
            },
            Ref(\.semesterId, to: Semester.self, onDelete: .restrict),
            // Passes in the transcript, which has no materials: a course there has no folder.
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
    /// The session's materials as ids, so the model can treat them like any other list of pointers.
    var materialIds: [UUID] {
        get { materials.map(\.materialId) }
        set { materials = materials.filter { newValue.contains($0.materialId) } }
    }
}

extension ExamPlanItem {
    // A target is one pointer whose kind says what it points at, so the model sees it as two optional pointers.
    // Clearing one keeps the item as a plain dated to-do.
    var unitTarget: UUID? {
        get { target.flatMap { $0.kind == .problemSet ? nil : $0.id } }
        set { pointTarget(unitTarget, to: newValue) }
    }

    var problemSetTarget: UUID? {
        get { target.flatMap { $0.kind == .problemSet ? $0.id : nil } }
        set { pointTarget(problemSetTarget, to: newValue) }
    }

    private mutating func pointTarget(_ old: UUID?, to new: UUID?) {
        guard old != nil else { return }
        if let new { target?.id = new } else { target = nil }
    }
}

extension ProblemSet {
    /// Every problem's units as one list. Problems have no ids of their own, so the model reaches them through the set;
    /// setting it keeps on each problem only the units still listed.
    var problemUnitIds: [UUID] {
        get { problems.flatMap(\.unitIds) }
        set { for i in problems.indices { problems[i].unitIds = problems[i].unitIds.filter(newValue.contains) } }
    }
}

extension CourseFile: Document {
    public static let model = Model<CourseFile>(place: String(localized: .modelPlaceCourse)) {
        One(\.course, noun: String(localized: .modelNounCourse), name: \.title) { Course.members() }
        Items(\.materials, noun: String(localized: .modelNounMaterial), name: \.path) {
            Ref(\.sourceOf, to: Material.self, onDelete: .nullify)
            Ref(\.solutionOf, to: Material.self, onDelete: .nullify)
            Refs(\.sessionIds, to: Session.self, onDelete: .nullify)
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
            Refs(\.examIds, to: Exam.self, onDelete: .nullify)
        }
        Items(\.units, noun: String(localized: .modelNounUnit), name: \.title) {
            NonEmpty(\.title, String(localized: .ruleUnitTitleEmpty))
            Ref(\.parentId, to: Unit.self, as: String(localized: .modelLabelParentUnit), onDelete: .reparent)
            Refs(\.sessionIds, to: Session.self, onDelete: .nullify)
            Refs(\.examIds, to: Exam.self, onDelete: .nullify)
            Refs(\.lectureMaterialIds, to: Material.self, onDelete: .nullify)
            Check("Unit.pages", String(localized: .ruleUnitPages)) { u, _ in
                u.lecturePages.allSatisfy { $0.firstPage >= 1 && $0.firstPage <= $0.lastPage }
            }
        }
        Items(\.sessions, noun: String(localized: .modelNounSession), name: { s, f in f.title(of: s, calendar: .current) }) {
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
            Refs(\.materialIds, to: Material.self, onDelete: .nullify)
            // The session is the only side that holds the link, so the note it names must be of that slot's kind.
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
        Items(\.exams, noun: String(localized: .modelNounExam), name: \.title) {
            NonEmpty(\.title, String(localized: .ruleExamTitleEmpty))
            Check("Exam.time", String(localized: .ruleExamTime)) { e, _ in
                switch (e.start, e.end) {
                case (nil, .some): false
                case (let s?, let t?): t > s
                default: true
                }
            }
            Ref(\.componentId, to: GradeComponent.self, onDelete: .nullify)
            Refs(\.scopeUnitIds, to: Unit.self, as: String(localized: .modelLabelScopeUnit), onDelete: .nullify)
        }
        Items(\.exams, \.plan, noun: String(localized: .modelNounExamPlanItem), name: \.title) {
            NonEmpty(\.title, String(localized: .ruleExamPlanItemTitleEmpty))
            Ref(\.unitTarget, to: Unit.self, onDelete: .nullify)
            Ref(\.problemSetTarget, to: ProblemSet.self, onDelete: .nullify)
        }
        Items(\.assignments, noun: String(localized: .modelNounAssignment), name: \.title) {
            NonEmpty(\.title, String(localized: .ruleAssignmentTitleEmpty))
            Ref(\.componentId, to: GradeComponent.self, onDelete: .nullify)
            Check("Assignment.componentGroup", String(localized: .ruleAssignmentComponentGroup)) { a, f in
                a.componentGroup.map { g in f.components.contains { $0.group == g } } ?? true
            }
            Ref(\.problemMaterialId, to: Material.self, as: String(localized: .modelLabelProblemMaterial), onDelete: .nullify)
            Refs(\.submissionMaterialIds, to: Material.self, as: String(localized: .modelLabelSubmissionMaterial), onDelete: .nullify)
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
        }
        Items(\.components, noun: String(localized: .modelNounGradeComponent), name: \.name) {
            NonEmpty(\.name, String(localized: .ruleGradeComponentNameEmpty))
            Check("GradeComponent.weight", String(localized: .ruleGradeComponentWeight)) { c, _ in c.weight >= 0 }
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
        Items(\.scores, noun: String(localized: .modelNounScoreEntry), name: { s, f in
            s.title.isEmpty ? (f.components.first { $0.id == s.componentId }?.name ?? s.id.uuidString) : s.title
        }) {
            Check("ScoreEntry.max", String(localized: .ruleScoreEntryMax)) { s, _ in s.max > 0 }
            Ref(\.componentId, to: GradeComponent.self, onDelete: .cascade)
            Ref(\.examId, to: Exam.self, onDelete: .nullify)
            Ref(\.assignmentId, to: Assignment.self, onDelete: .cascade)
            Check("ScoreEntry.source", String(localized: .ruleScoreEntrySource)) { s, _ in s.assignmentId == nil || s.examId == nil }
            Check("ScoreEntry.unique", String(localized: .ruleScoreEntryUnique)) { s, f in !f.hasScore(s.source, in: s.componentId, other: s.id) }
        }
        Items(\.attendance, noun: String(localized: .modelNounAttendance), name: { a, f in f.sessions.first { $0.id == a.sessionId }.map { f.title(of: $0, calendar: .current) } ?? a.id.uuidString }) {
            Ref(\.sessionId, to: Session.self, onDelete: .restrict)
            Check("Attendance.cancelled", String(localized: .ruleAttendanceCancelled)) { a, f in
                f.sessions.first { $0.id == a.sessionId }?.isCancelled != true
            }
        }
        Items(\.problemSets, noun: String(localized: .modelNounProblemSet), name: \.title) {
            NonEmpty(\.title, String(localized: .ruleProblemSetTitleEmpty))
            Check("ProblemSet.problems", String(localized: .ruleProblemSetProblems)) { p, _ in !p.problems.isEmpty }
            Ref(\.materialId, to: Material.self, as: String(localized: .modelLabelProblemMaterial), onDelete: .nullify)
            Ref(\.solutionMaterialId, to: Material.self, as: String(localized: .modelLabelSolutionMaterial), onDelete: .nullify)
            Refs(\.problemUnitIds, to: Unit.self, onDelete: .nullify)
        }
        Items(\.recordings, noun: String(localized: .modelNounRecording), name: \.file) {
            Ref(\.sessionId, to: Session.self, onDelete: .nullify)
        }
        Items(\.notes, noun: String(localized: .modelNounNote), name: \.path) {
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
            Ref(\.examId, to: Exam.self, onDelete: .nullify)
            // Notes are found by their file, so two entries on one file would give it two sets of properties.
            Check("NoteEntry.path", String(localized: .ruleNotePath)) { n, f in f.notes.count { $0.path == n.path } == 1 }
            // Other kinds read their units from their session or exam; a stored copy would go stale and resurface.
            Check("NoteEntry.units", String(localized: .ruleNoteUnits)) { n, _ in n.kind == .unit || n.unitIds.isEmpty }
        }
        // A rough note is taken during one class, so a second session pointing at it would give it two. A review note
        // may cover several classes reviewed at once; `Session.noteKind` keeps one note from filling both slots.
        Rule("NoteEntry.session") { f, _ in
            let pointers = f.sessions.compactMap(\.roughNoteId)
            let counts = Dictionary(pointers.map { ($0, 1) }, uniquingKeysWith: +)
            return f.notes.filter { (counts[$0.id] ?? 0) > 1 }.map { ($0.id, String(localized: .ruleNoteSession($0.path))) }
        }
        Pair(\.exams, \.scopeUnitIds, \.units, \.examIds)
        Pair(\.sessions, \.unitIds, \.units, \.sessionIds)
        Pair(\.sessions, \.materialIds, \.materials, \.sessionIds)
        Rule("GradePolicy.topGradeRatio", String(localized: .ruleGradePolicyTopGradeRatio)) { f, _ in
            f.policy.topGradeRatio.map { $0 > 0 && $0 < 1 } ?? true
        }
        Rule("GradePolicy.minAttendanceRatio", String(localized: .ruleGradePolicyMinAttendanceRatio)) { f, _ in
            f.policy.minAttendanceRatio.map { $0 > 0 && $0 <= 1 } ?? true
        }
        Rule("GradePolicy.latesPerAbsence", String(localized: .ruleGradePolicyLatesPerAbsence)) { f, _ in (f.policy.latesPerAbsence ?? 1) >= 1 }
        Rule("GradePolicy.attendanceCap", String(localized: .ruleGradePolicyAttendanceCap)) { f, _ in f.policy.attendanceCap.allSatisfy { $0.absences >= 1 } }
        Rule("GradePolicy.grades") { f, w in
            guard let cat = w.catalog else { return [] }
            let ids = f.policy.attendanceCap.map(\.maxGrade) + f.policy.cutoffs.map(\.grade)
            return ids.filter { cat.grade($0)?.points == nil }.map { ($0, String(localized: .ruleGradePolicyGrades("\($0)"))) }
        }
    }
}

extension Transcript: Document {
    public static let model = Model<Transcript>(place: String(localized: .modelPlaceTranscript)) {
        Items(\.semesters, noun: String(localized: .modelNounSemester), name: { s, _ in s.name }) {
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
        Items(\.unfiledCourses, noun: String(localized: .modelNounCourse), name: \.title) { Course.members() }
        // Two credited terms with one source would share `_Credited/<source>`, and neither would own its courses.
        Rule("Transcript.creditedSources") { t, _ in
            let credited = t.semesters.filter { $0.term == .credited && $0.source != nil }
            return credited.filter { s in credited.contains { $0.id != s.id && $0.source == s.source } }
                .map { ($0.id, String(localized: .ruleTranscriptCreditedSources($0.source ?? ""))) }
        }
        Rule("Transcript.targetGPA", String(localized: .ruleTranscriptTargetGpa)) { t, w in
            t.targetGPA.map { $0 >= 0 && $0 <= (w.catalog?.maxPoints ?? 4.5) } ?? true
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
        let term = switch term {
        case .spring: String(localized: .semesterTermSpring)
        case .summer: String(localized: .semesterTermSummer)
        case .fall: String(localized: .semesterTermFall)
        case .winter: String(localized: .semesterTermWinter)
        case .credited: String(localized: .semesterTermCredited)
        }
        return "\(year) \(term)"
    }

    /// Monday-based weeks from the start to the end, as the semester screen counts them.
    var weekCount: Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        func date(_ d: LocalDate?) -> Date? { d.flatMap { calendar.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day)) } }
        guard let a = date(start), let b = date(end) else { return nil }
        return SessionPlanner.week(of: b, anchor: a, calendar: calendar)
    }
}

extension Catalog: Document {
    public static let model = Model<Catalog>(place: String(localized: .modelPlaceCatalog)) {
        Items(\.codes, noun: String(localized: .modelNounCourseCode), name: \.prefix) { NonEmpty(\.prefix, String(localized: .ruleCourseCodePrefixEmpty)) }
        Items(\.categories, noun: String(localized: .modelNounCategory), name: \.name) {
            NonEmpty(\.name, String(localized: .ruleCategoryNameEmpty))
            Ref(\.parentId, to: Category.self, as: String(localized: .modelLabelParentCategory), onDelete: .nullify)
        }
        Items(\.letterGrades, noun: String(localized: .modelNounLetterGrade), name: \.symbol) { NonEmpty(\.symbol, String(localized: .ruleLetterGradeSymbolEmpty)) }
        Items(\.people, noun: String(localized: .modelNounPerson), name: \.name) { NonEmpty(\.name, String(localized: .rulePersonNameEmpty)) }
    }
}

extension Settings: Document {
    public static let model = Model<Settings>(place: String(localized: .modelPlaceSettings)) {
        Rule("Settings.dayBoundary", String(localized: .ruleSettingsDayBoundary)) { s, _ in (0...(8 * 60)).contains(s.dayBoundaryMinutes) }
        Rule("Settings.classMinutes", String(localized: .ruleSettingsClassMinutes)) { s, _ in (10...300).contains(s.classMinutes) }
        Rule("Settings.dailyLimit", String(localized: .ruleSettingsDailyLimit)) { s, _ in s.review.dailyLimit.map { (1...50).contains($0) } ?? true }
        Rule("Settings.intervals", String(localized: .ruleSettingsIntervals)) { s, _ in
            !s.review.intervals.isEmpty && s.review.intervals.allSatisfy { (1...365).contains($0) }
        }
        Rule("Settings.assignmentLeadHours", String(localized: .ruleSettingsAssignmentLeadHours)) { s, _ in
            s.notifications.assignmentLeadHours.allSatisfy { (1...336).contains($0) }
        }
    }
}

extension QuizFile: Document {
    public static let model = Model<QuizFile>(place: String(localized: .modelPlaceUnit)) {
        Items(\.cards, noun: String(localized: .modelNounQuizCard), name: \.prompt) {
            NonEmpty(\.prompt, String(localized: .ruleQuizCardPromptEmpty))
            Check("QuizCard.answer", String(localized: .ruleQuizCardAnswer)) { c, _ in
                guard !c.answer.isEmpty else { return false }
                return switch c.type {
                case .choice: c.options.contains(c.answer)
                case .trueFalse: QuizCard.trueFalseOptions.contains(c.answer)
                default: true
                }
            }
            Check("QuizCard.unit", String(localized: .ruleQuizCardUnit)) { c, f in c.unitId == f.unitId }
        }
    }
}
