import FolioDomain
import SwiftUI

struct SolveRun: View {
    @Bindable var model: SolveModel
    @Environment(\.goBack) private var goBack
    @Environment(\.openLink) private var openLink
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            if let record = model.current {
                header(record)
                Theme.Palette.lineSoft.frame(height: 1)
                problemPane(record)
                    .id(model.index)
                Theme.Palette.lineSoft.frame(height: 1)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.card)
        .foregroundStyle(Theme.Palette.text)
        .font(Theme.Typeface.body)
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
            Button(.commonClose) { model.close(goBack, openLink) }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.l)
    }

    func problemPane(_ record: CourseStudy.ProblemRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                ProblemStatement(problem: record.problem, stems: model.stems(record), sheet: model.sheet(record)).textSelection(.enabled)
                if let page = model.problemPage {
                    Button(String(localized: .solveProblemPage(page.page ?? 1)), systemImage: "doc.text") { model.open(page, openLink) }
                        .buttonStyle(.ghost)
                }
                SolveAnswer(model: model, problem: record.problem)
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
            if model.graded == nil {
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
