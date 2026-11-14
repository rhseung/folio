import SwiftUI

struct StripPage: View {
    let controller: PDFController
    let page: Int
    let picked: Bool
    let box: CGSize
    let ranging: Bool
    let press: (_ page: Int, _ extend: Bool) -> Void
    let start: ((_ page: Int) -> Void)?

    var body: some View {
        PageThumbnail(thumbnails: controller.thumbnails, page: page, current: controller.page + 1 == page, picked: picked, box: box)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Theme.Space.s)
            .contentShape(.rect)
            #if os(macOS)
        .gesture(
            TapGesture().modifiers(.shift).onEnded { pick(extend: true) }
                .exclusively(before: TapGesture().onEnded { pick(extend: false) }))
            #else
        .onTapGesture { pick(extend: ranging) }
        .modifier(LongPressStart(start: start.map { start in { start(page) } }))
            #endif
            .pointingHand()
    }

    private func pick(extend: Bool) {
        press(page, extend)
        controller.go(to: page - 1)
    }
}

#if os(iOS)
// 메뉴가 있는 곳에서는 아무것도 붙이지 않는다. 빈 길게 누르기도 메뉴의 길게 누르기와 경쟁하기 때문이다.
private struct LongPressStart: ViewModifier {
    let start: (() -> Void)?

    func body(content: Content) -> some View {
        if let start { content.onLongPressGesture(perform: start) } else { content }
    }
}
#endif
