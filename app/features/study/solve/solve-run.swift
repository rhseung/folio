import FolioDomain
import SwiftUI

struct SolveRun: View {
    @Bindable var model: SolveModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if let record = model.current, let course = model.course {
                header(record)
                Theme.Palette.lineSoft.frame(height: 1)
                let split = width >= Theme.Size.solveSplit
                let layout = split ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    problemPane(record)
                    if let side = model.side {
                        divider(split)
                        sidePane(side, course: course)
                    } else if model.answersBeside {
                        divider(split)
                        ScrollView {
                            SolveAnswer(model: model, problem: record.problem).padding(Theme.Space.xl)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .id(model.index)
                Theme.Palette.lineSoft.frame(height: 1)
                footer
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .frame(
            minWidth: Theme.Size.sheetWindowMin.width, idealWidth: Theme.Size.sheetWindow.width,
            minHeight: Theme.Size.sheetWindowMin.height, idealHeight: Theme.Size.sheetWindow.height
        )
        .background(Theme.Palette.card)
        .foregroundStyle(Theme.Palette.text)
        .font(Theme.Typeface.body)
        .task(id: model.mockDeadline) {
            guard let deadline = model.mockDeadline else { return }
            try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
            if !Task.isCancelled, model.phase == .solving { model.submitMock() }
        }
    }

    func divider(_ split: Bool) -> some View {
        Theme.Palette.lineSoft.frame(width: split ? 1 : nil, height: split ? nil : 1)
    }

    func header(_ record: CourseStudy.ProblemRecord) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(model.title(record)).font(Theme.Typeface.columnTitle).lineLimit(1)
                Text(model.subtitle(record)).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.m)
            if let deadline = model.mockDeadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(
                        Duration.seconds(max(deadline.timeIntervalSince(context.date), 0)).formatted(.time(pattern: .minuteSecond)),
                        systemImage: "timer"
                    )
                    .monospacedDigit().chip()
                }
            }
            Button(.commonClose) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    func problemPane(_ record: CourseStudy.ProblemRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                StudyText(text: record.problem.text).textSelection(.enabled)
                if let page = model.problemPage {
                    Button(String(localized: .solveProblemPage(page.page ?? 1)), systemImage: "doc.text") { model.show(page) }
                        .buttonStyle(.ghost)
                }
                if !model.answersBeside {
                    SolveAnswer(model: model, problem: record.problem)
                }
                if model.grading { ProgressView().controlSize(.small) }
                if let failure = model.failure {
                    Text(failure).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.warning)
                }
                if let graded = model.graded { SolveVerdict(model: model, graded: graded) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func sidePane(_ side: SolveModel.SidePage, course: LoadedCourse) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    model.side = nil
                } label: {
                    Image(systemName: "xmark").accessibilityLabel(Text(.commonClose))
                }
                .buttonStyle(.ghost).help(Text(.commonClose))
            }
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
            // PDF 뷰는 처음 받은 문서를 계속 쓰므로 자료가 바뀌면 새 뷰를 만든다.
            FileView(
                workspace: model.workspace, course: course, material: side.material, requestedPage: .constant(side.page),
                remembersPage: false
            )
            .id(side)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var footer: some View {
        HStack(spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(Array(model.steps.enumerated()), id: \.offset) { i, verdict in
                    Capsule()
                        .fill(i == model.index ? accent.color : verdict?.tone.foreground ?? Theme.Palette.fill)
                        .frame(width: Theme.Size.solveStep.width, height: Theme.Size.solveStep.height)
                }
            }
            .overflowFade(.horizontal)
            Spacer(minLength: Theme.Space.m)
            if model.isMock {
                Button(.solveBack) { model.back() }.disabled(model.index == 0)
                if model.isLast {
                    Button(.solveSubmit) { model.submitMock() }.buttonStyle(.prominent).keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.grading)
                } else {
                    Button(.solveNext) { model.next() }.buttonStyle(.prominent).keyboardShortcut(.rightArrow, modifiers: .command)
                }
            } else if model.graded == nil {
                Button(.solveSkip) { model.next() }.disabled(model.grading)
                Button(.solveGrade) { model.grade() }.buttonStyle(.prominent).keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canGrade)
            } else {
                Button(model.isLast ? .solveFinish : .solveNext) { model.next() }.buttonStyle(.prominent)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.m)
    }
}
