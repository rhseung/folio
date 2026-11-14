import FolioAI
import FolioDomain
import SwiftUI

struct CourseOverview: View {
    @Environment(\.accent) private var accent
    @Bindable var model: CourseModel
    let course: LoadedCourse
    @State private var editing = false
    @State private var wide = true

    var body: some View {
        let file = course.file
        let now = model.workspace.now
        let score = model.score(file)
        let reviews = model.reviews(now: now)
        let suggested = model.suggested(course, now: now)
        let unclassified = model.unclassified(file)
        let layout =
            wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Space.xl))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.xl))

        Page {
            PageHeader(title: course.title, subtitle: model.subtitle(file)) {
                let code = course.codeLine(model.workspace)
                if !code.isEmpty { Chip(code, tone: .accent) }
                Chip(model.credits(file.course))
                Chip(file.course.gradingMode.label)
                Spacer()
                Button(.courseEdit, systemImage: "slider.horizontal.3") { editing = true }.buttonStyle(.ghost)
                PageMenuButton { CourseMenu(courseId: course.id, host: .own) }
            }
            .sheet(isPresented: $editing) { EditCourseSheet(workspace: model.workspace, course: course) }
            #if DEBUG && os(macOS)
            .onChange(of: SnapshotDriver.shared.editCourse, initial: true) { _, on in editing = on }
            #endif

            StatStrip(items: model.stats(file, reviews: reviews, suggested: suggested, now: now))

            if !unclassified.isEmpty {
                NoticeCard(
                    title: String(localized: .courseUnclassifiedNotice(unclassified.count)),
                    detail: String(localized: .courseUnclassifiedDetail),
                    systemImage: "tray.fill"
                ) {
                    Button(.courseReviewMaterials) { model.section = .materials }.buttonStyle(.ghost)
                }
            }

            layout {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    weekBlock(file, suggested: suggested, now: now)
                    assignmentsBlock(file, now: now)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    unitsBlock(file, reviews: reviews)
                    gradesBlock(file, score: score)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .onGeometryChange(for: Bool.self) {
                $0.size.width >= 620
            } action: {
                wide = $0
            }

            InfoBlocks(workspace: model.workspace, course: course)
        }
        .confirming($model.pending)
    }

    func weekBlock(_ file: CourseFile, suggested: Workspace.SuggestedSession?, now: Date) -> some View {
        let sessions = model.weekSessions(file, now: now)
        let next = model.weekSuggestion(suggested, now: now)
        return Block(String(localized: .courseThisWeek)) {
            if !sessions.isEmpty || next == nil {
                Card {
                    if sessions.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .courseNoClassThisWeek)) } }
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        CardRow(last: i == sessions.count - 1) {
                            VStack(spacing: 0) {
                                Text(s.date.formatted(.dateTime.weekday(.abbreviated))).font(Theme.Typeface.label.weight(.regular))
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                // 숫자만 쓴다. 한국어 날짜 형식은 `일`을 붙여 34pt 열을 넘었다.
                                Text(verbatim: "\(model.day(of: s.date))").font(Theme.Typeface.figureMedium).foregroundStyle(
                                    s.date > now ? accent.ink : Theme.Palette.text)
                            }
                            .frame(width: 34)
                            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                HStack(spacing: Theme.Space.s) {
                                    Text(model.recentTitle(s, in: file)).font(Theme.Typeface.bodyStrong).lineLimit(1)
                                        .strikethrough(s.isCancelled)
                                    if s.kind == .makeup { SessionKindChip(kind: s.kind) }
                                }
                                Text(model.weekStatus(s, in: file, now: now)).lineLimit(1)
                                    .font(Theme.Typeface.caption)
                                    .foregroundStyle(file.needsReviewNote(s, at: now) ? Theme.Palette.danger : Theme.Palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contextMenu { SessionMenu(courseId: course.id, sessionId: s.id, openNote: model.show(note:)) }
                    }
                }
                .opens { model.section = .sessions }
            }
            if let next { SuggestedSessionRow(item: next, openNote: model.show(note:)) }
        }
    }

    func assignmentsBlock(_ file: CourseFile, now: Date) -> some View {
        let open = model.openAssignments(file)
        let shown = Array(open.prefix(5))
        return Block(String(localized: .courseSectionAssignments), note: model.assignmentsNote(file)) {
            Card {
                if shown.isEmpty {
                    CardRow(last: true) {
                        EmptyLine(String(localized: file.assignments.isEmpty ? .courseNoAssignments : .courseNoOpenAssignments))
                    }
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, a in
                    CardRow(last: i == shown.count - 1 && open.count == shown.count) {
                        AssignmentStatusIcon(status: a.status)
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(a.title).font(Theme.Typeface.bodyStrong).lineLimit(1)
                            Text(a.due?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? String(localized: .courseNoDue))
                                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit().lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.s)
                        if let due = a.due {
                            if due < now {
                                Chip(String(localized: .courseOverdue), tone: .danger)
                            } else {
                                DdayChip(days: model.days(to: due))
                            }
                        }
                    }
                    .contextMenu { AssignmentMenu(courseId: course.id, assignmentId: a.id) }
                }
                if open.count > shown.count {
                    CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(open.count - shown.count))) }
                }
            }
            .opens { model.section = .assignments }
        }
    }

    func unitsBlock(_ file: CourseFile, reviews: [Workspace.ReviewEntry]) -> some View {
        let shown = model.glanceUnits(file, reviews: reviews)
        return Block(
            String(localized: .courseSectionUnits),
            note: file.units.count > shown.count ? String(localized: .courseUnitsNote(file.units.count, shown.count)) : nil
        ) {
            Card {
                if shown.isEmpty {
                    CardRow(last: true) { EmptyLine(String(localized: file.units.isEmpty ? .courseNoUnits : .courseNoCoveredUnits)) }
                }
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, unit in
                    let entry = reviews.first { $0.item.unitId == unit.id }
                    ReviewOpener(courseId: course.id, unitId: unit.id) {
                        CardRow(last: i == shown.count - 1) {
                            Text(unit.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.s)
                            if let entry {
                                Chip(
                                    String(
                                        localized: entry.item.overdueDays > 0 ? .unitsDaysLate(entry.item.overdueDays) : .courseReviewToday),
                                    tone: entry.item.overdueDays > 0 ? .danger : .accent)
                            } else {
                                Text(.sessionsCount(unit.sessionIds.count)).font(Theme.Typeface.caption).foregroundStyle(
                                    Theme.Palette.textTertiary
                                ).fixedSize()
                            }
                        }
                    }
                    .contextMenu { UnitMenu(courseId: course.id, unitId: unit.id) }
                }
            }
            .opens { model.section = .units }
        }
    }

    func gradesBlock(_ file: CourseFile, score: GradeCalculator.CourseScore) -> some View {
        Block(
            String(localized: .courseSectionGrades),
            note: file.components.isEmpty ? nil : String(localized: .courseRemainingWeight(Int(score.remainingWeight.rounded())))
        ) {
            Card(padding: Theme.Space.l) {
                if file.components.isEmpty {
                    EmptyLine(String(localized: .courseNoComponents))
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.l) {
                            Figure(String(localized: .courseSecured), score.secured.oneDecimal, font: Theme.Typeface.figureCompact)
                            Figure(
                                String(localized: .courseProjectedTitle), score.projected.map(\.oneDecimal) ?? "-", tint: accent.ink,
                                font: Theme.Typeface.figureCompact)
                        }
                        .sensitive()
                        WeightBar(components: file.components)
                    }
                }
            }
            .opens { model.section = .grades }
        }
    }
}
