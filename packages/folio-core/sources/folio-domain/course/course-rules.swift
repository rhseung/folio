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
            Ref(\.semesterId, to: Semester.self, onDelete: .restrict),
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

    var label: String { "\(week)주차-\(index)" }
}

extension CourseFile: Document {
    public static let model = Model<CourseFile>(place: String(localized: .modelPlaceCourse)) {
        One(\.course, noun: String(localized: .modelNounCourse), name: \.title) { Course.members() }
        Items(\.materials, noun: String(localized: .modelNounMaterial), name: \.path) {
            Refs(\.sessionIds, to: Session.self, onDelete: .nullify)
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
        }
        Items(\.units, noun: String(localized: .modelNounUnit), name: \.title) {
            NonEmpty(\.title, String(localized: .ruleUnitTitleEmpty))
            Ref(\.parentId, to: Unit.self, as: String(localized: .modelLabelParentUnit), onDelete: .reparent)
            Refs(\.sessionIds, to: Session.self, onDelete: .nullify)
            Refs(\.examIds, to: Exam.self, onDelete: .nullify)
        }
        Items(\.sessions, noun: String(localized: .modelNounSession), name: { s, _ in s.label }) {
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
            Refs(\.materialIds, to: Material.self, onDelete: .nullify)
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
            Check("ExamPlanItem.target", String(localized: .ruleExamPlanItemTarget)) { item, f in
                guard let t = item.target else { return true }
                return switch t.kind {
                case .unit, .quiz: f.units.contains { $0.id == t.id }
                case .problemSet: f.problemSets.contains { $0.id == t.id }
                }
            }
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
            Ref(\.assignmentId, to: Assignment.self, onDelete: .nullify)
        }
        Items(\.attendance, noun: String(localized: .modelNounAttendance), name: { a, f in f.sessions.first { $0.id == a.sessionId }?.label ?? a.id.uuidString }) {
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
            Check("ProblemSet.units", String(localized: .ruleProblemSetUnits)) { p, f in
                p.problems.allSatisfy { $0.unitIds.allSatisfy { u in f.units.contains { $0.id == u } } }
            }
        }
        Items(\.recordings, noun: String(localized: .modelNounRecording), name: \.file) {
            Ref(\.sessionId, to: Session.self, onDelete: .nullify)
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
        }
        Items(\.courses, noun: String(localized: .modelNounCourse), name: \.title) { Course.members() }
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
