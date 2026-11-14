import FolioDomain
import SwiftUI

struct ProfileCard: View {
    @State private var model: ProfileModel

    init(workspace: Workspace) {
        _model = State(initialValue: ProfileModel(workspace: workspace))
    }

    var body: some View {
        let rule = model.rule
        let options = model.codeOptions
        Card {
            FormRow(label: String(localized: .profileEmail)) {
                InlineField("name@gm.gist.ac.kr", text: $model.email)
            }
            FormRow(label: String(localized: .profileAdmissionYear)) {
                TextField(
                    String(localized: .profileAdmissionYearExample),
                    value: Binding(get: { rule.admissionYear }, set: { y in model.update { $0.admissionYear = y } }),
                    format: .number.grouping(.never)
                )
                .pill(width: 72)
            }
            // 같은 과정이 두 번 나열되면 충돌하므로 위치로 구분한다.
            ForEach(Array(rule.programs.enumerated()), id: \.offset) { i, p in
                FormRow(label: String(localized: .profileProgram(i + 1))) {
                    SearchSelect(
                        selection: Binding(get: { p.codeId }, set: { id in model.update { $0.programs[i].codeId = id } }), options: options)
                    ChoiceMenu(
                        selection: Binding(get: { p.kind }, set: { k in model.update { $0.programs[i].kind = k } }),
                        options: StudentProgram.Kind.allCases.map { ($0, $0.label) })
                    Button(.profileRemoveProgram, systemImage: "minus.circle") { model.update { $0.programs.remove(at: i) } }
                        .buttonStyle(.ghostIcon)
                }
                .contextMenu { Button(.profileRemoveProgramMenu, role: .destructive) { model.update { $0.programs.remove(at: i) } } }
            }
            CardRow(last: true) {
                SearchPicker(options: model.addableOptions, pick: { model.addProgram($0) }, prompt: String(localized: .profileCodeSearch)) {
                    Label(.profileAddProgram, systemImage: "plus")
                }
                Spacer()
            }
        }
        .onAppear { model.load() }
        // 저장할 때마다 transcript.json을 다시 쓰므로, 설정처럼 입력이 멈춘 뒤 저장한다.
        .task(id: model.email) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.saveEmail()
        }
    }
}
