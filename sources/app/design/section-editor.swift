import FolioDomain
import SwiftUI

struct SectionEditor: View {
    @Binding var split: LectureSplit
    let units: [FolioDomain.Unit]
    var page: Int?
    var selected: Binding<Int?>?
    var pick: (Int) -> Void = { _ in }

    @State private var own: Int?

    private var picked: Binding<Int?> { selected ?? $own }

    var body: some View {
        let selected = picked
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionBar(split: $split, selected: selected, label: label, page: page, pick: pick)
            VStack(spacing: 0) {
                ForEach(Array(split.sections.enumerated()), id: \.element.id) { i, section in
                    SectionRow(split: $split, id: section.id, units: units, selected: selected.wrappedValue == i, label: label(i))
                        .contentShape(.rect)
                        .onTapGesture {
                            guard let i = split.sections.firstIndex(where: { $0.id == section.id }) else { return }
                            selected.wrappedValue = i
                            pick(split.sections[i].firstPage)
                        }
                }
            }
        }
        .onChange(of: split.sections.count) { _, count in if let s = selected.wrappedValue, s >= count { selected.wrappedValue = nil } }
    }

    func label(_ i: Int) -> String {
        guard split.sections.indices.contains(i) else { return "" }
        let s = split.sections[i]
        guard let unit = s.unit else { return "" }
        if s.isNew { return s.title }
        return units.first { $0.id == unit }?.title ?? s.title
    }
}

// 행은 자리가 아니라 구간의 id를 가진다. 합치기나 화면 닫기로 나누기가 줄어든 뒤에도 행이 한 번 더 그려지는데, 옛
// 자리를 읽은 행은 배열 끝을 넘었다. 그래서 편집마다 실행할 때 자리를 찾는다.
private struct SectionRow: View {
    @Binding var split: LectureSplit
    let id: LectureSplit.Section.ID
    let units: [FolioDomain.Unit]
    let selected: Bool
    let label: String

    @Environment(\.accent) private var accent
    @State private var cutting = false
    @State private var cutPage = ""

    private var index: Int? { split.sections.firstIndex { $0.id == id } }

    var body: some View {
        if let index {
            row(split.sections[index], at: index)
                .alert(String(localized: .designSectionsCutTitle), isPresented: $cutting) {
                    TextField(String(localized: .designSectionsCutPage), text: $cutPage)
                        #if os(iOS)
                    .keyboardType(.numberPad)
                        #endif
                    Button(String(localized: .designSectionsCutAction)) { cut() }
                    Button(String(localized: .commonCancel), role: .cancel) {}
                } message: {
                    let s = split.sections[index]
                    Text(.designSectionsCutRange(s.firstPage + 1, s.lastPage))
                }
        }
    }

    private func cut() {
        guard let index, let page = Int(cutPage.trimmingCharacters(in: .whitespaces)),
            split.sections[index].pages.contains(page)
        else { return }
        split.split(at: page)
    }

    private func row(_ section: LectureSplit.Section, at index: Int) -> some View {
        HStack(spacing: Theme.Space.s) {
            name(section).frame(maxWidth: .infinity, alignment: .leading)
            Text(section.firstPage == section.lastPage ? "\(section.firstPage)" : "\(section.firstPage)–\(section.lastPage)")
                .font(Theme.Typeface.mono).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            unitMenu(section, at: index).frame(width: 152, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Space.s)
        .frame(height: 32)
        .background(selected ? Theme.Palette.fill : .clear, in: .rect(cornerRadius: Theme.Radius.control))
    }

    private func edit(_ change: (Int) -> Void) {
        if let index { change(index) }
    }

    @ViewBuilder private func name(_ section: LectureSplit.Section) -> some View {
        if section.isNew {
            TextField(
                String(localized: .designSectionsNamePlaceholder),
                text: Binding(get: { section.title }, set: { title in edit { split.rename($0, to: title) } })
            )
            .textFieldStyle(.plain)
        } else {
            let own = section.title.isEmpty ? label : section.title
            Text(own.isEmpty ? String(localized: .designSectionsUnnamed) : own)
                .foregroundStyle(own.isEmpty || section.unit == nil ? Theme.Palette.textTertiary : Theme.Palette.text)
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private func unitMenu(_ section: LectureSplit.Section, at index: Int) -> some View {
        Menu {
            if section.match != nil {
                Text(matchHelp(section))
                Divider()
            }
            Section(String(localized: .designSectionsCourseUnits)) {
                ForEach(UnitTree.outline(units), id: \.unit.id) { item in
                    Button {
                        edit { split.setUnit(item.unit.id, of: $0) }
                    } label: {
                        if section.unit == item.unit.id && !section.isNew { Image(systemName: "checkmark") }
                        Text(String(repeating: "    ", count: item.depth) + item.unit.title)
                    }
                }
            }
            Button(
                section.title.isEmpty
                    ? String(localized: .designSectionsNewUnit) : String(localized: .designSectionsNewUnitNamed(section.title))
            ) {
                edit { split.makeNew($0) }
            }
            Button(String(localized: .designSectionsNoUnit)) { edit { split.setUnit(nil, of: $0) } }
            Divider()
            Button(String(localized: .designSectionsCut)) {
                cutPage = ""
                cutting = true
            }
            .disabled(section.firstPage == section.lastPage)
            Button(String(localized: .designSectionsMergeBefore)) { edit { split.merge(after: $0 - 1) } }.disabled(index == 0)
            Button(String(localized: .designSectionsMergeAfter)) { edit { split.merge(after: $0) } }.disabled(
                index == split.sections.count - 1)
        } label: {
            HStack(spacing: Theme.Space.tight) {
                if section.match != nil { Image(systemName: "sparkle").font(Theme.Glyph.small).foregroundStyle(accent.color) }
                menuText(section).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down").font(Theme.Glyph.small).foregroundStyle(Theme.Palette.textTertiary)
            }
            .contentShape(.rect)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).pointingHand()
        .help(matchHelp(section))
    }

    @ViewBuilder private func menuText(_ section: LectureSplit.Section) -> some View {
        if section.isNew {
            Text(.designSectionsNewUnitLabel).foregroundStyle(accent.ink)
        } else if let unit = section.unit {
            Text(units.first { $0.id == unit }?.title ?? "").foregroundStyle(Theme.Palette.textSecondary)
        } else {
            Text(.designSectionsSkip).foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    private func matchHelp(_ section: LectureSplit.Section) -> String {
        switch section.match {
        case .name: String(localized: .designSectionsMatchName)
        case .claude: String(localized: .designSectionsMatchClaude)
        case nil: String(localized: .designSectionsUnitHelp)
        }
    }
}
