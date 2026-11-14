import SwiftUI

struct TodayWash: View {
    let model: TodayModel
    let courses: [UUID]

    var body: some View {
        let now = model.nowCourse(at: model.workspace.liveNow)
        ZStack {
            ForEach(Array(courses.enumerated()), id: \.element) { i, id in
                let x = courses.count == 1 ? 0.25 : 0.06 + 0.88 * Double(i) / Double(courses.count - 1)
                RadialGradient(
                    colors: [model.workspace.accent(id).color.opacity(Theme.Opacity.courseWash), .clear],
                    center: UnitPoint(x: x, y: 0), startRadius: 0, endRadius: Theme.Size.washReach)
            }
            .opacity(now == nil ? 1 : 0)
            if let now {
                RadialGradient(
                    colors: [model.workspace.accent(now).color.opacity(Theme.Opacity.courseWash), .clear],
                    center: UnitPoint(x: 0.25, y: 0), startRadius: 0, endRadius: Theme.Size.washReachFocus
                )
                .transition(.opacity)
            }
        }
        .frame(height: Theme.Size.washHeight)
        .mask(
            LinearGradient(
                stops: [.init(color: .primary, location: 0.3), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        )
        .animation(.easeInOut(duration: 0.6), value: now)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
