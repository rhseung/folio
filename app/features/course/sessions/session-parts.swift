import FolioActions
import FolioDomain
import SwiftUI

/// 휴강 or 보강 beside a class's name. A lecture, the usual kind, goes unmarked. A makeup is held, so it takes the
/// course color rather than a warning.
struct SessionKindChip: View {
    let kind: Session.Kind

    var body: some View {
        switch kind {
        case .cancelled: Chip(String(localized: .sessionsCancelled))
        case .makeup: Chip(String(localized: .sessionsMakeup), tone: .accent)
        case .lecture: EmptyView()
        }
    }
}

/// Joins an online class: Zoom links go to the Zoom app directly, and anything else (or Zoom when the app isn't
/// installed) opens in the browser.
struct JoinOnlineButton: View {
    @Environment(\.openURL) private var openURL
    let url: URL
    /// The class card's own start button, rather than a slot among the notes.
    var prominent = false

    var body: some View {
        if prominent {
            Button(.sessionsJoin, systemImage: "video") { Self.join(url, openURL) }.buttonStyle(.prominent)
                .help(url.absoluteString)
        } else {
            SessionSlot(String(localized: .sessionsJoin), symbol: "video", help: url.absoluteString, fixed: false) {
                Self.join(url, openURL)
            }
        }
    }

    static func join(_ url: URL, _ openURL: OpenURLAction) {
        guard let app = OnlineLink.appURL(url) else { return openURL(url) }
        openURL(app, completion: fallback(to: url, with: openURL))
    }

    // On macOS, LaunchServices calls this completion on its own background queue. A closure written here would be
    // inferred @MainActor (this is a View), and Swift 6 traps when it runs off the main queue, so it must be
    // @Sendable and hop back to the main actor before opening the web link.
    static func fallback(to url: URL, with openURL: OpenURLAction) -> @Sendable (Bool) -> Void {
        { @Sendable accepted in
            if !accepted { Task { @MainActor in openURL(url) } }
        }
    }
}

/// The units a session covers, a shortcut into its sheet's 단원 group (#403). A held class with none is flagged, since
/// its review never reaches the unit queue.
struct SessionUnitsButton: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Environment(\.itemSheets) private var sheets
    let course: LoadedCourse
    let session: Session
    /// The icon alone, when the row's title already names the units.
    var compact = false
    /// After other text on a line, so it leads with a `·`; a held class with none asks for them in the accent.
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
            // The title names the units already, so only the icon is left to click and it needs no separator.
            if !(compact && !units.shown.isEmpty) { Text("·") }

            if !units.shown.isEmpty {
                // The strip has a fixed width, so a narrow row (a pane, an iPad in a split) falls back to the plain form.
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
