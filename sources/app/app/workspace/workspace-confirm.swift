import FolioActions
import SwiftUI

/// An action held until the user answers the question its declaration asks. A screen model keeps one in `pending` and
/// the view shows it with `.confirming(_:)`, so every screen asks the same words the CLI and the Claude panel ask.
struct PendingAction: Identifiable {
    let id = UUID()
    let question: String
    /// Set when the action would be refused: the user hears why instead of agreeing to something that then fails.
    let refusal: String?
    let button: LocalizedStringResource
    let role: ButtonRole?
    let perform: @MainActor () -> Void
}

extension Workspace {
    /// Runs the action now when its declaration asks nothing for it, and returns nil. Otherwise nothing runs yet and
    /// the returned value runs it once the user agrees. `done` gets what it wrote either way.
    func ask<A: Action>(
        _ action: A, button: LocalizedStringResource? = nil,
        then done: @escaping @MainActor (ActionContext) -> Void = { _ in }
    ) -> PendingAction? {
        guard let question = confirmation(action) else {
            if let ctx = run(action) { done(ctx) }
            return nil
        }
        let effect = A.spec.effect
        return PendingAction(
            question: question, refusal: refusal(action), button: button ?? Self.answer(effect),
            role: effect == .removes ? .destructive : nil
        ) { [weak self] in
            if let ctx = self?.run(action) { done(ctx) }
        }
    }

    private static func answer(_ effect: Effect) -> LocalizedStringResource {
        switch effect {
        case .removes: .commonDelete
        case .moves: .commonMove
        default: .commonOk
        }
    }
}

extension View {
    func confirming(_ pending: Binding<PendingAction?>) -> some View {
        let asking = pending.wrappedValue.flatMap { $0.refusal == nil ? $0 : nil }
        let refused = pending.wrappedValue?.refusal
        return confirmationDialog(
            asking?.question ?? "",
            isPresented: Binding(get: { asking != nil }, set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible, presenting: asking
        ) { p in
            Button(role: p.role) {
                p.perform()
            } label: {
                Text(p.button)
            }
        }
        .alert(Text(.commonRefused), isPresented: Binding(get: { refused != nil }, set: { if !$0 { pending.wrappedValue = nil } })) {
            Button(.commonOk, role: .cancel) {}
        } message: {
            Text(refused ?? "")
        }
    }
}
