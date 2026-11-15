import FolioDomain
import SwiftUI

struct SearchPicker<ID: Hashable, Label: View>: View {
    let options: [PickOption<ID>]
    var isSelected: (ID) -> Bool = { _ in false }
    let pick: (ID) -> Void
    var multiple = false
    var prompt = String(localized: .commonSearch)
    var flexible = false
    var create: ((String) -> Void)?
    var createTitle: (String) -> String = { $0 }
    @ViewBuilder let label: Label
    @State private var open = false
    @State private var query = ""
    @State private var highlighted: ID?
    @FocusState private var focused: Bool

    var filtered: [PickOption<ID>] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return options }
        return options.filter { o in [o.title, o.detail, o.section].contains { $0?.localizedCaseInsensitiveContains(q) == true } }
    }

    var creatable: String? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard create != nil, !q.isEmpty, !options.contains(where: { $0.title.caseInsensitiveCompare(q) == .orderedSame }) else {
            return nil
        }
        return q
    }

    var body: some View {
        Button {
            open.toggle()
        } label: {
            label
        }
        .buttonStyle(.pointing(.plain))
        .fixedSize(horizontal: !flexible, vertical: true)
        .popover(isPresented: $open, arrowEdge: .bottom) { panel }
    }

    var panel: some View {
        let rows = filtered
        return VStack(spacing: 0) {
            HStack(spacing: Theme.Space.tight) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.textTertiary)
                TextField(prompt, text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        if let id = highlighted ?? rows.first?.id { choose(id) } else if let title = creatable { make(title) }
                    }
                    .onKeyPress(.downArrow) {
                        step(1, in: rows); return .handled
                    }
                    .onKeyPress(.upArrow) {
                        step(-1, in: rows); return .handled
                    }
            }
            .padding(Theme.Space.m)
            Theme.Palette.line.frame(height: 1)
            if let title = creatable {
                createRow(title)
                if !rows.isEmpty { Theme.Palette.lineSoft.frame(height: 1) }
            }
            if rows.isEmpty {
                if creatable == nil {
                    EmptyLine(String(localized: .designNoMatch)).padding(Theme.Space.m).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, o in
                                if let section = o.section, i == 0 || rows[i - 1].section != section {
                                    Caption(section).padding(.horizontal, Theme.Space.m).padding(.top, Theme.Space.s).padding(
                                        .bottom, Theme.Space.xxs)
                                }
                                row(o).id(o.id)
                            }
                        }
                        .padding(.vertical, Theme.Space.xs)
                    }
                    .overflowFade(.vertical)
                    .onChange(of: highlighted) { _, id in if let id { proxy.scrollTo(id) } }
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 340)
        .font(Theme.Typeface.body)
        .onAppear {
            query = ""
            highlighted = options.first { isSelected($0.id) }?.id
            focused = true
        }
        .onChange(of: query) { highlighted = filtered.first?.id }
    }

    func row(_ o: PickOption<ID>) -> some View {
        Button {
            choose(o.id)
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "checkmark").font(Theme.Glyph.regular)
                    .opacity(isSelected(o.id) ? 1 : 0)
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(o.title).lineLimit(1)
                    if let detail = o.detail {
                        Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, Theme.Space.m + CGFloat(o.depth) * Theme.Space.m)
            .padding(.trailing, Theme.Space.m)
            .padding(.vertical, Theme.Space.tight)
            .background(highlighted == o.id ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .padding(.horizontal, Theme.Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .disabled(o.disabled && !isSelected(o.id))
        .opacity(o.disabled && !isSelected(o.id) ? 0.45 : 1)
        .onHover { if $0 { highlighted = o.id } }
    }

    func createRow(_ title: String) -> some View {
        Button {
            make(title)
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "plus").font(Theme.Glyph.regular)
                Text(createTitle(title)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.tight)
            .background(rowsEmpty ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .padding(Theme.Space.xs)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
    }

    private var rowsEmpty: Bool { filtered.isEmpty }

    func make(_ title: String) {
        create?(title)
        query = ""
        if !multiple { open = false }
    }

    func step(_ delta: Int, in rows: [PickOption<ID>]) {
        guard !rows.isEmpty else { return }
        let i = highlighted.flatMap { id in rows.firstIndex { $0.id == id } } ?? (delta > 0 ? -1 : rows.count)
        highlighted = rows[min(max(i + delta, 0), rows.count - 1)].id
    }

    func choose(_ id: ID) {
        // 강조한 행에서 Return을 누르면 버튼을 거치지 않고 여기로 오므로, disabled 검사를 한 번 더 한다.
        if options.first(where: { $0.id == id })?.disabled == true, !isSelected(id) { return }
        pick(id)
        if !multiple { open = false }
    }
}
