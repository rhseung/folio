import FolioDomain
import SwiftUI

// 그림과 위젯의 크게 보기다. 그림은 미리보기의 그림 보기를 그대로 띄우고 그 보기를 닫으면 시트도 닫는다. 위젯은 노트와
// 같은 격리된 페이지에서 처음 상태부터 돌리며, 노트 안의 위젯과 상태를 나누지 않는다.
struct AssetViewer: View {
    let model: AssetTrayModel
    let asset: NoteAsset
    @Environment(\.dismiss) private var dismiss
    @State private var height = Theme.Size.assetPreview.height

    var body: some View {
        Group {
            switch asset.ref {
            case .file:
                NotePreview(text: model.figureText(asset) ?? "", baseURL: model.editor.baseURL, figureOnly: { dismiss() })
            case .widget(let id):
                widget(id)
            }
        }
        #if os(macOS)
        .frame(minWidth: Theme.Size.assetViewer.width, minHeight: Theme.Size.assetViewer.height)
        #else
        .presentationDetents([.large])
        #endif
    }

    private func widget(_ id: NoteWidget.ID) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Text(model.name(asset)).font(Theme.Typeface.sectionTitle).lineLimit(1)
                Spacer(minLength: Theme.Space.s)
                Button(.commonDone) { dismiss() }
                    .buttonStyle(.ghost)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, Theme.Space.l)
            .padding(.trailing, Theme.Space.s)
            .frame(height: Theme.Size.assetTrayHead)
            Theme.Palette.lineSoft.frame(height: 1)
            ScrollView(.vertical) {
                WidgetPageView(id: id, noteFolder: model.editor.baseURL, height: $height)
                    .frame(height: height)
                    .padding(Theme.Space.l)
            }
        }
        .background(Theme.Palette.card)
    }
}
