import SwiftUI

/// A page of the column, pressed as both columns take it: a press goes to the page; ⇧-press on a Mac, or a tap while
/// a range is up on a touch screen, which has no ⇧ to hold, moves a range's end; a long press starts one.
struct StripPage: View {
    let controller: PDFController
    let page: Int
    let picked: Bool
    let box: CGSize
    /// A range is up: on a touch screen the next tap moves its end.
    let ranging: Bool
    let press: (_ page: Int, _ extend: Bool) -> Void
    /// Nil where the long press opens the page's menu instead, which then holds the way in.
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
/// None at all where there's a menu: an empty long press would still race the menu's own.
private struct LongPressStart: ViewModifier {
    let start: (() -> Void)?

    func body(content: Content) -> some View {
        if let start { content.onLongPressGesture(perform: start) } else { content }
    }
}
#endif
