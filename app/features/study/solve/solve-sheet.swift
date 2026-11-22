import FolioDomain
import SwiftUI
import UniformTypeIdentifiers

// 필기와 모의시험의 문제집 페이지다. 문제집을 만들어 보내고, 손으로 푼 PDF를 받아 한 번에 채점한다(#577).
struct SolveSheet: View {
    @Bindable var model: SolveSheetModel
    let onClose: (GoBackAction, OpenLinkAction) -> Void
    @Environment(\.goBack) private var goBack
    @Environment(\.openLink) private var openLink
    @State private var choosing = false
    @State private var dropping = false
    @State private var opened: UUID?

    var body: some View {
        Page(maxWidth: Theme.Size.solveSheet) {
            header
            if model.isMock { timer }
            Block(String(localized: .solveCollection), note: CourseFolder.study.rawValue) { Card { collectionRow } }
            Block(String(localized: .solveSheetSubmitted)) { submission }
            if model.isGraded { grades } else { problems }
            if model.isGraded { results }
        }
        .background(Theme.Palette.page)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { model.submit(url) }
        }
    }

    var header: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            PageHeader(title: String(localized: model.isMock ? .solveModeMock : .solveSheetTitle), subtitle: model.subtitle)
            Spacer(minLength: Theme.Space.m)
            Button(.commonClose) { onClose(goBack, openLink) }.keyboardShortcut(.cancelAction)
        }
    }

    // 모의시험은 문제집이 생긴 때부터 잰다. 시간이 끝나도 낸 PDF로 채점하므로 내기를 막지 않는다.
    var timer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: Theme.Space.m) {
                    Label(
                        Duration.seconds(model.remaining(at: context.date)).formatted(.time(pattern: .minuteSecond)),
                        systemImage: model.isPaused ? "pause.fill" : "timer"
                    )
                    .font(Theme.Typeface.figureMedium).monospacedDigit()
                    if model.timeIsUp(at: context.date) {
                        Text(.solveSheetTimeUp).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.warning)
                    }
                    Spacer(minLength: Theme.Space.m)
                    Button(model.isPaused ? .solveResumeMock : .solvePause, systemImage: model.isPaused ? "play.fill" : "pause.fill") {
                        model.togglePause()
                    }
                    .buttonStyle(.secondary).disabled(model.started == nil || model.isGraded)
                }
                ProgressBar(value: model.elapsedFraction(at: context.date))
            }
        }
    }

    var collectionRow: some View {
        CardRow(last: true) {
            LineIcon(symbol: "doc.text")
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.solveCollection).lineLimit(1)
                Text(model.collectionDetail).font(Theme.Typeface.caption)
                    .foregroundStyle(
                        model.collectionFailure != nil || model.asksToReplaceCollection ? Theme.Palette.warning : Theme.Palette.textTertiary
                    )
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.Space.m)
            if model.asksToReplaceCollection {
                Button(.solveCollectionReplace) { model.replaceCollection() }.buttonStyle(.secondary)
            } else if let collection = model.collection, !model.buildingCollection {
                Button(.commonOpen) { model.openCollection(solutions: false, openLink) }.buttonStyle(.secondary)
                if model.isGraded {
                    Button(.solveCollectionSolutions) { model.openCollection(solutions: true, openLink) }.buttonStyle(.secondary)
                }
                ShareLink(item: collection.url) { Label(String(localized: .solveCollectionShare), systemImage: "square.and.arrow.up") }
                    .buttonStyle(.secondary)
            } else {
                Button(model.collectionTitle) { Task { await model.buildCollection() } }
                    .buttonStyle(.prominent).disabled(model.buildingCollection)
            }
        }
    }

    // 끌어 놓기는 포인터와 iPad의 손가락 끌기가 함께 쓰고, 고르기 단추가 같은 일을 한다.
    var submission: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                LineIcon(symbol: "paperclip")
                Text(model.submittedLine ?? String(localized: .solveSheetDrop))
                    .foregroundStyle(model.submitted == nil ? Theme.Palette.textTertiary : Theme.Palette.text).lineLimit(1)
                Spacer(minLength: Theme.Space.m)
                Button(model.submitted == nil ? .solveSheetChoose : .solveSheetReplace) { choosing = true }.buttonStyle(.secondary)
            }
            .padding(Theme.Inset.panel)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.rowHeight, alignment: .leading)
            .background(dropping ? Theme.Palette.fill : Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(
                    Theme.Palette.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.submit(url)
                return true
            } isTargeted: {
                dropping = $0
            }
            HStack(spacing: Theme.Space.m) {
                if let detail = model.gradeDetail {
                    Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.warning)
                }
                Spacer(minLength: Theme.Space.m)
                if model.grading { ProgressView().controlSize(.small) }
                if !model.isGraded || !model.ungraded.isEmpty {
                    Button(model.gradeTitle) { Task { await model.grade() } }.buttonStyle(.prominent).disabled(!model.canGrade)
                }
            }
        }
    }

    var problems: some View {
        Block(String(localized: .solveSheetProblems), note: String(localized: .problemsCount(model.rows.count))) {
            Card {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                    CardRow(last: i == model.rows.count - 1) {
                        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                            StudyText(text: row.title, look: .title).lineLimit(1)
                            Text(model.detail(row)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    var grades: some View {
        Block(String(localized: .solveSheetGrades), note: model.gradedNote) {
            Card {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.snappy) { opened = opened == row.id ? nil : row.id }
                        } label: {
                            CardRow(last: i == model.rows.count - 1 && opened != row.id) {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    StudyText(text: row.title, look: .title).lineLimit(1)
                                    Text(model.detail(row)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: Theme.Space.m)
                                if let graded = row.graded {
                                    Badge(graded.verdict.label, tone: graded.verdict.tone)
                                } else {
                                    Badge(String(localized: .solveSheetNotGraded), tone: .warning)
                                }
                                LineIcon(symbol: opened == row.id ? "chevron.up" : "chevron.down").foregroundStyle(
                                    Theme.Palette.textTertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.pointing(.plain))
                        if opened == row.id, let graded = row.graded { verdict(row, graded) }
                    }
                }
            }
        }
    }

    func verdict(_ row: SolveSheetModel.Row, _ graded: SolveModel.Graded) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            // 채점이 틀렸으면 고친다. 고친 판정이 최종이다.
            SegmentedControl(
                selection: Binding(get: { graded.verdict }, set: { model.override(row.id, $0) }),
                options: Verdict.allCases.map { ($0, $0.label) }, size: .small)
            ForEach(Array(graded.feedback.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(verbatim: "•").foregroundStyle(Theme.Palette.textTertiary)
                    StudyText(text: line, look: .prose)
                }
            }
            if graded.verdict.isMistake {
                Caption(String(localized: .solveReason))
                SegmentedControl(
                    selection: Binding(get: { graded.reason }, set: { if let r = $0 { model.setReason(row.id, r) } }),
                    options: model.reasons.map { (Optional($0), $0.label) }, layout: .flow)
            }
        }
        .padding(Theme.Inset.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.page)
    }

    var results: some View {
        let units = model.unitResults()
        let reasons = model.reasonSummary
        return VStack(alignment: .leading, spacing: Theme.Space.section) {
            if !units.isEmpty {
                Block(String(localized: .solveResultUnits), note: model.resultLine) {
                    Card {
                        ForEach(Array(units.enumerated()), id: \.element.unit.id) { i, row in
                            CardRow(last: i == units.count - 1) {
                                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                                    StudyText(text: row.unit.title, look: .title).lineLimit(1)
                                    Text(row.line).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                }
                                Spacer(minLength: Theme.Space.m)
                                ReadinessBadge(readiness: row.readiness)
                            }
                        }
                    }
                }
            }
            if !reasons.isEmpty {
                Block(String(localized: .solveResultReasons)) {
                    Card {
                        ForEach(Array(reasons.enumerated()), id: \.element.reason) { i, row in
                            CardRow(last: i == reasons.count - 1) {
                                Text(row.reason.label)
                                Spacer(minLength: Theme.Space.m)
                                Text(verbatim: "\(row.count)").monospacedDigit().foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }
                }
            }
            HStack(spacing: Theme.Space.s) {
                Button(.solvePlan) { openLink(.course(model.course, page: .units), course: model.course) }
                Spacer()
                Button(.commonDone) { onClose(goBack, openLink) }.buttonStyle(.prominent)
            }
        }
    }
}
