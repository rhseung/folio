import FolioDomain
import SwiftUI

struct CourseGradesView: View {
    @State private var model: CourseGradesModel
    let course: LoadedCourse
    @State private var editingPolicy = false

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: CourseGradesModel(workspace: workspace, course: course.id))
        self.course = course
    }

    var body: some View {
        let file = course.file
        let result = model.result(file)
        let components = model.components(file)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: String(localized: .courseGradesTitle), subtitle: model.subtitle(file))
                Spacer()
                Button(.courseGradesPolicy) { editingPolicy = true }.buttonStyle(.pointing(.bordered))
                    .help(Text(.courseGradesPolicyHelp))
            }

            ScorePanel(result: result, target: $model.target, relative: model.relative(file))
                .sensitive(.block)
                .contextMenu { Button(.courseGradesPolicyEdit) { editingPolicy = true } }

            Block(
                title: String(localized: .courseGradesComponents), note: model.componentsNote(file),
                trailing: {
                    Button(.courseGradesAddComponent) { model.addComponent(file) }
                        .buttonStyle(.ghost)
                }
            ) {
                let lines = model.lines(file)
                Card {
                    if lines.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .courseGradesNoComponents)) } }
                    ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                        let last = i == lines.count - 1
                        switch line {
                        case .group(let name, let weight, _):
                            CardRow(last: last) {
                                Text(name).font(Theme.Typeface.bodyStrong)
                                Spacer()
                                Text("\(weight.formatted())%").font(Theme.Typeface.caption).monospacedDigit()
                                    .foregroundStyle(Theme.Palette.textTertiary)
                                    .padding(.trailing, Self.addWidth + Theme.Space.m)
                            }
                        case .component(let c, let indented):
                            componentRow(
                                c, score: result.components.first { $0.componentId == c.id }, all: components,
                                indented: indented, last: last)
                        case .entry(let e, let indented):
                            Button {
                                model.editingEntry = e
                            } label: {
                                EntryRow(entry: e, indented: indented, last: last)
                            }
                            .buttonStyle(.pointing(.plain))
                            .contextMenu { ItemMenu(source: ScoreMenuSource(model: model, entry: e)) }
                        }
                    }
                }
                .sensitive(.block)
            }

            attendance(file)

            let late = model.latePolicy(file)
            if late != nil || !file.policy.notes.isEmpty {
                Block(String(localized: .courseGradesOtherRules), note: String(localized: .courseGradesOtherRulesNote)) {
                    Card {
                        if let late {
                            FormRow(label: String(localized: .courseGradesLateSubmission), last: file.policy.notes.isEmpty) {
                                Text(late).foregroundStyle(Theme.Palette.textSecondary).multilineTextAlignment(.trailing)
                            }
                        }
                        if !file.policy.notes.isEmpty {
                            Text(file.policy.notes).lineSpacing(3).textSelection(.enabled)
                                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .contextMenu { Button(.courseGradesPolicyEdit) { editingPolicy = true } }
                }
            }
        }
        .confirming($model.pending)
        .sheet(item: $model.editingEntry) { ScoreEntrySheet(workspace: model.workspace, course: course, entry: $0) }
        .sheet(item: $model.editingComponent) { ComponentSheet(workspace: model.workspace, course: course, component: $0) }
        .sheet(isPresented: $editingPolicy) { PolicySheet(workspace: model.workspace, course: course) }
    }

    static let meterWidth: CGFloat = 88
    static let ratioWidth: CGFloat = 48
    static let weightWidth: CGFloat = 56
    static let addWidth: CGFloat = 20

    func componentRow(
        _ c: GradeComponent, score: GradeCalculator.ComponentResult?, all components: [GradeComponent],
        indented: Bool, last: Bool
    ) -> some View {
        let i = components.firstIndex { $0.id == c.id } ?? 0
        let ratio = score?.ratio
        let canAdd = model.canAdd(c)
        let add = { model.addScore(c) }
        return CardRow(last: last) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(c.name).font(Theme.Typeface.bodyStrong).lineLimit(2)
                Text(model.componentDetail(c, in: course.file))
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            .padding(.leading, indented ? Theme.Space.l : 0)
            Spacer(minLength: Theme.Space.m)
            Meter(value: ratio ?? 0, height: 6).frame(width: Self.meterWidth)
            Text(CourseGradesModel.ratioText(ratio))
                .font(Theme.Typeface.figureSmall)
                .foregroundStyle(ratio == nil ? Theme.Palette.textTertiary : Theme.Palette.text)
                .frame(width: Self.ratioWidth, alignment: .trailing)
            Chip("\(c.weight.formatted())%", tone: .accent).monospacedDigit().frame(width: Self.weightWidth, alignment: .trailing)
            Button(action: add) { Image(systemName: "plus") }
                .buttonStyle(.ghost)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: Self.addWidth)
                .opacity(canAdd ? 1 : 0)
                .disabled(!canAdd)
                .help(Text(.courseGradesAddScoreTo(c.name)))
        }
        // Button으로 두면 안의 추가 버튼이 클릭을 받지 못한다.
        .opens { model.editingComponent = c }
        .help(Text(.courseGradesEditComponentHelp(c.name)))
        .contextMenu {
            ItemMenu(source: ComponentMenuSource(model: model, component: c, addsScore: canAdd, index: i, count: components.count))
        }
    }

    func attendance(_ file: CourseFile) -> some View {
        let a = model.attendance(file)
        let next = model.nextText(a)
        return Block(String(localized: .courseGradesAttendance)) {
            Card {
                FormRow(
                    label: String(localized: .courseGradesAbsences), detail: a.detail, last: a.ratio == nil && a.cap == nil && next == nil
                ) {
                    Text(.courseGradesAbsenceCount(a.absences)).font(Theme.Typeface.bodyStrong).monospacedDigit()
                }
                if let ratio = a.ratio {
                    FormRow(label: String(localized: .courseGradesMinAttendance), last: a.cap == nil && next == nil) {
                        Text(ratio.percent).monospacedDigit()
                    }
                }
                if let cap = a.cap {
                    FormRow(label: String(localized: .courseGradesMaxGrade), last: next == nil) {
                        Chip(model.symbol(cap.maxGrade), tone: .danger)
                    }
                }
                if let next {
                    FormRow(label: String(localized: .courseGradesUntilNextCap), last: true) {
                        Text(next).foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
                    }
                }
            }
            .contextMenu { Button(.courseGradesPolicyEdit) { editingPolicy = true } }
        }
    }
}

private struct EntryRow: View {
    let entry: ScoreEntry
    let indented: Bool
    let last: Bool

    var body: some View {
        CardRow(last: last) {
            Text(entry.title.isEmpty ? String(localized: .courseGradesScore) : entry.title).foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
                .padding(.leading, Theme.Space.l + (indented ? Theme.Space.l : 0))
            if entry.excused { Chip(String(localized: .courseGradesExcused)) }
            Spacer(minLength: Theme.Space.s)
            if let mean = entry.mean {
                Text(entry.stdDev.flatMap { $0 > 0 ? ((entry.score - mean) / $0).sigmas : nil } ?? (entry.score - mean).points)
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            Text(
                "\(Text(entry.score.formatted()).foregroundStyle(entry.excused ? Theme.Palette.textTertiary : Theme.Palette.text))\(Text(" / \(entry.max.formatted())").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary))"
            )
            .monospacedDigit()
            Color.clear.frame(width: CourseGradesView.weightWidth + Theme.Space.m + CourseGradesView.addWidth, height: 0)
        }
        .contentShape(.rect)
    }
}
