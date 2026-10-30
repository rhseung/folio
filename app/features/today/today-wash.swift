import SwiftUI

// Today's one exception to plain paper: the day's course colors glow faintly across the page's top and fade out
// before the lists, so the landing page changes with the timetable. A day without classes stays plain paper.
// During a class the other colors clear and the class's own color alone glows behind the title.
struct TodayWash: View {
    let model: TodayModel
    let courses: [UUID]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let now = model.nowClass(at: model.workspace.now)
            ZStack {
                ForEach(Array(courses.enumerated()), id: \.element) { i, id in
                    // Spread edge to edge; a lone course sits left, over the title, rather than dead center.
                    let x = courses.count == 1 ? 0.25 : 0.06 + 0.88 * Double(i) / Double(courses.count - 1)
                    RadialGradient(colors: [model.workspace.accent(id).color.opacity(Theme.Opacity.courseWash), .clear],
                                   center: UnitPoint(x: x, y: 0), startRadius: 0, endRadius: Theme.Size.washReach)
                }
                .opacity(now == nil ? 1 : 0)
                if let now {
                    RadialGradient(colors: [model.workspace.accent(now.courseId).color.opacity(Theme.Opacity.courseWash), .clear],
                                   center: UnitPoint(x: 0.25, y: 0), startRadius: 0, endRadius: Theme.Size.washReachFocus)
                        .transition(.opacity)
                }
            }
            .frame(height: Theme.Size.washHeight)
            // The glows alone end in arcs; the mask fades them out evenly at one depth.
            .mask(LinearGradient(stops: [.init(color: .primary, location: 0.3), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .animation(.easeInOut(duration: 0.6), value: now?.courseId)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
