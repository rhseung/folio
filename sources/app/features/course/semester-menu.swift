import FolioDomain
import SwiftUI

struct SemesterMenu: View {
    @Environment(\.openLink) private var openLink
    let semesterId: UUID
    var host: MenuHost = .elsewhere
    var addCourse: (@MainActor () -> Void)?
    var folded: Bool?
    var fold: (@MainActor () -> Void)?

    var body: some View {
        ItemMenu(
            source: SemesterMenuSource(
                semesterId: semesterId, host: host, addCourse: addCourse, folded: folded, fold: fold, openLink: openLink))
    }
}
