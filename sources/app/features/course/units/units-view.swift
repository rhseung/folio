import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct UnitsView: View {
    @State private var model: UnitsModel
    let course: LoadedCourse
    let place: AppLink
    let opened: (UUID?) -> Void

    init(workspace: Workspace, course: LoadedCourse, place: AppLink, opened: @escaping (UUID?) -> Void) {
        let model = UnitsModel(workspace: workspace, courseId: course.id)
        // 아래의 첫 보고보다 먼저 정해야 한다. 그러지 않으면 창에 목록이 보인다고 알린다.
        if place.kind == .unit { model.openUnit = place.id }
        _model = State(initialValue: model)
        self.course = course
        self.place = place
        self.opened = opened
    }

    var body: some View {
        Group {
            if let id = model.openUnit, let unit = course.file.units.first(where: { $0.id == id }) {
                UnitDetail(model: model, course: course, unit: unit, delete: { model.remove(unit) })
            } else {
                list
            }
        }
        .task(id: course.file.units.map(\.id)) { model.loadQuiz(course) }
        .onChange(of: model.workspace.quizRevision) { model.loadQuiz(model.workspace.course(course.id) ?? course) }
        // 페이지는 목록에서 시작하고 지난번에 연 단원은 모델과 함께 사라졌으므로 initial로도 부른다.
        .onChange(of: model.openUnit, initial: true) { _, id in opened(id) }
        .onChange(of: place) { _, link in
            if link.kind == .unit { model.openUnit = link.id } else if link.kind == .course { model.openUnit = nil }
        }
        .confirming($model.pending)
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.unitStep, initial: true) { _, step in
            if step != nil { model.openUnit = UnitTree.outline(course.file.units).first?.unit.id }
        }
        #endif
    }

    struct Chapter: Identifiable {
        var root: FolioDomain.Unit?
        var rows: [(unit: FolioDomain.Unit, depth: Int)] = []
        var id: UUID? { root?.id ?? rows.first?.unit.id }
    }

    static func groups(_ outline: [(unit: FolioDomain.Unit, depth: Int)]) -> [Chapter] {
        var groups: [Chapter] = []
        for (i, row) in outline.enumerated() {
            let hasChildren = i + 1 < outline.count && outline[i + 1].depth > row.depth
            if row.depth == 0 && hasChildren {
                groups.append(Chapter(root: row.unit))
            } else if row.depth == 0 {
                if groups.last.map({ $0.root == nil }) != true { groups.append(Chapter()) }
                groups[groups.count - 1].rows.append(row)
            } else {
                groups[groups.count - 1].rows.append((row.unit, row.depth - 1))
            }
        }
        return groups
    }

    var list: some View {
        let file = course.file
        let states = model.states()
        let today = model.today
        let unlinked = file.sessionsNeedingUnits(at: model.workspace.now)
        return Page {
            PageHeader(title: String(localized: .unitsTitle), subtitle: model.subtitle(file, states: states))
            if !unlinked.isEmpty { unlinkedCard(unlinked) }
            ForEach(Self.groups(UnitTree.outline(file.units))) { group in
                if let root = group.root {
                    let exams = model.exams(of: root, in: file)
                    Block(
                        title: root.title, note: model.sessionsLine(root, in: file),
                        trailing: {
                            HStack(spacing: Theme.Space.s) {
                                ForEach(exams) { Chip($0.title) }
                                ReviewBadge(state: states[root.id], today: today)
                                Button {
                                    model.openUnit = root.id
                                } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .buttonStyle(.ghost).tint(Theme.Palette.textTertiary)
                                .help(Text(.unitsOpen))
                            }
                        }
                    ) {
                        Card { rows(group.rows, states: states, today: today, inheritedExams: Set(exams.map(\.id))) }
                    }
                    .contextMenu { menu(root) }
                } else {
                    Card { rows(group.rows, states: states, today: today, inheritedExams: []) }
                }
            }
            Card {
                CardRow(last: true) {
                    Image(systemName: "plus").foregroundStyle(Theme.Palette.textTertiary)
                    TextField(String(localized: .unitsNewName), text: $model.newTitle).textFieldStyle(.plain).onSubmit(model.add)
                    Button(.commonAdd, action: model.add).buttonStyle(.prominent).disabled(!model.canAdd)
                }
            }
            if file.units.isEmpty {
                EmptyLine(String(localized: .unitsEmpty))
                    .padding(.horizontal, Theme.Space.m)
            }
        }
    }

    func rows(_ rows: [(unit: FolioDomain.Unit, depth: Int)], states: [UUID: ReviewState], today: LocalDate, inheritedExams: Set<UUID>)
        -> some View
    {
        ForEach(Array(rows.enumerated()), id: \.element.unit.id) { i, row in
            let unit = row.unit
            let exams = model.exams(of: unit, in: course.file)
            CardRow(last: i == rows.count - 1) {
                Button {
                    model.openUnit = unit.id
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            Text(unit.title).font(Theme.Typeface.body)
                            Text(model.detail(unit, state: states[unit.id], in: course.file)).font(Theme.Typeface.caption).foregroundStyle(
                                Theme.Palette.textTertiary
                            ).lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.m)
                        if Set(exams.map(\.id)) != inheritedExams { ForEach(exams) { Chip($0.title) } }
                        ReviewBadge(state: states[unit.id], today: today)
                    }
                    .padding(.leading, CGFloat(row.depth) * Theme.Space.xl)
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
            }
            .contextMenu { menu(unit) }
        }
    }

    func menu(_ unit: FolioDomain.Unit) -> some View {
        UnitMenu(courseId: course.id, unitId: unit.id, host: .list)
    }

    func unlinkedCard(_ sessions: [Session]) -> some View {
        let shown = sessions.prefix(6)
        return NoticeCard(
            title: String(localized: .unitsUnlinkedTitle(sessions.count)),
            detail: String(localized: .unitsUnlinkedDetail),
            systemImage: "link.badge.plus", trailing: { EmptyView() }
        ) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                CardRow(last: i == shown.count - 1 && sessions.count <= shown.count) {
                    Text(course.file.title(of: s, calendar: model.workspace.calendar)).lineLimit(1)
                    Spacer(minLength: Theme.Space.m)
                    SessionUnitsButton(course: course, session: s)
                }
            }
            if sessions.count > shown.count {
                CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(sessions.count - shown.count))) }
            }
        }
    }
}

extension LocalDate {
    var shortLabel: String {
        date(in: .current)?.formatted(.dateTime.month().day().weekday()) ?? description
    }
}

extension ReviewResult {
    var label: String {
        switch self {
        case .again: String(localized: .reviewResultAgain)
        case .hard: String(localized: .reviewResultHard)
        case .good: String(localized: .reviewResultGood)
        case .easy: String(localized: .reviewResultEasy)
        case .skip: String(localized: .reviewResultSkip)
        }
    }
}
