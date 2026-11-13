import FolioActions
import FolioDomain
import SwiftUI

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

struct JoinOnlineButton: View {
    @Environment(\.openURL) private var openURL
    let url: URL
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

    // macOS에서 LaunchServices는 이 completion을 자기 background queue에서 부른다. 여기서 쓴 클로저는 View 안이라
    // @MainActor로 추론되고, Swift 6는 그것이 main queue 밖에서 돌면 trap 한다. 그래서 @Sendable로 두고 웹 링크를 열기
    // 전에 main actor로 돌아가야 한다.
    static func fallback(to url: URL, with openURL: OpenURLAction) -> @Sendable (Bool) -> Void {
        { @Sendable accepted in
            if !accepted { Task { @MainActor in openURL(url) } }
        }
    }
}

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
