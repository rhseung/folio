import FolioDomain
import SwiftUI

struct RecordingFace<Outline: InsettableShape>: View {
    let shape: Outline
    let accent: CourseAccent
    let recording: Bool
    let level: Float
    var origin: (CGSize) -> CGPoint = { CGPoint(x: 0, y: $0.height) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let voice = recording ? CGFloat(level) : 0
        ZStack {
            shape.fill(accent.tint)
            shape.strokeBorder(accent.color.opacity(Theme.Opacity.innerFill))
            GeometryReader { proxy in
                let reach = max(proxy.size.width, proxy.size.height)
                // 카드를 채우는 gradient 대신 원점 주위의 원을 쓴다. 카드 높이보다 줄면 카드 크기의 채움은 윗변이 빛을
                // 가로지르는 선으로 보였다.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.color.opacity(Theme.Opacity.voiceGlow), accent.color.opacity(0)],
                            center: .center, startRadius: 0, endRadius: reach)
                    )
                    .frame(width: reach * 2, height: reach * 2)
                    .position(origin(proxy.size))
                    // 반지름을 바꾸지 않고 원점에서 scale 한다. SwiftUI는 레벨 샘플 사이의 scale을 부드럽게 잇지만
                    // gradient 반지름은 건너뛴다.
                    .scaleEffect(reduceMotion ? 1 : 0.5 + 1.1 * voice, anchor: Self.anchor(origin(proxy.size), in: proxy.size))
                    .opacity(Double(voice).squareRoot())
            }
            .clipShape(shape)
        }
        // 레벨이 1초에 다섯 번 오고 spring은 샘플마다 넘쳐서 깜박였으므로, easing으로 둔다.
        .animation(Theme.Motion.pane, value: voice)
    }

    private static func anchor(_ point: CGPoint, in size: CGSize) -> UnitPoint {
        UnitPoint(x: size.width > 0 ? point.x / size.width : 0, y: size.height > 0 ? point.y / size.height : 0)
    }
}
