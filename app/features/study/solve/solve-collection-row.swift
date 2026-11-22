import FolioDomain
import SwiftUI

// 필기로 풀 때 고른 문제로 문제집 PDF를 만들고 다른 필기 앱으로 보내는 행이다. 화면에서 푸는 길(풀기 시작)은 그대로 둔다.
struct SolveCollectionRow: View {
    @Bindable var model: SolveModel
    @Environment(\.openLink) private var openLink

    var body: some View {
        FormRow(
            label: String(localized: .solveCollection),
            detail: model.collectionFailure
                ?? (model.asksToReplaceCollection
                    ? String(localized: .solveCollectionReplaceDetail) : String(localized: .solveCollectionDetail)),
            warns: model.collectionFailure != nil || model.asksToReplaceCollection, last: true
        ) {
            HStack(spacing: Theme.Space.s) {
                if model.asksToReplaceCollection {
                    Button(.solveCollectionReplace) { model.replaceCollection() }.buttonStyle(.secondary)
                } else if let collection = model.collection, model.collectionIsCurrent, !model.buildingCollection {
                    Button(.commonOpen) { model.openCollection(solutions: false, openLink) }.buttonStyle(.secondary)
                    Button(.solveCollectionSolutions) { model.openCollection(solutions: true, openLink) }.buttonStyle(.secondary)
                    ShareLink(item: collection.url) { Label(String(localized: .solveCollectionShare), systemImage: "square.and.arrow.up") }
                        .buttonStyle(.prominent)
                } else {
                    Button(model.collectionTitle) { Task { await model.buildCollection() } }
                        .buttonStyle(.secondary).disabled(model.picked.isEmpty || model.buildingCollection)
                }
            }
        }
    }
}
