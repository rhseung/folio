import Algorithms
import FolioActions
import FolioDomain
import SwiftUI

/// Course codes from catalog.json as tiles: a prefix and its department at a glance, the ones my courses use in their
/// colors. A tile opens its editor.
struct CodesView: View {
    @Environment(Workspace.self) private var workspace
    @State private var query = ""
    @State private var editing: UUID?

    var body: some View {
        let device = workspace.device
        let users = Dictionary(grouping: workspace.allCourseRecords.flatMap { c in c.codes.map { (code: $0, course: c.id) } }, by: \.code)
            .mapValues { $0.map(\.course) }
        CatalogEditing { $catalog in
            Page {
                PageHeader(title: "강의 코드", subtitle: "\(catalog.codes.count)개 · 과목에는 여러 코드를 붙일 수 있고 첫 번째가 대표 코드입니다")
                SearchField(prompt: "접두어나 학과", text: $query).frame(maxWidth: 320)
                // Grouped by program (학사과정, 대학원과정) in the order they first appear in the table.
                let programs = Array(catalog.codes.map(\.program).uniqued())
                ForEach(programs, id: \.self) { program in
                    let shown = catalog.codes.filter { c in
                        c.program == program && (query.isEmpty || [c.prefix, c.department].contains { $0.localizedCaseInsensitiveContains(query) })
                    }
                    .sorted { $0.prefix < $1.prefix }
                    if query.isEmpty || !shown.isEmpty {
                        Block(program.isEmpty ? "과정 없음" : program, note: "\(shown.count)개") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                                ForEach(shown) { code in
                                    let remove = {
                                        editing = nil
                                        catalog.codes.removeAll { $0.id == code.id }
                                    }
                                    CodeTile(code: code, courses: users[code.id] ?? [])
                                        .onTapGesture { editing = code.id }
                                        .contextMenu {
                                            Button("편집") { editing = code.id }
                                            Divider()
                                            Button("삭제", role: .destructive, action: remove).disabled(workspace.codeRemoval(code.id) != nil)
                                        }
                                        .popover(isPresented: Binding(get: { editing == code.id }, set: { if !$0 { closeEditor(code.id, catalog: $catalog, users: users) } }),
                                                 arrowEdge: .bottom) {
                                            CodeEditor(code: $catalog.codes.element(id: code.id, fallback: code), programs: programs, courses: users[code.id] ?? [], remove: remove)
                                        }
                                }
                                if query.isEmpty {
                                    Button {
                                        let code = CourseCode(device: device, at: .now, prefix: "", program: program)
                                        catalog.codes.append(code)
                                        editing = code.id
                                    } label: {
                                        Label("코드 추가", systemImage: "plus")
                                            .foregroundStyle(Theme.Palette.textTertiary)
                                            .frame(maxWidth: .infinity, minHeight: CodeTile.height)
                                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                                            .contentShape(.rect)
                                    }
                                    .buttonStyle(.pointing(.plain))
                                }
                            }
                        }
                    }
                }
                if !query.isEmpty, !catalog.codes.contains(where: { [$0.prefix, $0.department].contains { $0.localizedCaseInsensitiveContains(query) } }) {
                    EmptyLine("맞는 코드가 없습니다")
                }
            }
        }
        .navigationTitle("강의 코드")
    }

    /// A code added and left blank goes away with its editor, instead of staying in catalog.json as an empty tile.
    func closeEditor(_ id: UUID, catalog: Binding<Catalog>, users: [UUID: [UUID]]) {
        guard editing == id else { return }
        editing = nil
        if let code = catalog.wrappedValue.codes.first(where: { $0.id == id }), users[id] == nil,
           code.prefix.trimmingCharacters(in: .whitespaces).isEmpty, code.department.trimmingCharacters(in: .whitespaces).isEmpty {
            catalog.wrappedValue.codes.removeAll { $0.id == id }
        }
    }
}

private struct CodeTile: View {
    @Environment(Workspace.self) private var workspace
    static let height: CGFloat = 108
    let code: CourseCode
    let courses: [UUID]

    var body: some View {
        // A code my courses use takes the first one's color; the rest stay quiet.
        let accent = courses.first.map { workspace.accent($0) }
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .center) {
                Text(code.prefix.isEmpty ? "—" : code.prefix)
                    .font(.system(size: 20, weight: .bold, design: .rounded)) // design: one-off, the prefix is the code tile's face
                    .foregroundStyle(accent?.ink ?? Theme.Palette.text)
                Spacer()
                HStack(spacing: Theme.Space.xxs) {
                    ForEach(courses.prefix(4), id: \.self) { CourseDot(color: workspace.accent($0).color, size: 8) }
                }
            }
            Text(code.department.isEmpty ? "학과 없음" : code.department)
                .foregroundStyle(Theme.Palette.textSecondary).lineLimit(2)
            Spacer(minLength: 0)
            Text(courses.isEmpty ? code.source : "\(courses.count)과목" + (code.source.isEmpty ? "" : " · \(code.source)"))
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

struct CodeEditor: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.searchTarget) private var searchTarget
    @Binding var code: CourseCode
    let programs: [String]
    let courses: [UUID]
    let remove: () -> Void


    var body: some View {
        // Newest term first, the way the sidebar lists semesters.
        let records = workspace.allCourseRecords.filter { courses.contains($0.id) }
            .sorted { (workspace.semester(of: $0)?.order ?? 0, $1.title) > (workspace.semester(of: $1)?.order ?? 0, $0.title) }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if !records.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Caption("쓰는 과목 \(records.count)개")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(records) { c in
                                Button { searchTarget.wrappedValue = SearchTarget(courseId: c.id, section: .overview) } label: {
                                    HStack(spacing: Theme.Space.s) {
                                        CourseDot(color: workspace.accent(c.id).color, size: 8)
                                        Text(c.title).lineLimit(1)
                                        Spacer(minLength: Theme.Space.s)
                                        Text(workspace.semester(of: c)?.title ?? "").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                    }
                                    .padding(.vertical, Theme.Space.tight)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.pointing(.plain))
                                .help("\(c.title) 열기")
                            }
                        }
                    }
                    // GS alone has a dozen and more; past about eight rows the list scrolls instead of growing the popover.
                    .frame(maxHeight: 240)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.s) {
                // Each field is as wide as what goes in it: a prefix is two or three letters, a department name is long.
                GridRow { Text("접두어"); TextField("EC", text: $code.prefix).pill(width: 64, alignment: .leading) }
                GridRow { Text("학과"); TextField("전기전자컴퓨터공학부", text: $code.department).pill(width: nil, alignment: .leading) }
                GridRow {
                    Text("과정")
                    ChoiceMenu(selection: $code.program, options: programs.map { ($0, $0.isEmpty ? "과정 없음" : $0) })
                }
                GridRow { Text("출처"); TextField("예: 2026 편람", text: $code.source).pill(width: nil, alignment: .leading) }
            }
            HStack {
                Spacer()
                let refusal = workspace.codeRemoval(code.id)
                Button("삭제", role: .destructive, action: remove).buttonStyle(.ghost).disabled(refusal != nil)
                    .help(refusal ?? "이 코드를 지웁니다")
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 300)
    }
}

extension Workspace {
    /// Why the code can't be removed (a course still uses it), by the catalog's own rules; nil when it can.
    func codeRemoval(_ id: UUID) -> String? {
        var c = catalog
        c.codes.removeAll { $0.id == id }
        return refusal(CatalogSet(catalog: c))
    }
}
