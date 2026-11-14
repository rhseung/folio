import FolioDomain
import SwiftUI

extension PrimitiveButtonStyle {
    static func pointing<Base: PrimitiveButtonStyle>(_ base: Base) -> Self where Self == PointingButtonStyle<Base> { .init(base: base) }
}

extension PrimitiveButtonStyle where Self == ProminentButtonStyle {
    static var prominent: ProminentButtonStyle { .init() }
}

extension View {
    // `.button` 스타일 메뉴에 사용자 정의 button style을 주면 pop-up으로 돌아가므로, 메뉴의 손가락 포인터는 따로 둔다.
    func pointingHand() -> some View {
        #if os(macOS)
        pointerStyle(.link)
        #else
        self
        #endif
    }

    func opens(_ action: (() -> Void)?) -> some View {
        #if os(macOS)
        contentShape(.rect).onTapGesture { action?() }.pointerStyle(action == nil ? nil : .link)
        #else
        contentShape(.rect).onTapGesture { action?() }
        #endif
    }
}

extension EnvironmentValues {
    @Entry var linkFocus: UUID?
}

extension View {
    func linkTarget(_ id: UUID) -> some View { modifier(LinkTarget(id: id)) }
}

private struct LinkTarget: ViewModifier {
    let id: UUID
    @Environment(\.linkFocus) private var focus
    @Environment(\.accent) private var accent
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if focus == id {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .fill(accent.tint)
                        .strokeBorder(accent.color.opacity(lit ? 1 : 0), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .id(id)
            .task(id: focus) {
                guard focus == id else { return lit = false }
                lit = true
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeOut(duration: 0.8)) { lit = false }
            }
    }
}

extension View {
    func fileDrop(_ perform: @escaping ([URL]) -> Void) -> some View { modifier(FileDrop(perform: perform)) }

    func fileDrag(_ url: URL) -> some View {
        // shortcut: 아직 내려받지 않은 iCloud placeholder는 끌어도 아무것도 전달되지 않는다. 문제가 되면 먼저
        // 내려받는다.
        onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    }
}

private struct FileDrop: ViewModifier {
    @Environment(\.accent) private var accent
    let perform: ([URL]) -> Void
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if targeted {
                    RoundedRectangle(cornerRadius: Theme.Radius.control)
                        .strokeBorder(accent.color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                if !files.isEmpty { perform(files) }
                return !files.isEmpty
            } isTargeted: {
                targeted = $0
            }
    }
}

extension View {
    func picks(picking: Bool, touch: PickPress, hold: @escaping () -> Void, _ press: @escaping (PickPress) -> Void) -> some View {
        modifier(Picks(picking: picking, touch: touch, hold: hold, press: press))
    }
}

private struct Picks: ViewModifier {
    let picking: Bool
    let touch: PickPress
    let hold: () -> Void
    let press: (PickPress) -> Void

    #if os(macOS)
    func body(content: Content) -> some View {
        // 클릭 이벤트 자신의 flags를 읽는다. 키보드의 현재 상태(`NSEvent.modifierFlags`)는 손쉬운 사용이나 스크립트
        // 클릭처럼 키를 누르지 않고 클릭에 실린 키를 놓친다.
        content.contentShape(.rect).onTapGesture {
            let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
            press(flags.contains(.shift) ? .range : flags.contains(.command) ? .toggle : .only)
        }
    }
    #else
    @State private var keys = HeldKeys()
    @State private var holds = 0

    func body(content: Content) -> some View {
        content.contentShape(.rect)
            // SwiftUI의 탭을 쓴다. 키를 함께 전하는 UIKit의 탭은 행 안의 버튼과 메뉴 옆에서도 발동한다.
            .onTapGesture {
                let flags = keys.flags
                press(flags.contains(.shift) ? .range : flags.contains(.command) ? .toggle : picking ? touch : .only)
            }
            .onLongPressGesture {
                holds += 1
                hold()
            }
            .gesture(KeyProbe(keys: keys))
            .sensoryFeedback(.selection, trigger: holds)
    }
    #endif
}

#if os(iOS)
// SwiftUI의 탭은 수정 키를 전하지 않고 `onModifierKeysChanged`는 Mac에서만 동작하므로, recognizer가 터치 이벤트에서
// 키를 읽는다.
@MainActor private final class HeldKeys {
    var flags: UIKeyModifierFlags = []
}

private struct KeyProbe: UIGestureRecognizerRepresentable {
    let keys: HeldKeys

    func makeUIGestureRecognizer(context: Context) -> Probe { Probe(keys: keys) }

    // 다른 제스처의 터치를 가로채거나 취소하지 않도록, 키만 읽고 바로 실패한다.
    final class Probe: UIGestureRecognizer {
        let keys: HeldKeys

        init(keys: HeldKeys) {
            self.keys = keys
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            keys.flags = event.modifierFlags
            state = .failed
        }
    }
}
#endif
