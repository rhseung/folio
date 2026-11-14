import FolioDomain
import SwiftUI

struct CodesView: View {
    @State private var model: CodesModel

    init(workspace: Workspace) { _model = State(initialValue: CodesModel(workspace: workspace)) }

    var body: some View {
        let users = model.users
        CatalogEditing { $catalog in
            Page {
                PageHeader(title: String(localized: .codesTitle), subtitle: model.subtitle(catalog))
                SearchField(prompt: String(localized: .codesSearch), text: $model.query).frame(maxWidth: 320)
                let programs = model.programs(in: catalog)
                ForEach(programs, id: \.self) { program in
                    let shown = model.shown(program, in: catalog)
                    if model.showsProgram(program, in: catalog) {
                        Block(CodesModel.programTitle(program), note: String(localized: .codesCount(shown.count))) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                                ForEach(shown) { code in
                                    let remove: @MainActor () -> Void = { model.remove(code.id, from: &catalog) }
                                    CodeTile(code: code, courses: users[code.id] ?? [])
                                        .onTapGesture { model.editing = code.id }
                                        .contextMenu {
                                            ItemMenu(
                                                source: CodeMenuSource(
                                                    edit: { model.editing = code.id }, remove: remove,
                                                    removable: model.removal(code.id) == nil))
                                        }
                                        .popover(
                                            isPresented: Binding(
                                                get: { model.editing == code.id },
                                                set: { if !$0 { model.closeEditor(code.id, catalog: &catalog) } }),
                                            arrowEdge: .bottom
                                        ) {
                                            CodeEditor(
                                                model: model, code: $catalog.codes.element(id: code.id, fallback: code), programs: programs,
                                                courses: users[code.id] ?? [], remove: remove)
                                        }
                                }
                                if model.query.isEmpty {
                                    Button {
                                        model.add(program, to: &catalog)
                                    } label: {
                                        Label(.codesAdd, systemImage: "plus")
                                            .foregroundStyle(Theme.Palette.textTertiary)
                                            .frame(maxWidth: .infinity, minHeight: CodeTile.height)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(
                                                    Theme.Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                            )
                                            .contentShape(.rect)
                                    }
                                    .buttonStyle(.pointing(.plain))
                                }
                            }
                        }
                    }
                }
                if model.hasNoMatch(in: catalog) {
                    EmptyLine(String(localized: .codesNoMatch))
                }
            }
        }
        .navigationTitle(.codesTitle)
    }
}

private struct CodeTile: View {
    @Environment(Workspace.self) private var workspace
    static let height: CGFloat = 108
    let code: CourseCode
    let courses: [UUID]

    var body: some View {
        let accent = courses.first.map { workspace.accent($0) }
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .center) {
                Text(code.prefix.isEmpty ? "—" : code.prefix)
                    .font(.system(size: 20, weight: .bold, design: .rounded))  // design: one-off, the prefix is the code tile's face
                    .foregroundStyle(accent?.ink ?? Theme.Palette.text)
                Spacer()
                HStack(spacing: Theme.Space.xxs) {
                    ForEach(courses.prefix(4), id: \.self) { CourseMark(workspace, $0, inline: true) }
                }
            }
            Text(code.department.isEmpty ? String(localized: .codesNoDepartment) : code.department)
                .foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
            Spacer(minLength: 0)
            Text(CodesModel.tileFooter(code, courses: courses.count))
                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
        }
        .padding(Theme.Inset.panel)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .topLeading)
        .background(accent?.tint ?? .clear, in: .rect(cornerRadius: Theme.Radius.card))
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(accent?.color.opacity(0.35) ?? Theme.Palette.lineSoft))
        .contentShape(.rect)
        .pointingHand()
    }
}
