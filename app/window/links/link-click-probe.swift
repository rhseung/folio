import FolioDomain
import SwiftUI

#if os(iOS)
import UIKit

struct LinkClickProbe: UIGestureRecognizerRepresentable {
    func makeUIGestureRecognizer(context: Context) -> Probe { Probe() }

    // 다른 제스처의 터치를 가로채거나 취소하지 않도록, 키만 읽고 바로 실패한다.
    final class Probe: UIGestureRecognizer {
        init() {
            super.init(target: nil, action: nil)
            cancelsTouchesInView = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            LinkClicks.touched = (KeyCombo.Modifiers(event.modifierFlags), .now)
            state = .failed
        }
    }
}
#endif
