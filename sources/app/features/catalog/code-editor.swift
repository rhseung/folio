import FolioDomain
import SwiftUI

struct CodeEditor: View {
    let model: CodesModel
    @Environment(\.openLink) private var openLink
    @Binding var code: CourseCode
    let programs: [String]
    let courses: [UUID]
    let remove: @MainActor () -> Void

    var body: some View {
        let records = model.courses(using: courses)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if !records.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Caption(String(localized: .codesUsedBy(records.count)))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(records) { c in
                                Button {
                                    openLink(.course(c.id), course: c.id)
                                } label: {
                                    HStack(spacing: Theme.Space.s) {
                                        CourseMark(model.workspace, c.id, inline: true)
                                        Text(c.title).lineLimit(1)
                                        Spacer(minLength: Theme.Space.s)
                                        Text(model.workspace.semester(of: c)?.title ?? "").font(Theme.Typeface.caption).foregroundStyle(
                                            Theme.Palette.textTertiary)
                                    }
                                    .padding(.vertical, Theme.Space.tight)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.pointing(.plain))
                                .help(Text(.commonOpenNamed(c.title)))
                            }
                        }
                    }
                    .overflowFade(.vertical)
                    .frame(maxHeight: 240)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.m, verticalSpacing: Theme.Space.s) {
                GridRow {
                    Text(.codesFieldPrefix)
                    TextField("EC", text: $code.prefix).pill(width: 64, alignment: .leading)  // strings: data, a code prefix
                }
                GridRow {
                    Text(.codesFieldDepartment)
                    TextField(String(localized: .codesFieldDepartmentExample), text: $code.department).pill(width: nil, alignment: .leading)
                }
                GridRow {
                    Text(.codesFieldProgram)
                    ChoiceMenu(selection: $code.program, options: programs.map { ($0, CodesModel.programTitle($0)) })
                }
                GridRow {
                    Text(.codesFieldSource)
                    TextField(String(localized: .codesFieldSourceExample), text: $code.source).pill(width: nil, alignment: .leading)
                }
            }
            HStack {
                Spacer()
                let refusal = model.removal(code.id)
                Button(.commonDelete, role: .destructive, action: remove).buttonStyle(.ghost).disabled(refusal != nil)
                    .help(refusal ?? String(localized: .codesRemoveHelp))
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 300)
    }
}
