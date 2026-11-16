import FolioDomain
import SwiftUI

@MainActor
struct SemesterMenuSource: ItemMenuSource {
    let semesterId: UUID
    let host: MenuHost
    var addCourse: (@MainActor () -> Void)?
    var folded: Bool?
    var fold: (@MainActor () -> Void)?
    let openLink: OpenLinkAction

    var commands: [SemesterMenuCommand] { SemesterMenuCommand.commands(host: host, addsCourse: addCourse != nil, folded: folded) }

    func row(_ command: SemesterMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(AppLink(.semester, semesterId)) }
        case .addCourse:
            MenuRow(command, .rootAddCourse, "plus", .action { addCourse?() })
        case .fold(let open):
            MenuRow(command, open ? .commonCollapse : .commonExpand, open ? "chevron.up" : "chevron.down", .action { fold?() })
        case .share:
            .share(command, AppLink(.semester, semesterId), course: nil)
        }
    }
}
