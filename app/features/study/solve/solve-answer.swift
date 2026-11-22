import FolioDomain
import SwiftUI

struct SolveAnswer: View {
    @Bindable var model: SolveModel
    let problem: Problem
    @Environment(\.accent) private var accent
    @State private var preview = false
    @State private var attaching = false

    var body: some View {
        if model.handwriting {
            handwriting
        } else {
            switch problem.format {
            case .trueFalse, .choice: choices
            case .short: short
            case .written: written
            }
        }
    }

    // 참거짓은 T와 F, 객관식은 번호 키로 고른다. 수식 키 없이 누르므로 글을 쓰는 칸이 없는 형식에만 단다. 이유 한 줄은 고른 뒤에
    // 열린다. 그때는 단추가 꺼져 있어 칸에 치는 T와 F가 단추를 누르지 않는다.
    var choices: some View {
        let options = model.options(of: problem)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                let tone = model.tone(of: option, in: problem)
                let chosen = model.answer == option
                Button {
                    model.choose(option)
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        KeyCap(key(i))
                        StudyText(text: problem.format == .trueFalse ? label(i) : option)
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Inset.listRow)
                    .frame(minHeight: Theme.Size.bigButton)
                    .background(tone?.fill ?? (chosen ? accent.tint : Theme.Palette.fill), in: .rect(cornerRadius: Theme.Radius.control))
                    .foregroundStyle(tone?.foreground ?? Theme.Palette.text)
                    .contentShape(.rect)
                }
                .buttonStyle(.pointing(.plain))
                .shortcut(command(i).id, at: command(i).index)
                .disabled(model.graded != nil || model.grading)
            }
            if model.asksWhy {
                TextField(String(localized: .solveWhyPrompt), text: $model.why)
                    .pill(width: nil, alignment: .leading)
                    .frame(minHeight: Theme.Size.solveCell)
            }
        }
    }

    func command(_ i: Int) -> (id: ShortcutID, index: Int) {
        problem.format == .trueFalse ? (i == 0 ? .solveTrue : .solveFalse, 0) : (.solveChoice, i)
    }

    func key(_ i: Int) -> String {
        let c = command(i)
        let bindings = ShortcutTable.shortcut(c.id).bindings
        guard bindings.indices.contains(c.index), case .character(let ch) = bindings[c.index].combo.key else { return "" }
        return String(ch).uppercased()
    }

    func label(_ i: Int) -> String { String(localized: i == 0 ? .solveTrue : .solveFalse) }

    var short: some View {
        TextField(String(localized: .solveShortPrompt), text: $model.answer)
            .pill(width: nil, alignment: .leading)
            .frame(minHeight: Theme.Size.solveCell)
            .onSubmit { if model.canGrade { model.grade() } }
            .disabled(model.graded != nil)
    }

    var written: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Caption(String(localized: .solveAnswer))
                Spacer()
                SegmentedControl(
                    selection: $preview, options: [(false, String(localized: .solveEdit)), (true, String(localized: .solvePreview))],
                    size: .small)
            }
            if preview {
                StudyText(text: model.answer).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Card(padding: Theme.Space.m) { GrowingTextEditor(text: $model.answer, room: nil) }
                    .disabled(model.graded != nil)
            }
        }
    }

    var handwriting: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Caption(String(localized: .solveAnswer))
                Spacer()
                if !model.images.isEmpty {
                    Button(.solveClearInk) { model.images = [] }.buttonStyle(.ghost).disabled(model.graded != nil)
                }
            }
            #if os(iOS)
            InkPad(images: $model.images)
                .frame(minHeight: Theme.Size.inkPad)
                .background(Theme.Palette.page, in: .rect(cornerRadius: Theme.Radius.control))
                .disabled(model.graded != nil)
            #else
            // Mac에는 펜이 없으므로 종이에 푼 답을 찍은 사진이나 PDF를 붙인다.
            Button {
                attaching = true
            } label: {
                Label(
                    model.images.isEmpty ? String(localized: .solveAttach) : String(localized: .solveAttached(model.images.count)),
                    systemImage: "photo.badge.plus"
                )
                .frame(maxWidth: .infinity, minHeight: Theme.Size.inkPad / 2)
                .background(Theme.Palette.fill, in: .rect(cornerRadius: Theme.Radius.control))
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            .disabled(model.graded != nil)
            .fileImporter(isPresented: $attaching, allowedContentTypes: AnswerImages.types, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { model.attach(urls) }
            }
            #endif
            Caption(String(localized: .solveInkNote))
            Card(padding: Theme.Space.m) { GrowingTextEditor(text: $model.answer, room: nil) }
                .disabled(model.graded != nil)
        }
    }
}
