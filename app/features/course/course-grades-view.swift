import FolioActions
import FolioDomain
import SwiftUI

/// Components, scores, rules, converted score, what's needed for a target, and attendance against the caps.
struct CourseGradesView: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    @State private var target = 90.0
    @State private var editingEntry: ScoreEntry?
    @State private var editingComponent: GradeComponent?
    @State private var editingPolicy = false
    @State private var deletingComponent: GradeComponent?
    @State private var deletingEntry: ScoreEntry?

    var body: some View {
        let file = course.file
        let result = GradeCalculator.score(components: file.components, entries: file.scores)
        let components = file.components.sorted { $0.order < $1.order }
        let total = components.map(\.weight).reduce(0, +)
        Page {
            HStack(alignment: .bottom) {
                PageHeader(title: "성적", subtitle: "\(file.course.gradingMode.label) · 평가 항목 \(components.count)개")
                Spacer()
                Button("성적 규칙") { editingPolicy = true }.buttonStyle(.pointing(.bordered))
                    .help("A 비율, 결석 상한, 지각과 그 밖의 규칙")
            }

            ScorePanel(result: result, target: $target, relative: file.course.gradingMode == .relative ? file.policy.effectiveTopGradeRatio : nil)
                .sensitive(.block)
                .contextMenu { Button("성적 규칙 편집…") { editingPolicy = true } }

            Block(title: "평가 항목", note: "비중 합계 \(total.formatted())%" + (components.isEmpty || total == 100 ? "" : " · 100%가 아닙니다"), trailing: {
                Button("항목 추가") {
                    let order = (components.map(\.order).max() ?? -1) + 1
                    editingComponent = GradeComponent(device: workspace.device, at: .now, name: "", weight: 10, order: order)
                }
                .buttonStyle(.ghost)
            }) {
                let lines = Self.lines(components, scores: file.scores)
                Card {
                    if lines.isEmpty { CardRow(last: true) { EmptyLine("평가 항목이 없습니다") } }
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
                            Button { editingEntry = e } label: { EntryRow(entry: e, indented: indented, last: last) }
                                .buttonStyle(.pointing(.plain))
                                .contextMenu {
                                    Button("편집…") { editingEntry = e }
                                    Button(e.excused ? "반영하기" : "면제하기") { setExcused(e, !e.excused) }
                                    Divider()
                                    Button("점수 삭제…", role: .destructive) { deletingEntry = e }
                                }
                        }
                    }
                }
                .sensitive(.block)
            }

            attendance(file)

            let late = file.policy.latePolicy.flatMap { $0.isEmpty ? nil : $0 }
            if late != nil || !file.policy.notes.isEmpty {
                // Only what the components and the policy can't express belongs here; it never enters the calculation.
                Block("그 밖의 규칙", note: "계산에는 쓰지 않습니다") {
                    Card {
                        if let late { FormRow(label: "지각 제출", last: file.policy.notes.isEmpty) { Text(late).foregroundStyle(Theme.Palette.textSecondary).multilineTextAlignment(.trailing) } }
                        if !file.policy.notes.isEmpty {
                            Text(file.policy.notes).lineSpacing(3).textSelection(.enabled)
                                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .contextMenu { Button("성적 규칙 편집…") { editingPolicy = true } }
                }
            }
        }
        .confirmationDialog(deletingComponent.map(ComponentSheet.deleteTitle) ?? "", isPresented: Binding(get: { deletingComponent != nil }, set: { if !$0 { deletingComponent = nil } }),
                            presenting: deletingComponent) { c in
            Button("삭제", role: .destructive) { ComponentSheet.delete(c, in: course, workspace: workspace) }
        } message: { ComponentSheet.deleteMessage($0, in: course) }
        .confirmationDialog(deletingEntry.map(ScoreEntrySheet.deleteTitle) ?? "", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }),
                            presenting: deletingEntry) { e in
            Button("삭제", role: .destructive) { ScoreEntrySheet.delete(e, in: course, workspace: workspace) }
        }
        .sheet(item: $editingEntry) { ScoreEntrySheet(course: course, entry: $0) }
        .sheet(item: $editingComponent) { ComponentSheet(course: course, component: $0) }
        .sheet(isPresented: $editingPolicy) { PolicySheet(course: course) }
    }

    /// The meter, percent, weight and add columns, fixed so they line up down the card; score rows end under the percent.
    static let meterWidth: CGFloat = 88
    static let ratioWidth: CGFloat = 48
    static let weightWidth: CGFloat = 56
    static let addWidth: CGFloat = 20

    enum Line: Identifiable {
        case group(String, weight: Double, first: UUID)
        case component(GradeComponent, indented: Bool)
        case entry(ScoreEntry, indented: Bool)

        var id: String {
            switch self {
            // Keyed by its first component: two runs apart can share a group name.
            case .group(_, _, let first): "group-\(first.uuidString)"
            case .component(let c, _): c.id.uuidString
            case .entry(let e, _): e.id.uuidString
            }
        }
    }

    /// Components in order, each followed by its scores; a run sharing a group sits under one heading with the run's weight.
    static func lines(_ components: [GradeComponent], scores: [ScoreEntry]) -> [Line] {
        var lines: [Line] = []
        for (i, c) in components.enumerated() {
            if let group = c.group, i == 0 || components[i - 1].group != group {
                let run = components[i...].prefix { $0.group == group }
                lines.append(.group(group, weight: run.map(\.weight).reduce(0, +), first: c.id))
            }
            lines.append(.component(c, indented: c.group != nil))
            lines += scores.filter { $0.componentId == c.id }.map { .entry($0, indented: c.group != nil) }
        }
        return lines
    }

    func componentRow(_ c: GradeComponent, score: GradeCalculator.ComponentResult?, all components: [GradeComponent],
                      indented: Bool, last: Bool) -> some View {
        let i = components.firstIndex { $0.id == c.id } ?? 0
        let ratio = score?.ratio
        let counted = course.file.scores.filter { $0.componentId == c.id && !$0.excused }.count
        let canAdd = workspace.can(ScoreAdd(course: course.id, component: c.id, score: 0, max: 100))
        let add = { editingEntry = ScoreEntry(device: workspace.device, at: .now, componentId: c.id, title: "", score: 0, max: 100) }
        return CardRow(last: last) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(c.name).font(Theme.Typeface.bodyStrong).lineLimit(2)
                Text(([c.aggregation.label, c.expectedCount.map { "\(counted)/\($0)회" }] as [String?]).compactMap { $0 }.joined(separator: " · "))
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            .padding(.leading, indented ? Theme.Space.l : 0)
            Spacer(minLength: Theme.Space.m)
            Meter(value: ratio ?? 0, height: 6).frame(width: Self.meterWidth)
            Text(ratio.map { "\(($0 * 100).formatted(.number.precision(.fractionLength(0))))%" } ?? "—")
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
                .help("\(c.name)에 점수 추가")
        }
        // Not a Button: the add button inside would never get its clicks.
        .opens { editingComponent = c }
        .help("눌러서 \(c.name) 편집")
        .contextMenu {
            Button("편집…") { editingComponent = c }
            if canAdd { Button("점수 추가…", action: add) }
            Divider()
            Button("앞으로") { move(c.id, by: -1) }.disabled(i == 0)
            Button("뒤로") { move(c.id, by: 1) }.disabled(i == components.count - 1)
            Divider()
            Button("항목 삭제…", role: .destructive) { deletingComponent = c }
        }
    }

    /// Absences against the caps; rows a course has no rule for stay out.
    func attendance(_ file: CourseFile) -> some View {
        let policy = file.policy
        let absences = GradeCalculator.absences(in: file.heldAttendance(at: .now), policy: policy)
        let cap = GradeCalculator.attendanceCap(absences: absences, policy: policy)
        let next = GradeCalculator.nextCap(absences: absences, policy: policy)
        let symbol = { (id: UUID) in workspace.catalog.grade(id)?.symbol ?? "?" }
        return Block("출석") {
            Card {
                FormRow(label: "결석", detail: [policy.attendanceCap.isEmpty ? "결석 상한 규칙이 없습니다" : capSummary(policy),
                                               policy.latesPerAbsence.map { "지각 \($0)회를 결석 1회로 셈" }]
                            .compactMap { $0 }.joined(separator: " · "),
                        last: policy.minAttendanceRatio == nil && cap == nil && next == nil) {
                    Text("\(absences)회").font(Theme.Typeface.bodyStrong).monospacedDigit()
                }
                if let ratio = policy.minAttendanceRatio {
                    FormRow(label: "최소 출석 비율", last: cap == nil && next == nil) { Text(ratio.percent).monospacedDigit() }
                }
                if let cap {
                    FormRow(label: "받을 수 있는 최대 성적", last: next == nil) { Chip(symbol(cap.maxGrade), tone: .danger) }
                }
                if let next {
                    FormRow(label: "다음 상한까지", last: true) {
                        Text("\(next.absences - absences)회 더 결석하면 최대 \(symbol(next.maxGrade))")
                            .foregroundStyle(Theme.Palette.textSecondary).monospacedDigit()
                    }
                }
            }
            .contextMenu { Button("성적 규칙 편집…") { editingPolicy = true } }
        }
    }

    func setExcused(_ entry: ScoreEntry, _ excused: Bool) {
        workspace.run(ScoreSet(course: course.id, score: entry.id, excused: .set(excused)))
    }

    /// `6회 B0 · 9회 F`
    func capSummary(_ policy: GradePolicy) -> String {
        policy.attendanceCap.sorted { $0.absences < $1.absences }
            .map { "\($0.absences)회 \(workspace.catalog.grade($0.maxGrade)?.symbol ?? "?")" }
            .joined(separator: " · ")
    }

    /// Swaps a component with its neighbor and renumbers all, since imported components may share one `order`.
    func move(_ id: UUID, by delta: Int) {
        workspace.run(ComponentMove(course: course.id, component: id, by: delta))
    }
}

/// A score under its component: the title, how far from the class mean, and the score, ending under the percent column.
private struct EntryRow: View {
    let entry: ScoreEntry
    let indented: Bool
    let last: Bool

    var body: some View {
        CardRow(last: last) {
            Text(entry.title.isEmpty ? "점수" : entry.title).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                .padding(.leading, Theme.Space.l + (indented ? Theme.Space.l : 0))
            if entry.excused { Chip("면제") }
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

/// Secured, projected and remaining weight, then the target and a 0-100 bar, or the class curve when graded relatively.
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
                Figure("확보 점수", result.secured.oneDecimal)
                Figure("예상 점수", result.projected.map(\.oneDecimal) ?? "-", tint: accent.ink)
                Figure("남은 비중", "\(Int(result.remainingWeight.rounded()))%")
                Spacer()
                if relative == nil {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Caption("목표 점수")
                        TextField("목표", value: $target, format: .number).pill(width: 72)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("남은 항목 평균").font(Theme.Typeface.label).foregroundStyle(accent.ink)
                        Text(need.map { $0 > 100 ? "만점으로도 부족" : $0 <= 0 ? "이미 확보" : "\($0.oneDecimal)% 필요" } ?? "남은 항목 없음")
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
                HStack(spacing: Theme.Space.tight) { Capsule().fill(accent.color).frame(width: 14, height: 6); Text("확보 \(result.secured.oneDecimal)") }
                if let p = result.projected {
                    HStack(spacing: Theme.Space.tight) { Capsule().fill(accent.color.opacity(Theme.Opacity.projected)).frame(width: 14, height: 6); Text("예상 \(p.oneDecimal) · 지금 득점률이 이어질 때") }
                }
                HStack(spacing: Theme.Space.tight) { Theme.Palette.text.frame(width: 2, height: 12); Text("목표 \(target.formatted())") }
                Spacer()
                Text("100").foregroundStyle(Theme.Palette.textTertiary)
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}

/// The class as a normal curve: the A share shaded past its cut, and the weighted z marked where it falls.
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
                            Text("나 · 상위 약 \(Int((s.above * 100).rounded()))%" + (estimated ? " · 추정" : ""))
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
                Text("A 경계").fixedSize()
                    .position(x: min(max(w * (min(max(cut, -Self.span), Self.span) + Self.span) / (2 * Self.span), 24), w - 24), y: 7)
            }
            .frame(height: 14)
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            HStack(spacing: Theme.Space.l) {
                Text("A \(Int((share * 100).rounded()))% · B와 C \(Int(((1 - share) * 100).rounded()))%")
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                if let s {
                    Text(s.inTopGrade ? "A 안" : "A 밖").fontWeight(.semibold)
                        .foregroundStyle(s.inTopGrade ? accent.ink : Theme.Palette.warning)
                } else if let gap {
                    // Without any standard deviation the place can't be drawn, but the side of the mean can still settle it.
                    let inA = GradeCalculator.inTopGrade(meanGap: gap, topGradeRatio: share)
                    Text(gap >= 0 ? "평균보다 위" : "평균보다 아래").foregroundStyle(Theme.Palette.textSecondary)
                    Text(inA.map { $0 ? "A 안" : "A 밖" } ?? "표준편차가 없어 A인지 모름").fontWeight(inA == nil ? .regular : .semibold)
                        .foregroundStyle(inA == true ? accent.ink : inA == false ? Theme.Palette.warning : Theme.Palette.textTertiary)
                } else {
                    Text("점수에 평균을 넣으면 위치를 표시합니다").foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .font(Theme.Typeface.caption)
        }
        .help(estimated ? "표준편차가 없는 점수는 이 과목의 다른 점수에 공개된 표준편차 비율로 추정했습니다. A 비율은 성적 규칙에서 바꿉니다."
                        : "공개된 평균과 표준편차로 추정한 반 안의 위치입니다. A 비율은 성적 규칙에서 바꿉니다.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.map { "반에서 상위 약 \(Int(($0.above * 100).rounded()))%, " + ($0.inTopGrade ? "A 안" : "A 밖") }
            ?? gap.map { $0 >= 0 ? "평균보다 위" : "평균보다 아래" } ?? "위치 모름")
    }
}

extension Aggregation {
    var label: String {
        switch self {
        case .sum: "합산"
        case .mean: "평균"
        case .single: "단일"
        case .dropLowest(let n): "최저 \(n)회 제외"
        case .bestOf(let n): "상위 \(n)회"
        }
    }
}
