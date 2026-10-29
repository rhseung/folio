import FolioDomain
import SwiftUI

/// The courses each person taught are found from the courses' instructorIds, never stored on the person.
struct PeopleView: View {
    @Environment(Workspace.self) private var workspace
    let openCourse: (UUID) -> Void
    @State private var selection: UUID?
    @State private var query = ""
    @State private var removing: Person?
    @Environment(\.personTarget) private var target

    var body: some View {
        CatalogEditing { $catalog in
            // A chosen person removed elsewhere (another device's save) falls back to the first instead of an empty page.
            let shown = selection.flatMap { id in catalog.people.contains { $0.id == id } ? id : nil }
                ?? catalog.people.min { ($0.role.order, $0.name) < ($1.role.order, $1.name) }?.id
            HStack(spacing: 0) {
                list($catalog, shown: shown)
                    .frame(width: Theme.Size.courseColumn)
                ColumnDivider()
                if let i = catalog.people.firstIndex(where: { $0.id == shown }) {
                    detail(catalog.people[i], person: $catalog.people.element(id: catalog.people[i].id, fallback: catalog.people[i]))
                } else {
                    ContentUnavailableView("사람을 고르세요", systemImage: "person.2")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Palette.page)
                }
            }
            .confirmationDialog("‘\(removing?.name ?? "")’을 지울까요?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                presenting: removing) { person in
                Button("삭제", role: .destructive) {
                    catalog.people.removeAll { $0.id == person.id }
                    selection = nil
                }
            } message: { person in
                let n = workspace.allCourseRecords.filter { $0.instructorIds.contains(person.id) }.count
                Text(n == 0 ? "맡은 과목이 없는 사람입니다." : "맡은 과목 \(n)개에서 이 사람이 빠집니다.")
            }
        }
        .navigationTitle("교수와 조교")
        .onChange(of: target.wrappedValue, initial: true) { _, id in
            guard let id else { return }
            selection = id
            target.wrappedValue = nil
        }
    }

    func list(_ catalog: Binding<Catalog>, shown: UUID?) -> some View {
        let people = catalog.wrappedValue.people
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.email.localizedCaseInsensitiveContains(query) }
            .sorted { ($0.role.order, $0.name) < ($1.role.order, $1.name) }
        let taughtCount = Dictionary(workspace.allCourseRecords.flatMap(\.instructorIds).map { ($0, 1) }, uniquingKeysWith: +)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SearchField(prompt: "이름이나 이메일", text: $query)
                Button("추가", systemImage: "plus") {
                    let person = Person(device: workspace.device, at: .now, name: "새 사람")
                    catalog.wrappedValue.people.append(person)
                    selection = person.id
                    query = ""
                }
                .buttonStyle(.ghostIcon)
                .help("사람 추가")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    ForEach(PersonRole.allCases, id: \.self) { role in
                        let group = people.filter { $0.role == role }
                        if !group.isEmpty {
                            Caption("\(role.label) \(group.count)").padding(.horizontal, Theme.Space.s).padding(.top, role == people.first?.role ? 0 : Theme.Space.m).padding(.bottom, Theme.Space.xs)
                            ForEach(group) { p in
                                let chosen = shown == p.id
                                Button { selection = p.id } label: {
                                    HStack(spacing: Theme.Space.s + 2) {
                                        Avatar(name: p.name, id: p.id)
                                        Text(p.name.isEmpty ? "이름 없음" : p.name).fontWeight(chosen ? .semibold : .regular).lineLimit(1)
                                        Spacer()
                                        if let n = taughtCount[p.id] { Text("\(n)과목").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
                                    }
                                    .padding(Theme.Inset.listRow)
                                    .background(chosen ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.pointing(.plain))
                                .contextMenu {
                                    if let url = workspace.mailURL(to: p.email) { Link("메일 쓰기", destination: url) }
                                    Divider()
                                    Button("삭제…", role: .destructive) { removing = p }
                                }
                            }
                        }
                    }
                    if people.isEmpty { EmptyLine(query.isEmpty ? "등록된 사람이 없습니다" : "찾는 사람이 없습니다").padding(.top, Theme.Space.s) }
                }
            }
        }
        .padding(.horizontal, Theme.Inset.panel)
        .padding(.vertical, Theme.Space.l)
        .font(Theme.Typeface.body)
        .foregroundStyle(Theme.Palette.text)
        .background(Theme.Palette.window)
    }

    func detail(_ p: Person, person: Binding<Person>) -> some View {
        let taught = workspace.allCourseRecords.filter { $0.instructorIds.contains(p.id) }
            .map { (course: $0, semester: workspace.semester(of: $0)) }
            .sorted { ($0.semester?.order ?? 0, $1.course.title) > ($1.semester?.order ?? 0, $0.course.title) }
        return Page {
            HStack(alignment: .center, spacing: Theme.Space.l) {
                Avatar(name: p.name, id: p.id, size: 56)
                PageHeader(title: p.name.isEmpty ? "이름 없음" : p.name,
                           subtitle: ([p.role.label] + (taught.isEmpty ? [] : ["맡은 과목 \(taught.count)개"])).joined(separator: " · "))
                Spacer()
                if let url = workspace.mailURL(to: p.email) {
                    Link(destination: url) { Label("메일 쓰기", systemImage: "envelope") }
                        .buttonStyle(.bordered).pointingHand().help(p.email)
                }
                Button("삭제", systemImage: "trash", role: .destructive) { removing = p }
                    .buttonStyle(.ghostIcon).help("이 사람 지우기")
            }
            Block("연락처") {
                Card {
                    FormRow(label: "이름") { InlineField("이름", text: person.name) }
                    FormRow(label: "역할") {
                        ChoiceMenu(selection: person.role, options: PersonRole.allCases.map { ($0, $0.label) })
                    }
                    FormRow(label: "이메일") { InlineField("name@gist.ac.kr", text: person.email) }
                    FormRow(label: "연구실") { InlineField("예: C-305", text: person.office) }
                    FormRow(label: "면담 시간", last: true) { InlineField("예: 화 14:00-16:00", text: person.officeHours) }
                }
            }
            Block("맡은 과목") {
                Card {
                    if taught.isEmpty {
                        CardRow(last: true) { EmptyLine("과목 편집에서 이 사람을 교수로 고르면 여기에 나옵니다") }
                    }
                    ForEach(Array(taught.enumerated()), id: \.element.course.id) { i, item in
                        // A course kept only in the transcript has no folder, so it has no page to open.
                        let loaded = workspace.course(item.course.id) != nil
                        CardRow(last: i == taught.count - 1) {
                            CourseDot(color: workspace.accent(item.course.id).color)
                            Text(item.course.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.m)
                            Text(item.semester?.title ?? "").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            Image(systemName: "chevron.right").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                .opacity(loaded ? 1 : 0)
                        }
                        .opens(loaded ? { openCourse(item.course.id) } : nil)
                        .contextMenu { if loaded { Button("과목 열기") { openCourse(item.course.id) } } }
                    }
                }
            }
            FormTextArea(label: "메모", detail: "시험 경향, 수업 방식 같은 것", text: person.memo, height: 140)
        }
    }
}

extension PersonRole: CaseIterable {
    public static let allCases: [PersonRole] = [.professor, .lecturer, .assistant]

    var label: String {
        switch self {
        case .professor: "교수"
        case .lecturer: "강사"
        case .assistant: "조교"
        }
    }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
