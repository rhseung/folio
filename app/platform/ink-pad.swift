#if os(iOS)
import PencilKit
import SwiftUI

// PencilKit 캔버스는 SwiftUI에 없어서 UIKit 뷰를 감싼다. 획이 바뀔 때마다 PNG 한 장으로 내보낸다.
struct InkPad: UIViewRepresentable {
    @Binding var images: [Data]

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)  // design: one-off, 펜 굵기는 화면 간격이 아니라 필기 획이다
        canvas.delegate = context.coordinator
        return canvas
    }

    // 다음 문제로 넘어가 답이 비면 캔버스도 비운다.
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if images.isEmpty, !canvas.drawing.strokes.isEmpty { canvas.drawing = PKDrawing() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(images: $images) }

    @MainActor final class Coordinator: NSObject, PKCanvasViewDelegate {
        let images: Binding<[Data]>

        init(images: Binding<[Data]>) { self.images = images }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            let drawing = canvas.drawing
            guard !drawing.strokes.isEmpty else {
                images.wrappedValue = []
                return
            }
            // 다크 모드의 흰 획은 투명 배경에서 Claude가 읽지 못하므로 라이트 모드로 그린다.
            var data: Data?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                data = drawing.image(from: drawing.bounds.insetBy(dx: -16, dy: -16), scale: 2).pngData()
            }
            images.wrappedValue = data.map { [$0] } ?? []
        }
    }
}
#endif
