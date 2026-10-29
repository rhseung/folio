import Foundation

// Rules every saved file keeps, whichever action wrote it. Checked on the whole file rather than in each action,
// since the app hides what breaks them but `folio run` takes whole entities and can reach any field.

extension Course {
    /// Checks a course record keeps wherever it is stored: in its course file, or in the transcript when it has no folder.
    static func members<Doc: Sendable>() -> [Member<Doc, Course>] {
        [
            NonEmpty(\.title, "과목 이름이 비었습니다"),
            Check("Course.credits", "과목 '{name}'의 학점이 음수입니다") { c, _ in c.credits >= 0 },
            Check("Course.schedule", "과목 '{name}'의 수업 시간이 잘못되었습니다: 요일은 월~일, 끝은 시작보다 늦어야 합니다") { c, _ in
                c.schedule.allSatisfy { (1...7).contains($0.weekday) && $0.startMinute >= 0 && $0.endMinute <= 24 * 60 && $0.endMinute > $0.startMinute }
            },
            Ref(\.semesterId, to: Semester.self, onDelete: .restrict),
            Check("Course.semester", "과목 '{name}'의 학기가 transcript.json에 없습니다") { c, _, w in
                guard let t = w.transcript, let s = c.semesterId else { return true }
                return t.semesters.contains { $0.id == s }
            },
            Check("Course.codes", "과목 '{name}'의 강의 코드가 catalog.json에 없습니다") { c, _, w in
                w.catalog.map { cat in c.codes.allSatisfy { cat.code($0) != nil } } ?? true
            },
            Check("Course.categories", "과목 '{name}'의 강의 분류가 catalog.json에 없습니다") { c, _, w in
                w.catalog.map { cat in c.categoryIds.allSatisfy { cat.category($0) != nil } } ?? true
            },
            Check("Course.instructors", "과목 '{name}'의 교수가 catalog.json에 없습니다") { c, _, w in
                w.catalog.map { cat in c.instructorIds.allSatisfy { id in cat.people.contains { $0.id == id } } } ?? true
            },
            Check("Course.finalGrade", "과목 '{name}'의 성적이 이 평가 방식의 평어가 아닙니다") { c, _, w in
                guard let cat = w.catalog, let g = c.finalGrade else { return true }
                return cat.grades(for: c.gradingMode).contains { $0.id == g }
            },
            Check("Course.targetGrade", "과목 '{name}'의 목표 성적이 이 평가 방식의 평어가 아닙니다") { c, _, w in
                guard let cat = w.catalog, let g = c.targetGrade else { return true }
                return cat.grades(for: c.gradingMode).contains { $0.id == g }
            },
            Check("Course.sharing", "과목 '{name}'의 강의 분류 중 학점을 함께 셀 수 없는 것이 있습니다") { c, _, w in
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
    public static let model = Model<CourseFile>(place: "이 과목에") {
        One(\.course, noun: "과목", name: \.title) { Course.members() }
        Items(\.materials, noun: "자료", name: \.path) {
            Refs(\.sessionIds, to: Session.self, onDelete: .nullify)
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
        }
        Items(\.units, noun: "단원", name: \.title) {
            NonEmpty(\.title, "단원 제목이 비었습니다")
            Ref(\.parentId, to: Unit.self, as: "상위 단원", onDelete: .reparent)
            Refs(\.sessionIds, to: Session.self, onDelete: .nullify)
            Refs(\.examIds, to: Exam.self, onDelete: .nullify)
        }
        Items(\.sessions, noun: "회차", name: { s, _ in s.label }) {
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
            Refs(\.materialIds, to: Material.self, onDelete: .nullify)
            Check("Session.pages", "회차 '{name}'의 자료 쪽수가 잘못되었습니다: 1쪽부터이고 끝 쪽이 시작 쪽보다 앞설 수 없습니다") { s, _ in
                s.materials.allSatisfy { m in
                    (m.firstPage ?? 1) >= 1 && (m.lastPage ?? 1) >= 1 && (m.firstPage ?? 1) <= (m.lastPage ?? Int.max)
                }
            }
        }
        Items(\.exams, noun: "시험", name: \.title) {
            NonEmpty(\.title, "시험 제목이 비었습니다")
            Check("Exam.time", "시험 '{name}'의 끝 시각은 시작보다 늦어야 하고, 시작 없이 끝만 둘 수 없습니다") { e, _ in
                switch (e.start, e.end) {
                case (nil, .some): false
                case (let s?, let t?): t > s
                default: true
                }
            }
            Ref(\.componentId, to: GradeComponent.self, onDelete: .nullify)
            Refs(\.scopeUnitIds, to: Unit.self, as: "범위 단원", onDelete: .nullify)
        }
        Items(\.exams, \.plan, noun: "공부 계획 항목", name: \.title) {
            NonEmpty(\.title, "공부 계획 항목 제목이 비었습니다")
            Check("ExamPlanItem.target", "공부 계획 항목 '{name}'이 가리키는 대상이 이 과목에 없습니다") { item, f in
                guard let t = item.target else { return true }
                return switch t.kind {
                case .unit, .quiz: f.units.contains { $0.id == t.id }
                case .problemSet: f.problemSets.contains { $0.id == t.id }
                }
            }
        }
        Items(\.assignments, noun: "과제", name: \.title) {
            NonEmpty(\.title, "과제 제목이 비었습니다")
            Ref(\.componentId, to: GradeComponent.self, onDelete: .nullify)
            Check("Assignment.componentGroup", "과제 '{name}'의 성적 묶음이 이 과목에 없습니다") { a, f in
                a.componentGroup.map { g in f.components.contains { $0.group == g } } ?? true
            }
            Ref(\.problemMaterialId, to: Material.self, as: "문제 자료", onDelete: .nullify)
            Refs(\.submissionMaterialIds, to: Material.self, as: "제출 자료", onDelete: .nullify)
            Refs(\.unitIds, to: Unit.self, onDelete: .nullify)
        }
        Items(\.components, noun: "성적 항목", name: \.name) {
            NonEmpty(\.name, "성적 항목 이름이 비었습니다")
            Check("GradeComponent.weight", "성적 항목 '{name}'의 비중이 음수입니다") { c, _ in c.weight >= 0 }
            Check("GradeComponent.count", "성적 항목 '{name}'의 집계 개수는 1 이상이어야 합니다") { c, _ in
                switch c.aggregation {
                case .dropLowest(let n), .bestOf(let n): n >= 1
                default: true
                }
            }
            Check("GradeComponent.expected", "성적 항목 '{name}'의 예정 개수는 1 이상이어야 합니다") { c, _ in (c.expectedCount ?? 1) >= 1 }
            Check("GradeComponent.single", "단일 성적 항목 '{name}'에는 점수를 하나만 둘 수 있습니다") { c, f in
                c.aggregation != .single || f.scores.count(where: { $0.componentId == c.id }) <= 1
            }
        }
        Items(\.scores, noun: "점수", name: { s, f in
            s.title.isEmpty ? (f.components.first { $0.id == s.componentId }?.name ?? s.id.uuidString) : s.title
        }) {
            Check("ScoreEntry.max", "점수 '{name}'의 만점은 0보다 커야 합니다") { s, _ in s.max > 0 }
            Ref(\.componentId, to: GradeComponent.self, onDelete: .cascade)
            Ref(\.examId, to: Exam.self, onDelete: .nullify)
            Ref(\.assignmentId, to: Assignment.self, onDelete: .nullify)
        }
        Items(\.attendance, noun: "출결", name: { a, f in f.sessions.first { $0.id == a.sessionId }?.label ?? a.id.uuidString }) {
            Ref(\.sessionId, to: Session.self, onDelete: .restrict)
            Check("Attendance.cancelled", "휴강한 회차 '{name}'에는 출결을 둘 수 없습니다") { a, f in
                f.sessions.first { $0.id == a.sessionId }?.isCancelled != true
            }
        }
        Items(\.problemSets, noun: "문제 묶음", name: \.title) {
            NonEmpty(\.title, "문제 묶음 제목이 비었습니다")
            Check("ProblemSet.problems", "문제 묶음 '{name}'에 문제가 없습니다") { p, _ in !p.problems.isEmpty }
            Ref(\.materialId, to: Material.self, as: "문제 자료", onDelete: .nullify)
            Ref(\.solutionMaterialId, to: Material.self, as: "풀이 자료", onDelete: .nullify)
            Check("ProblemSet.units", "문제 묶음 '{name}'의 문제가 가리키는 단원이 이 과목에 없습니다") { p, f in
                p.problems.allSatisfy { $0.unitIds.allSatisfy { u in f.units.contains { $0.id == u } } }
            }
        }
        Items(\.recordings, noun: "녹음", name: \.file) {
            Ref(\.sessionId, to: Session.self, onDelete: .nullify)
        }
        Pair(\.exams, \.scopeUnitIds, \.units, \.examIds)
        Pair(\.sessions, \.unitIds, \.units, \.sessionIds)
        Pair(\.sessions, \.materialIds, \.materials, \.sessionIds)
        Rule("GradePolicy.topGradeRatio", "A 비율은 0%보다 크고 100%보다 작아야 합니다") { f, _ in
            f.policy.topGradeRatio.map { $0 > 0 && $0 < 1 } ?? true
        }
        Rule("GradePolicy.minAttendanceRatio", "최소 출석 비율은 0%보다 크고 100% 이하여야 합니다") { f, _ in
            f.policy.minAttendanceRatio.map { $0 > 0 && $0 <= 1 } ?? true
        }
        Rule("GradePolicy.latesPerAbsence", "결석 1회로 치는 지각 횟수는 1 이상이어야 합니다") { f, _ in (f.policy.latesPerAbsence ?? 1) >= 1 }
        Rule("GradePolicy.attendanceCap", "결석 상한의 결석 횟수는 1 이상이어야 합니다") { f, _ in f.policy.attendanceCap.allSatisfy { $0.absences >= 1 } }
        Rule("GradePolicy.grades") { f, w in
            guard let cat = w.catalog else { return [] }
            let ids = f.policy.attendanceCap.map(\.maxGrade) + f.policy.cutoffs.map(\.grade)
            return ids.filter { cat.grade($0)?.points == nil }.map { ($0, "성적 규칙이 점수 있는 평어가 아닌 것을 가리킵니다: \($0)") }
        }
    }
}

extension Transcript: Document {
    public static let model = Model<Transcript>(place: "transcript.json에") {
        Items(\.semesters, noun: "학기", name: { s, _ in s.name }) {
            Check("Semester.dates", "학기 '{name}'의 끝나는 날이 시작하는 날보다 앞섭니다") { s, _ in
                guard let a = s.start, let b = s.end else { return true }
                return a <= b
            }
            Check("Semester.examWeeks", "학기 '{name}'의 시험 주차가 학기 밖에 있습니다") { s, _ in
                let last = s.weekCount ?? Int.max
                return [s.midtermWeek, s.finalWeek].compactMap { $0 }.allSatisfy { (1...last).contains($0) }
            }
            Check("Semester.creditedHours", "학기 '{name}'의 인정 학점이 음수입니다") { s, _ in (s.creditedHours ?? 0) >= 0 }
        }
        Items(\.courses, noun: "과목", name: \.title) { Course.members() }
        Rule("Transcript.targetGPA", "목표 평점이 평점 범위 밖입니다") { t, w in
            t.targetGPA.map { $0 >= 0 && $0 <= (w.catalog?.maxPoints ?? 4.5) } ?? true
        }
        Rule("GraduationRule.range", "졸업 학점과 최소 평점은 음수일 수 없습니다") { t, _ in
            t.graduation.totalCredits >= 0 && t.graduation.minGPA >= 0
        }
        Rule("GraduationRule.programs") { t, w in
            guard let cat = w.catalog else { return [] }
            return t.graduation.programs.filter { cat.code($0.codeId) == nil }
                .map { ($0.codeId, "졸업 요건의 과정이 catalog.json에 없는 강의 코드를 가리킵니다: \($0.codeId)") }
        }
    }
}

extension Semester {
    public var name: String {
        let term = switch term {
        case .spring: "봄"
        case .summer: "여름"
        case .fall: "가을"
        case .winter: "겨울"
        case .credited: "인정"
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
    public static let model = Model<Catalog>(place: "catalog.json에") {
        Items(\.codes, noun: "강의 코드", name: \.prefix) { NonEmpty(\.prefix, "강의 코드가 비었습니다") }
        Items(\.categories, noun: "강의 분류", name: \.name) {
            NonEmpty(\.name, "강의 분류 이름이 비었습니다")
            Ref(\.parentId, to: Category.self, as: "상위 분류", onDelete: .nullify)
        }
        Items(\.letterGrades, noun: "평어", name: \.symbol) { NonEmpty(\.symbol, "평어가 비었습니다") }
        Items(\.people, noun: "교수", name: \.name) { NonEmpty(\.name, "교수 이름이 비었습니다") }
    }
}

extension Settings: Document {
    public static let model = Model<Settings>(place: "settings.json에") {
        Rule("Settings.dayBoundary", "하루 경계는 0시부터 8시 사이여야 합니다") { s, _ in (0...(8 * 60)).contains(s.dayBoundaryMinutes) }
        Rule("Settings.dailyLimit", "하루 복습 개수는 1에서 50 사이여야 합니다") { s, _ in s.review.dailyLimit.map { (1...50).contains($0) } ?? true }
        Rule("Settings.intervals", "복습 간격은 1일에서 365일 사이여야 합니다") { s, _ in
            !s.review.intervals.isEmpty && s.review.intervals.allSatisfy { (1...365).contains($0) }
        }
        Rule("Settings.assignmentLeadHours", "과제 알림은 마감 1시간 전에서 336시간 전 사이여야 합니다") { s, _ in
            s.notifications.assignmentLeadHours.allSatisfy { (1...336).contains($0) }
        }
    }
}

extension QuizFile: Document {
    public static let model = Model<QuizFile>(place: "이 단원에") {
        Items(\.cards, noun: "퀴즈 카드", name: \.prompt) {
            NonEmpty(\.prompt, "퀴즈 카드의 문제가 비었습니다")
            Check("QuizCard.answer", "퀴즈 카드 '{name}'의 정답이 비었거나 보기에 없습니다") { c, _ in
                guard !c.answer.isEmpty else { return false }
                return switch c.type {
                case .choice: c.options.contains(c.answer)
                case .trueFalse: QuizCard.trueFalseOptions.contains(c.answer)
                default: true
                }
            }
            Check("QuizCard.unit", "퀴즈 카드 '{name}'의 단원이 이 파일의 단원이 아닙니다") { c, f in c.unitId == f.unitId }
        }
    }
}
