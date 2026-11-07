import FolioDomain
import SwiftUI

/// A lecture file's pages by the classes that went through them, with the part no class has reached yet.
struct LectureProgressBlock: View {
    @State private var model: LectureProgressModel

    init(workspace: Workspace, course: UUID, material: UUID) {
        _model = State(initialValue: LectureProgressModel(workspace: workspace, course: course, material: material))
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
                        Text(row.classes ?? String(localized: .materialsProgressNotYet)).lineLimit(1)
                            .foregroundStyle(row.classes == nil ? Theme.Palette.textTertiary : Theme.Palette.text)
                        Spacer(minLength: Theme.Space.s)
                        if !row.confusing.isEmpty {
                            Chip(String(localized: .materialsProgressConfusing(row.confusing.map(String.init).joined(separator: ", "))), tone: .warning)
                        }
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
