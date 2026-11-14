import FolioDomain
import SwiftUI

struct QuickAddChip: View {
    static let inset = Theme.Space.m
    let model: QuickAddModel
    let chip: QuickAddModel.Chip
    @State private var pickingDue = false
    @State private var pickingRepeat = false
    @State private var rule = AssignmentRepeat.weekly

    var body: some View {
        Group {
            switch chip {
            case let .course(id): courseChip(id)
            case let .due(date): dueChip(date)
            case let .repeats(repeats): repeatsChip(repeats)
            case let .folder(name): folderChip(name)
            }
        }
        #if DEBUG && os(macOS)
        .task {
            switch chip {
            case .due where SnapshotDriver.shared.quickAddDueOpen:
                try? await Task.sleep(for: .seconds(0.6))
                pickingDue = true
            case let .repeats(repeats?) where SnapshotDriver.shared.quickAddRepeatOpen:
                try? await Task.sleep(for: .seconds(0.6))
                rule = repeats
                pickingRepeat = true
            default: break
            }
        }
        #endif
    }

    private func courseChip(_ id: UUID?) -> some View {
        Menu {
            ForEach(model.courses, id: \.id) { c in
                Button {
                    model.pickCourse(c.id)
                } label: {
                    if c.id == id { Label(c.title, systemImage: "checkmark") } else { Text(c.title) }
                }
            }
        } label: {
            if let id, let title = model.courseTitle(id) {
                let accent = model.accent(id)
                label(fill: accent.read) {
                    CourseMark(model.workspace, id, inline: true)
                    Text(title).foregroundStyle(accent.ink)
                }
            } else if model.isDimmed(chip) {
                dimmed("book.closed", .quickAddChipCourse)
            } else {
                label(fill: Theme.Palette.dangerFill) {
                    Image(systemName: "exclamationmark.circle")
                    Text(.quickAddPickCourse)
                }
                .foregroundStyle(Theme.Palette.danger)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
    }

    private func dueChip(_ date: Date?) -> some View {
        Button {
            pickingDue = true
        } label: {
            if model.isDimmed(chip) {
                dimmed("clock", .quickAddChipDue)
            } else {
                dueLabel(date)
            }
        }
        .buttonStyle(.pointing(.plain))
        .popover(isPresented: $pickingDue, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                DatePanel(date: Binding(get: { date ?? model.newDue }, set: { model.pickDue($0) }))
                Divider()
                Toggle(
                    String(localized: .quickAddRepeatToggle),
                    isOn: Binding(
                        get: { model.parsed?.repeats != nil },
                        set: { on in
                            if on, model.parsed?.due == nil { model.pickDue(model.newDue) }
                            model.pickRepeats(on ? .weekly : nil)
                        }))
                if date != nil {
                    Button(String(localized: .quickAddClearDue), role: .destructive) {
                        model.pickDue(nil)
                        pickingDue = false
                    }
                    .buttonStyle(.ghost)
                }
            }
            .padding(Theme.Space.l)
            .frame(width: 280)
            // popover는 열릴 때의 높이를 제안하므로, 첫 날짜를 골라 아래에 지우기 버튼이 생기면 높이가 모자란다.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dueLabel(_ date: Date?) -> some View {
        label(fill: Theme.Palette.readDue) {
            Image(systemName: "clock")
            if let date, let parsed = model.parsed, let text = model.due(parsed) {
                Text(text)
                if let left = model.left(date) {
                    Text(left.text).foregroundStyle(
                        left.overdue ? Theme.Palette.danger : Theme.Palette.readDueInk.opacity(Theme.Opacity.secondaryInk))
                }
            } else {
                Text(.quickAddAddDue)
            }
        }
        .foregroundStyle(Theme.Palette.readDueInk)
        .monospacedDigit()
    }

    private func repeatsChip(_ repeats: AssignmentRepeat?) -> some View {
        Menu {
            RepeatMenuItems(
                selection: repeats, custom: repeats.map { !AssignmentRepeat.presets.contains($0) } ?? false,
                pick: { model.pickRepeats($0) },
                customize: {
                    rule = repeats ?? .weekly
                    if repeats == nil { model.pickRepeats(rule) }
                    pickingRepeat = true
                })
        } label: {
            if model.isDimmed(chip) {
                dimmed("repeat", .quickAddChipRepeat)
            } else {
                label(fill: Theme.Palette.readDue) {
                    Image(systemName: "repeat")
                    Text(repeats?.label ?? "")
                }
                .foregroundStyle(Theme.Palette.readDueInk)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
        .popover(isPresented: $pickingRepeat, arrowEdge: .bottom) {
            Card {
                RepeatRuleRows(
                    rule: Binding(
                        get: { rule },
                        set: {
                            rule = $0; model.pickRepeats($0)
                        }), dueWeekday: model.dueWeekday, last: true)
            }
            .padding(Theme.Space.l)
            .frame(width: 360)
            // popover는 마지막에 받은 높이를 제안한다. 개월로 바꿨다가 주로 돌아오면 요일 줄이 더 낮은 높이에 눌려 행이
            // 카드 가장자리 밖으로 넘쳤다.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func folderChip(_ name: String?) -> some View {
        let current = model.kind
        return Menu {
            Section(String(localized: .quickAddKind)) {
                ForEach(AssignmentKind.allCases, id: \.self) { kind in
                    Button {
                        model.renumber(kind: kind, number: current?.number ?? 1)
                    } label: {
                        if kind == current?.kind { Label(kind.rawValue, systemImage: "checkmark") } else { Text(kind.rawValue) }
                    }
                }
            }
            Menu(String(localized: .quickAddNumber)) {
                ForEach(1...20, id: \.self) { n in
                    Button {
                        model.renumber(kind: current?.kind ?? .homework, number: n)
                    } label: {
                        if n == current?.number { Label(String(n), systemImage: "checkmark") } else { Text(String(n)) }
                    }
                }
            }
        } label: {
            if let name {
                label(fill: Theme.Palette.readFolder) {
                    Image(systemName: "folder")
                    Text(verbatim: name)
                }
                .foregroundStyle(Theme.Palette.readFolderInk)
            } else {
                dimmed("folder", .quickAddChipFolder)
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain).pointingHand()
        .fixedSize()
    }

    private func dimmed(_ icon: String, _ title: LocalizedStringResource) -> some View {
        label(fill: Theme.Palette.text.opacity(Theme.Opacity.wash)) {
            Image(systemName: icon)
            Text(title)
        }
        .foregroundStyle(Theme.Palette.textTertiary)
    }

    private func label<Content: View>(fill: Color, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Theme.Space.tight) { content() }
            .font(Theme.Typeface.caption)
            .lineLimit(1)
            .padding(.horizontal, Self.inset)
            .frame(height: 28)
            .background(fill, in: .capsule)
            .contentShape(.capsule)
            #if os(iOS)
        .padding(.vertical, Theme.Space.s)
        .contentShape(.rect)
            #endif
    }
}
