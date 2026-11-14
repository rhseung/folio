import FolioActions
import SwiftUI

extension Workspace {
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
