import Algorithms
import FolioActions
import FolioDomain
import Foundation
import Observation

@MainActor @Observable
final class ProfileModel {
    let workspace: Workspace
    var email = ""
    // 초안을 transcript에서 채우기 전에 저장하면 저장된 메일이 지워진다.
    private var loaded = false

    init(workspace: Workspace) { self.workspace = workspace }

    var rule: GraduationRule { workspace.transcript.graduation }

    var codeOptions: [PickOption<UUID>] {
        workspace.catalog.codes.sorted { ($0.prefix, $0.program) < ($1.prefix, $1.program) }
            .map { PickOption(id: $0.id, title: "\($0.prefix) \($0.department)", detail: $0.program) }
    }

    var addableOptions: [PickOption<UUID>] { codeOptions.filter { o in !rule.programs.contains { $0.codeId == o.id } } }

    func update(_ change: (inout GraduationRule) -> Void) {
        var r = rule
        change(&r)
        guard r != rule else { return }
        let old = rule
        workspace.run(
            GraduationSet(
                totalCredits: .changed(old.totalCredits, r.totalCredits), minGPA: .changed(old.minGPA, r.minGPA),
                admissionYear: .changed(old.admissionYear, r.admissionYear), email: .changed(old.email, r.email),
                programs: .changed(old.programs, r.programs)))
    }

    func addProgram(_ codeId: UUID) {
        update { $0.programs.append(.init(codeId: codeId, kind: $0.programs.contains { $0.kind == .major } ? .doubleMajor : .major)) }
    }

    func load() {
        email = rule.email
        loaded = true
    }

    func saveEmail() {
        guard loaded else { return }
        let e = email.trimmingCharacters(in: .whitespaces)
        guard e != rule.email else { return }
        update { $0.email = e }
    }
}
