import FolioDomain
import SwiftUI

struct PeopleView: View {
    @State private var model: PeopleModel
    @Environment(\.place) private var place
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace) {
        _model = State(initialValue: PeopleModel(workspace: workspace))
    }

    func openCourse(_ id: UUID) { openLink(.course(id)) }

    /// Cleared here too: a person just added isn't saved yet, so the window is still on the list and the link alone
    /// wouldn't move.
    func backToList() {
        model.selection = nil
        openLink(.place(.people))
    }

    var body: some View {
        CatalogEditing { $catalog in
            let shown = model.shown(in: catalog)
            ColumnSplit(fold: .stack(showingPage: model.selection != nil)) {
                list($catalog, shown: shown)
            } bar: {
                Button(.peopleTitle, systemImage: "chevron.left", action: backToList)
            } content: {
                if let i = catalog.people.firstIndex(where: { $0.id == shown }) {
                    detail(catalog.people[i], person: $catalog.people.element(id: catalog.people[i].id, fallback: catalog.people[i]))
                } else {
                    ContentUnavailableView(String(localized: .peopleChoose), systemImage: "person.2")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.Palette.page)
                }
            }
            .confirmationDialog(String(localized: .peopleRemoveConfirm(model.removing?.name ?? "")),
                                isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } }),
                                presenting: model.removing) { person in
                Button(.commonDelete, role: .destructive) { model.remove(person, from: &catalog) }
            } message: { person in
                Text(model.removalMessage(person))
            }
        }
        .navigationTitle(.peopleTitle)
        // The window's link is the selection, so picking a person, and going back to the list where the list and a
        // person don't fit side by side, are steps in the window's history.
        .onChange(of: place, initial: true) { _, entry in
            guard let entry else { return }
            if entry.link.kind == .person, let id = entry.link.id { model.selection = id }
            if entry.link.kind == .people { model.selection = nil }
        }
    }

    func list(_ catalog: Binding<Catalog>, shown: UUID?) -> some View {
        let groups = model.groups(in: catalog.wrappedValue)
        let taughtCount = model.taughtCount
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SearchField(prompt: String(localized: .peopleSearch), text: $model.query)
                Button(.commonAdd, systemImage: "plus") { model.add(to: &catalog.wrappedValue) }
                    .buttonStyle(.ghostIcon)
                    .help(Text(.peopleAdd))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    ForEach(groups, id: \.role) { role, people in
                        Caption(String(localized: .peopleGroup(role.label, people.count)))
                            .padding(.horizontal, Theme.Space.s).padding(.top, role == groups.first?.role ? 0 : Theme.Space.m).padding(.bottom, Theme.Space.xs)
                        ForEach(people) { p in
                            let chosen = shown == p.id
                            Button { openLink(AppLink(.person, p.id)) } label: {
                                HStack(spacing: Theme.Space.s + 2) {
                                    Avatar(name: p.name, id: p.id)
                                    Text(model.name(p)).fontWeight(chosen ? .semibold : .regular).lineLimit(1)
                                    Spacer()
                                    if let n = taughtCount[p.id] { Text(.peopleCourseCount(n)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary) }
                                }
                                .padding(Theme.Inset.listRow)
                                .background(chosen ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pointing(.plain))
                            .contextMenu {
                                if let url = model.workspace.mailURL(to: p.email) { Link(String(localized: .peopleMail), destination: url) }
                                Divider()
                                Button(.commonDeleteEllipsis, role: .destructive) { model.removing = p }
                            }
                        }
                    }
                    if groups.isEmpty { EmptyLine(model.emptyList).padding(.top, Theme.Space.s) }
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
        let taught = model.taught(by: p.id)
        return Page {
            HStack(alignment: .center, spacing: Theme.Space.l) {
                Avatar(name: p.name, id: p.id, size: 56)
                PageHeader(title: model.name(p), subtitle: model.subtitle(p))
                Spacer()
                if let url = model.workspace.mailURL(to: p.email) {
                    Link(destination: url) { Label(.peopleMail, systemImage: "envelope") }
                        .buttonStyle(.bordered).pointingHand().help(p.email)
                }
                Button(.commonDelete, systemImage: "trash", role: .destructive) { model.removing = p }
                    .buttonStyle(.ghostIcon).help(Text(.peopleRemoveHelp))
            }
            Block(String(localized: .peopleContact)) {
                Card {
                    FormRow(label: String(localized: .peopleFieldName)) { InlineField(String(localized: .peopleFieldName), text: person.name) }
                    FormRow(label: String(localized: .peopleFieldRole)) {
                        ChoiceMenu(selection: person.role, options: PersonRole.allCases.map { ($0, $0.label) })
                    }
                    FormRow(label: String(localized: .peopleFieldEmail)) { InlineField("name@gist.ac.kr", text: person.email) }
                    FormRow(label: String(localized: .peopleFieldOffice)) { InlineField(String(localized: .peopleFieldOfficeExample), text: person.office) }
                    FormRow(label: String(localized: .peopleFieldOfficeHours), last: true) {
                        InlineField(String(localized: .peopleFieldOfficeHoursExample), text: person.officeHours)
                    }
                }
            }
            Block(String(localized: .peopleTaught)) {
                Card {
                    if taught.isEmpty {
                        CardRow(last: true) { EmptyLine(String(localized: .peopleTaughtEmpty)) }
                    }
                    ForEach(Array(taught.enumerated()), id: \.element.course.id) { i, item in
                        let opens = model.opens(item.course.id)
                        CardRow(last: i == taught.count - 1) {
                            CourseMark(model.workspace, item.course.id)
                            Text(item.course.title).lineLimit(1)
                            Spacer(minLength: Theme.Space.m)
                            Text(item.semester?.title ?? "").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                            Image(systemName: "chevron.right").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                .opacity(opens ? 1 : 0)
                        }
                        .opens(opens ? { openCourse(item.course.id) } : nil)
                        .contextMenu { if opens { Button(.commonOpenCourse) { openCourse(item.course.id) } } }
                    }
                }
            }
            FormTextArea(label: String(localized: .peopleMemo), detail: String(localized: .peopleMemoDetail), text: person.memo, height: 140)
        }
    }
}
