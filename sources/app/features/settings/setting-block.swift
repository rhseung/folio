import FolioDomain
import SwiftUI

// 설정 화면의 한 묶음이다. 선언에서 그 묶음에 놓인 항목을 차례대로 행으로 그리고, 탭이 따로 그리는 행(`extra`)을 그 뒤에 둔다.
// 다른 항목의 스위치가 되는 토글은 따로 행을 갖지 않는다.
struct SettingBlock<Extra: View>: View {
    let group: SettingGroup
    @Bindable var model: SettingsModel
    private let hasExtra: Bool
    private let extra: Extra
    @State private var details = false

    init(_ group: SettingGroup, model: SettingsModel, @ViewBuilder extra: () -> Extra) {
        self.group = group
        self.model = model
        hasExtra = true
        self.extra = extra()
    }

    var rows: [SettingItem] {
        let switches = Set(group.rows.compactMap(\.switchedBy))
        return group.rows.filter { !switches.contains($0.key) }
    }

    var body: some View {
        let rows = rows, more = group.more
        if let prose = rows.first(where: { $0.shape == .prose }) {
            TextArea(
                label: String(localized: prose.name),
                text: Binding(get: { model.text(of: prose) }, set: { model.set(prose, .string($0)) }))
        } else if let name = group.name {
            Block(String(localized: name)) { card(rows, more) }
        } else {
            card(rows, more)
        }
    }

    func card(_ rows: [SettingItem], _ more: [SettingItem]) -> some View {
        Card(clipped: hasExtra || !more.isEmpty) {
            ForEach(rows, id: \.key) { item in
                SettingRow(item: item, model: model, last: item.key == rows.last?.key && !hasExtra && more.isEmpty)
            }
            extra
            if !more.isEmpty {
                DisclosureRow(label: String(localized: .settingsDetails), isExpanded: $details, last: true) {
                    ForEach(more, id: \.key) { item in SettingRow(item: item, model: model, last: item.key == more.last?.key) }
                }
            }
        }
    }
}

extension SettingBlock where Extra == EmptyView {
    init(_ group: SettingGroup, model: SettingsModel) {
        self.group = group
        self.model = model
        hasExtra = false
        extra = EmptyView()
    }
}
