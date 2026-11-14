import FolioDomain
import Foundation
import SwiftUI

struct NotePanesPicker: View {
    @Binding var panes: NotePanes
    let wide: Bool

    var body: some View {
        if wide {
            Segmented(
                selection: Binding {
                    panes.mode
                } set: {
                    panes.choose($0)
                },
                options: [
                    (.read, String(localized: .notesModeRead)), (.split, String(localized: .notesModeSplit)),
                    (.write, String(localized: .notesModeWrite)),
                ],
                compact: true
            )
            .help(Text(.notesModeToggle))
        } else {
            Segmented(
                selection: Binding {
                    panes.shown(wide: false)
                } set: {
                    panes.chooseNarrow($0)
                },
                options: [(.read, String(localized: .notesModeRead)), (.write, String(localized: .notesModeWrite))],
                compact: true
            )
            .help(Text(.notesModeToggle))
        }
    }
}
