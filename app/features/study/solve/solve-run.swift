import FolioDomain
import SwiftUI

struct SolveRun: View {
    @Bindable var model: SolveModel
    @Environment(\.goBack) private var goBack
    @Environment(\.openLink) private var openLink
    @Environment(\.accent) private var accent
    @State private var width: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if let record = model.current {
                header(record)
                Theme.Palette.lineSoft.frame(height: 1)
                let split = width >= Theme.Size.solveSplit
                let layout = split ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    problemPane(record)
                        .overlay { if model.isPaused { paused } }
                    if model.answersBeside {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.card)
        .foregroundStyle(Theme.Palette.text)
        .font(Theme.Typeface.body)
        .task(id: model.runningDeadline) {
            guard let deadline = model.runningDeadline else { return }
            try? await Task.sleep(for: .seconds(max(deadline.timeIntervalSinceNow, 0)))
            if !Task.isCancelled, model.phase == .solving { model.submitMock() }
        }
    }

    // 멈춘 동안에는 문제를 가린다. 시계만 세우고 문제를 계속 볼 수 있으면 멈춤이 시간을 늘리는 길이 된다.
    var paused: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "pause.circle").font(Theme.Glyph.large).foregroundStyle(Theme.Palette.textTertiary)
                .accessibilityHidden(true)
            Text(.solvePausedTitle).font(Theme.Typeface.columnTitle)
            Button(.solveResumeMock, systemImage: "play.fill") { model.togglePause() }.buttonStyle(.prominent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.card)
    }

    func divider(_ split: Bool) -> some View {
        Theme.Palette.lineSoft.frame(width: split ? 1 : nil, height: split ? nil : 1)
    }

    func header(_ record: CourseStudy.ProblemRecord) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                StudyText(text: model.title(record), look: .title).font(Theme.Typeface.columnTitle).lineLimit(1)
                StudyText(text: model.subtitle(record), look: .title).font(Theme.Typeface.caption).foregroundStyle(
                    Theme.Palette.textTertiary
                ).lineLimit(1)
            }
            Spacer(minLength: Theme.Space.m)
            if model.mockDeadline != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Label(
                        Duration.seconds(model.remaining(at: context.date)).formatted(.time(pattern: .minuteSecond)),
                        systemImage: model.isPaused ? "pause.fill" : "timer"
                    )
                    .monospacedDigit().chip()
                }
                Button(model.isPaused ? .solveResumeMock : .solvePause, systemImage: model.isPaused ? "play.fill" : "pause.fill") {
                    model.togglePause()
                }
                .buttonStyle(.secondary)
            }
            Button(.commonClose) { model.close(goBack, openLink) }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    func problemPane(_ record: CourseStudy.ProblemRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                StudyText(text: record.problem.text).textSelection(.enabled)
                if let page = model.problemPage {
                    Button(String(localized: .solveProblemPage(page.page ?? 1)), systemImage: "doc.text") { model.open(page, openLink) }
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
            // 칸 전체로 늘이면 넓은 창에서 문제 줄과 답 칸이 읽기 어려울 만큼 길어진다.
            .frame(maxWidth: Theme.Size.readingColumn, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(Theme.Space.xl)
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
                Button(.solveBack) { model.back() }.disabled(model.index == 0 || model.isPaused)
                Button(model.isLast ? .solveSubmit : .solveNext) { model.go() }.buttonStyle(.prominent).shortcut(.solveGo)
                    .disabled(model.grading || model.isPaused)
            } else if model.graded == nil {
                Button(.solveSkip) { model.next() }.disabled(model.grading)
                Button(.solveGrade) { model.go() }.buttonStyle(.prominent).shortcut(.solveGo)
                    .disabled(!model.canGrade)
            } else {
                Button(model.isLast ? .solveFinish : .solveNext) { model.go() }.buttonStyle(.prominent).shortcut(.solveGo)
            }
        }
        .controlSize(.large)
        .padding(.leading, Theme.Space.xl)
        // 창의 오른쪽 아래에는 Claude 단추가 떠 있다. 그 자리를 비워야 채점과 내기 단추가 가려지지 않는다.
        .padding(.trailing, Theme.Size.fab + Theme.Space.l * 2)
        .padding(.vertical, Theme.Space.m)
    }
}
