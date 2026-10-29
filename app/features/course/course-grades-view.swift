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

            Block(title: String(localized: .courseGradesComponents), note: model.componentsNote(file), trailing: {
                Button(.courseGradesAddComponent) { model.addComponent(file) }
                    .buttonStyle(.ghost)
            }) {
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
                            componentRow(c, score: result.components.first { $0.componentId == c.id }, all: components,
                                         indented: indented, last: last)
                        case .entry(let e, let indented):
                            Button { model.editingEntry = e } label: { EntryRow(entry: e, indented: indented, last: last) }
                                .buttonStyle(.pointing(.plain))
                                .contextMenu {
                                    Button(.courseGradesEditEllipsis) { model.editingEntry = e }
                                    Button(e.excused ? .courseGradesInclude : .courseGradesExcuse) { model.setExcused(e, !e.excused) }
                                    Divider()
                                    Button(.courseGradesRemoveScoreEllipsis, role: .destructive) { model.deletingEntry = e }
                                }
                        }
                    }
                }
                .sensitive(.block)
            }

            attendance(file)

            let late = model.latePolicy(file)
            if late != nil || !file.policy.notes.isEmpty {
                // Only what the components and the policy can't express belongs here; it never enters the calculation.
                Block(String(localized: .courseGradesOtherRules), note: String(localized: .courseGradesOtherRulesNote)) {
                    Card {
                        if let late { FormRow(label: String(localized: .courseGradesLateSubmission), last: file.policy.notes.isEmpty) { Text(late).foregroundStyle(Theme.Palette.textSecondary).multilineTextAlignment(.trailing) } }
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
        .confirmationDialog(model.deletingComponent.map(CourseGradesModel.removeTitle) ?? "",
                            isPresented: Binding(get: { model.deletingComponent != nil }, set: { if !$0 { model.deletingComponent = nil } }),
                            presenting: model.deletingComponent) { c in
            Button(.commonDelete, role: .destructive) { model.remove(c) }
        } message: { c in
            if let message = CourseGradesModel.removeMessage(c, in: file) { Text(message) }
        }
        .confirmationDialog(model.deletingEntry.map(CourseGradesModel.removeTitle) ?? "",
                            isPresented: Binding(get: { model.deletingEntry != nil }, set: { if !$0 { model.deletingEntry = nil } }),
                            presenting: model.deletingEntry) { e in
            Button(.commonDelete, role: .destructive) { model.remove(e) }
        }
        .sheet(item: $model.editingEntry) { ScoreEntrySheet(workspace: model.workspace, course: course, entry: $0) }
        .sheet(item: $model.editingComponent) { ComponentSheet(workspace: model.workspace, course: course, component: $0) }
        .sheet(isPresented: $editingPolicy) { PolicySheet(workspace: model.workspace, course: course) }
    }

    /// The meter, percent, weight and add columns, fixed so they line up down the card; score rows end under the percent.
    static let meterWidth: CGFloat = 88
    static let ratioWidth: CGFloat = 48
    static let weightWidth: CGFloat = 56
    static let addWidth: CGFloat = 20

    func componentRow(_ c: GradeComponent, score: GradeCalculator.ComponentResult?, all components: [GradeComponent],
                      indented: Bool, last: Bool) -> some View {
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
        // Not a Button: the add button inside would never get its clicks.
        .opens { model.editingComponent = c }
        .help(Text(.courseGradesEditComponentHelp(c.name)))
        .contextMenu {
            Button(.courseGradesEditEllipsis) { model.editingComponent = c }
            if canAdd { Button(.courseGradesAddScoreEllipsis, action: add) }
            Divider()
            Button(.courseGradesMoveUp) { model.move(c.id, by: -1) }.disabled(i == 0)
            Button(.courseGradesMoveDown) { model.move(c.id, by: 1) }.disabled(i == components.count - 1)
            Divider()
            Button(.courseGradesRemoveComponentEllipsis, role: .destructive) { model.deletingComponent = c }
        }
    }

    func attendance(_ file: CourseFile) -> some View {
        let a = model.attendance(file)
        let next = model.nextText(a)
        return Block(String(localized: .courseGradesAttendance)) {
            Card {
                FormRow(label: String(localized: .courseGradesAbsences), detail: a.detail, last: a.ratio == nil && a.cap == nil && next == nil) {
                    Text(.courseGradesAbsenceCount(a.absences)).font(Theme.Typeface.bodyStrong).monospacedDigit()
                }
                if let ratio = a.ratio {
                    FormRow(label: String(localized: .courseGradesMinAttendance), last: a.cap == nil && next == nil) { Text(ratio.percent).monospacedDigit() }
                }
                if let cap = a.cap {
                    FormRow(label: String(localized: .courseGradesMaxGrade), last: next == nil) { Chip(model.symbol(cap.maxGrade), tone: .danger) }
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
            Text(entry.title.isEmpty ? String(localized: .courseGradesScore) : entry.title).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                .padding(.leading, Theme.Space.l + (indented ? Theme.Space.l : 0))
            if entry.excused { Chip(String(localized: .courseGradesExcused)) }
            Spacer(minLength: Theme.Space.s)
            if let mean = entry.mean {
                Text(entry.stdDev.flatMap { $0 > 0 ? ((entry.score - mean) / $0).sigmas : nil } ?? (entry.score - mean).points)
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
            }
            Text("\(Text(entry.score.formatted()).foregroundStyle(entry.excused ? Theme.Palette.textTertiary : Theme.Palette.text))\(Text(" / \(entry.max.formatted())").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary))")
                .monospacedDigit()
            Color.clear.frame(width: CourseGradesView.weightWidth + Theme.Space.m + CourseGradesView.addWidth, height: 0)
        }
        .contentShape(.rect)
    }
}

struct ScorePanel: View {
    @Environment(\.accent) private var accent
    let result: GradeCalculator.CourseScore
    @Binding var target: Double
    /// The A share of a relatively graded course. Its cutoffs aren't known, so it is aimed at by place against the
    /// mean, not by a score (docs/SPEC.md "목표 점수 역산").
    var relative: Double?

    var body: some View {
        let need = GradeCalculator.requiredAverage(for: target, given: result)
        VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
            HStack(alignment: .bottom, spacing: Theme.Space.section) {
                Figure(String(localized: .courseGradesSecured), result.secured.oneDecimal)
                Figure(String(localized: .courseGradesProjected), result.projected.map(\.oneDecimal) ?? "-", tint: accent.ink)
                Figure(String(localized: .courseGradesRemainingWeight), "\(Int(result.remainingWeight.rounded()))%")
                Spacer()
                if relative == nil {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Caption(String(localized: .courseGradesTargetScore))
                        TextField(String(localized: .courseGradesTarget), value: $target, format: .number).pill(width: 72)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(.courseGradesNeedTitle).font(Theme.Typeface.label).foregroundStyle(accent.ink)
                        Text(CourseGradesModel.needText(need))
                            .font(Theme.Typeface.figureMedium).foregroundStyle(accent.ink)
                    }
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                    .background(accent.tint, in: .rect(cornerRadius: Theme.Space.s))
                }
            }
            if let relative {
                // A relative grade is a place in the class, so the class curve replaces the 0-100 bar.
                StandingCurve(z: result.z, estimated: result.zEstimated, gap: result.meanGap, share: relative)
            } else {
                scoreBar
            }
        }
        .padding(.horizontal, Theme.Space.l + 4)
        .padding(.vertical, Theme.Space.l + 2)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineSoft))
    }

    var scoreBar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.fill)
                    if let p = result.projected { Capsule().fill(accent.color.opacity(Theme.Opacity.projected)).frame(width: w * min(p, 100) / 100) }
                    Capsule().fill(accent.color).frame(width: w * min(result.secured, 100) / 100)
                    Theme.Palette.text.frame(width: 2, height: 20).offset(x: w * min(target, 100) / 100 - 1)
                }
            }
            .frame(height: 12)
            // A legend with the bar's own marks, so each color says what it is; the scale ends sit under the bar's ends.
            HStack(spacing: Theme.Space.l) {
                Text("0").foregroundStyle(Theme.Palette.textTertiary)
                HStack(spacing: Theme.Space.tight) { Capsule().fill(accent.color).frame(width: 14, height: 6); Text(.courseGradesLegendSecured(result.secured.oneDecimal)) }
                if let p = result.projected {
                    HStack(spacing: Theme.Space.tight) { Capsule().fill(accent.color.opacity(Theme.Opacity.projected)).frame(width: 14, height: 6); Text(.courseGradesLegendProjected(p.oneDecimal)) }
                }
                HStack(spacing: Theme.Space.tight) { Theme.Palette.text.frame(width: 2, height: 12); Text(.courseGradesLegendTarget(target.formatted())) }
                Spacer()
                Text("100").foregroundStyle(Theme.Palette.textTertiary)
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

struct StandingCurve: View {
    @Environment(\.accent) private var accent
    let z: Double?
    /// The z leans on a spread borrowed from the course's other scores, as a score gave a mean but no standard deviation.
    var estimated = false
    /// Weighted gap from the class mean, all there is when no score has a standard deviation.
    var gap: Double?
    let share: Double

    /// z from -3 to 3: past that the curve is flat, and a mark beyond it is drawn at the edge.
    static let span = 3.0

    var body: some View {
        let cut = GradeCalculator.standing(z: 0, topGradeRatio: share).cutZ
        let s = z.map { GradeCalculator.standing(z: $0, topGradeRatio: share) }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                let x = { (t: Double) in w * (min(max(t, -Self.span), Self.span) + Self.span) / (2 * Self.span) }
                // The peak stops short of the top, leaving room for the mark's label over it.
                let y = { (t: Double) in h - (h - 26) * exp(-t * t / 2) }
                let top = Path { p in
                    for i in 0...120 {
                        let t = -Self.span + 2 * Self.span * Double(i) / 120
                        let point = CGPoint(x: x(t), y: y(t))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                let area = Path { p in
                    p.addPath(top)
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                let split = x(cut)
                ZStack(alignment: .topLeading) {
                    // Each side fades to clear toward the baseline; the A side is the stronger tint, so it reads as
                    // its own region without a hard block of color.
                    area.fill(LinearGradient(colors: [accent.color.opacity(0.22), accent.color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .mask(alignment: .leading) { Rectangle().frame(width: split) }
                    area.fill(LinearGradient(colors: [accent.color.opacity(0.6), accent.color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .mask(alignment: .trailing) { Rectangle().frame(width: max(w - split, 0)) }
                    top.stroke(accent.color.opacity(0.45), lineWidth: 1.5)
                        .mask(alignment: .leading) { Rectangle().frame(width: split) }
                    top.stroke(accent.color, lineWidth: 1.5)
                        .mask(alignment: .trailing) { Rectangle().frame(width: max(w - split, 0)) }
                    Path { p in p.move(to: CGPoint(x: x(cut), y: y(cut))); p.addLine(to: CGPoint(x: x(cut), y: h)) }
                        .stroke(Theme.Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Rectangle().fill(Theme.Palette.line).frame(width: w, height: 1).offset(y: h - 1)
                    if let s {
                        let mx = x(s.z), my = y(s.z)
                        // The rule runs from the label row at the top, so the label never sits on the curve however far out the mark is.
                        Path { p in p.move(to: CGPoint(x: mx, y: 18)); p.addLine(to: CGPoint(x: mx, y: h)) }
                            .stroke(Theme.Palette.text.opacity(0.7), lineWidth: 1.5)
                        Circle().fill(Theme.Palette.text).frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Theme.Palette.card, lineWidth: 2))
                            .offset(x: mx - 5, y: my - 5)
                        // The label sits on the side with room, so a place near either end stays inside the card.
                        HStack(spacing: 0) {
                            if mx > w * 0.7 { Spacer(minLength: 0) } else { Color.clear.frame(width: max(mx - 8, 0), height: 0) }
                            Text(String(localized: .courseGradesStandingMe(Int((s.above * 100).rounded()))) + (estimated ? String(localized: .courseGradesStandingEstimated) : ""))
                                .font(Theme.Typeface.label).foregroundStyle(Theme.Palette.text).fixedSize()
                            if mx > w * 0.7 { Color.clear.frame(width: max(w - mx - 8, 0), height: 0) } else { Spacer(minLength: 0) }
                        }
                        .frame(width: w)
                    }
                }
            }
            .frame(height: 104)
            GeometryReader { proxy in
                let w = proxy.size.width
                Text(.courseGradesStandingCut).fixedSize()
                    .position(x: min(max(w * (min(max(cut, -Self.span), Self.span) + Self.span) / (2 * Self.span), 24), w - 24), y: 7)
            }
            .frame(height: 14)
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            HStack(spacing: Theme.Space.l) {
                Text(.courseGradesStandingShares(Int((share * 100).rounded()), Int(((1 - share) * 100).rounded())))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                if let s {
                    Text(s.inTopGrade ? .courseGradesStandingInA : .courseGradesStandingOutA).fontWeight(.semibold)
                        .foregroundStyle(s.inTopGrade ? accent.ink : Theme.Palette.warning)
                } else if let gap {
                    // Without any standard deviation the place can't be drawn, but the side of the mean can still settle it.
                    let inA = GradeCalculator.inTopGrade(meanGap: gap, topGradeRatio: share)
                    Text(gap >= 0 ? .courseGradesStandingAboveMean : .courseGradesStandingBelowMean).foregroundStyle(Theme.Palette.textSecondary)
                    Text(inA.map { $0 ? .courseGradesStandingInA : .courseGradesStandingOutA } ?? .courseGradesStandingUnknown).fontWeight(inA == nil ? .regular : .semibold)
                        .foregroundStyle(inA == true ? accent.ink : inA == false ? Theme.Palette.warning : Theme.Palette.textTertiary)
                } else {
                    Text(.courseGradesStandingNoMean).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .font(Theme.Typeface.caption)
        }
        .help(Text(estimated ? .courseGradesStandingHelpEstimated : .courseGradesStandingHelp))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.map { String(localized: .courseGradesStandingAccessibility(Int(($0.above * 100).rounded()), String(localized: $0.inTopGrade ? .courseGradesStandingInA : .courseGradesStandingOutA))) }
            ?? gap.map { String(localized: $0 >= 0 ? .courseGradesStandingAboveMean : .courseGradesStandingBelowMean) } ?? String(localized: .courseGradesStandingUnknownPlace))
    }
}
