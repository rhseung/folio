import FolioActions
import FolioDomain
import SwiftUI

struct SessionUnitsButton: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Environment(\.itemSheets) private var sheets
    let course: LoadedCourse
    let session: Session
    var compact = false
    var separated = false

    var body: some View {
        let units = SessionUnits(session, in: course.file, now: workspace.now)
        if units.offered {
            Button {
                sheets.present(.session(SessionSheetRequest(course: course.id, session: session.id, focus: .units)))
            } label: {
                if separated {
                    inline(units)
                } else {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: units.symbol)
                        if !compact {
                            ViewThatFits(in: .horizontal) {
                                if !units.shown.isEmpty, let progress = units.progress {
                                    SectionProgress(file: course.file, material: progress.material, range: progress.pages)
                                }
                                Text(units.label).lineLimit(1).truncationMode(.tail)
                            }
                        }
                    }
                    .font(Theme.Typeface.caption.weight(units.missing ? .semibold : .regular))
                    .foregroundStyle(
                        units.missing
                            ? Theme.Palette.warning : units.linked.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textSecondary
                    )
                    .contentShape(.rect)
                }
            }
            .buttonStyle(.pointing(.plain))
            .help(units.help)
        }
    }

    @ViewBuilder func inline(_ units: SessionUnits) -> some View {
        HStack(spacing: Theme.Space.tight) {
            if !(compact && !units.shown.isEmpty) { Text("·") }

            if !units.shown.isEmpty {
                ViewThatFits(in: .horizontal) {
                    if let progress = units.progress {
                        HStack(spacing: Theme.Space.tight) {
                            if compact { Image(systemName: "link") }
                            SectionProgress(file: course.file, material: progress.material, range: progress.pages, labeled: !compact)
                        }
                    }
                    if compact {
                        Image(systemName: "link")
                    } else {
                        Text(units.titles).lineLimit(1).truncationMode(.tail)
                    }
                }
            } else if units.missing {
                Label(.sessionsUnitsAdd, systemImage: "plus").labelStyle(.titleAndIcon).fontWeight(.semibold).foregroundStyle(accent.ink)
            } else {
                Label(.sessionsUnitsAdd, systemImage: "plus").labelStyle(.titleAndIcon)
            }
        }
        .contentShape(.rect)
    }
}
