import FolioDomain
import SwiftUI

// 과목을 고르는 "추가 ⌄"다. 강의실에 기억한 과목이 있으면 그 과목에 바로 받는 단추와 다른 과목을 고르는 메뉴로 나눈다.
// 메뉴를 길게 누르기 뒤에 숨기지 않고 단추 둘로 두어, 터치에서도 둘 다 한 번 눌러 쓴다.
struct TargetCourseMenu<More: View>: View {
    let model: LMSModel
    let label: String
    var remembered: (id: UUID, title: String)?
    var all = false
    var strong = false
    let pick: (UUID) -> Void
    @ViewBuilder var more: () -> More

    var body: some View {
        if let remembered {
            HStack(spacing: Theme.Space.xs) {
                Button {
                    pick(remembered.id)
                } label: {
                    Text(
                        all ? String(localized: .lmsAddAllToCourse(remembered.title)) : String(localized: .lmsAddToCourse(remembered.title))
                    )
                    .lineLimit(1)
                }
                .buttonStyle(.secondary(strong: strong))
                menu {
                    Image(systemName: "chevron.down").font(Theme.Glyph.small)
                        .accessibilityLabel(String(localized: .lmsOtherCourse))
                }
                .help(String(localized: .lmsOtherCourse))
            }
            .fixedSize()
        } else {
            menu {
                HStack(spacing: Theme.Space.xs) {
                    Text(label)
                    Image(systemName: "chevron.down").font(Theme.Glyph.small).accessibilityHidden(true)
                }
            }
        }
    }

    func menu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
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
            label()
        }
        .menuStyle(.button).buttonStyle(.secondary(strong: strong && remembered == nil, iconOnly: remembered != nil)).menuIndicator(.hidden)
        .fixedSize()
    }
}

extension TargetCourseMenu where More == EmptyView {
    init(
        model: LMSModel, label: String, remembered: (id: UUID, title: String)? = nil, strong: Bool = false,
        pick: @escaping (UUID) -> Void
    ) {
        self.init(model: model, label: label, remembered: remembered, strong: strong, pick: pick, more: { EmptyView() })
    }
}
