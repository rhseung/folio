import FolioDomain
import SwiftUI

struct TargetCourseMenu<More: View>: View {
    let model: LMSModel
    let label: String
    var strong = false
    let pick: (UUID) -> Void
    @ViewBuilder var more: () -> More

    var body: some View {
        Menu {
            Section(String(localized: .lmsAddTo)) {
                ForEach(model.targets, id: \.id) { course in
                    Button {
                        pick(course.id)
                    } label: {
                        Text(course.title)
                    }
                }
            }
            more()
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(label)
                Image(systemName: "chevron.down").font(Theme.Glyph.small).accessibilityHidden(true)
            }
        }
        .menuStyle(.button).buttonStyle(.secondary(strong: strong)).menuIndicator(.hidden)
        .fixedSize()
    }
}

extension TargetCourseMenu where More == EmptyView {
    init(model: LMSModel, label: String, strong: Bool = false, pick: @escaping (UUID) -> Void) {
        self.init(model: model, label: label, strong: strong, pick: pick, more: { EmptyView() })
    }
}
