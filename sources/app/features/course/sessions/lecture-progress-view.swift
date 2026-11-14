import FolioDomain
import SwiftUI

struct LectureProgressBlock: View {
    @State private var model: LectureProgressModel
    @Environment(\.openLink) private var openLink
    let close: () -> Void

    init(workspace: Workspace, course: UUID, material: UUID, close: @escaping () -> Void = {}) {
        _model = State(initialValue: LectureProgressModel(workspace: workspace, course: course, material: material))
        self.close = close
    }

    var body: some View {
        let rows = model.rows
        let unranged = model.unranged
        Block(String(localized: .materialsProgressTitle), note: model.summary) {
            Card {
                if rows.isEmpty { CardRow(last: unranged == nil) { EmptyLine(String(localized: .materialsProgressEmpty)) } }
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    CardRow(last: i == rows.count - 1 && unranged == nil) {
                        Text(row.pages).monospacedDigit().frame(width: 72, alignment: .leading)
                        if row.classes.isEmpty {
                            Text(.materialsProgressNotYet).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                        } else {
                            HStack(spacing: Theme.Space.xs) {
                                ForEach(Array(row.classes.enumerated()), id: \.element.id) { i, c in
                                    if i > 0 { Text("·").foregroundStyle(Theme.Palette.textTertiary) }
                                    Button(c.day) {
                                        openLink(c.link, course: model.courseId)
                                        close()
                                    }
                                    .buttonStyle(.pointing(.plain))
                                    .help(Text(.materialsProgressOpenClass(c.day)))
                                }
                            }
                            .lineLimit(1)
                        }
                        Spacer(minLength: Theme.Space.s)
                    }
                }
                if let unranged {
                    CardRow(last: true) {
                        Text(unranged).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
        }
        .task { await model.load() }
    }
}
