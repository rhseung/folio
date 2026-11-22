import FolioDomain
import SwiftUI

// 블록을 누르면 뜨는 회차 패널이다. 행은 오른쪽 클릭 메뉴와 같은 회차 메뉴이고, 정리하지 않은 수업이면 맨 위에 수업
// 정리를 둔다. iPhone에서는 아래 시트로 뜬다.
struct SessionPopover: View {
    @Environment(\.openLink) private var openLink
    @Environment(\.openURL) private var openURL
    @Environment(\.itemSheets) private var sheets
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let model: SessionsModel
    let course: LoadedCourse
    let session: Session
    let asksWrapUp: Bool

    var body: some View {
        let file = course.file
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(model.popoverTitle(session, in: file)).font(Theme.Typeface.figureMedium).lineLimit(2)
                    Text(model.popoverDetail(session, in: file)).font(Theme.Typeface.caption)
                        .foregroundStyle(Theme.Palette.textTertiary).lineLimit(2)
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.l)
                .padding(.bottom, Theme.Space.s)
                if asksWrapUp { wrapUp }
                if let source = SessionMenu.source(
                    model.workspace, model.courseId, session.id, host: .own, openNote: openNote, openLink: openLink, openURL: openURL,
                    sheets: sheets)
                {
                    ItemPanel(source: source)
                }
            }
            .padding(.bottom, Theme.Space.s)
        }
        .frame(width: compact ? nil : Theme.Size.popover)
        .presentationCompactAdaptation(.sheet)
        .presentationDetents([.medium, .large])
    }

    var compact: Bool { sizeClass == .compact }

    // iPhone에서는 큰 버튼으로, 넓은 화면에서는 행 하나로 둔다.
    @ViewBuilder var wrapUp: some View {
        let start = { sheets.present(.session(SessionSheetRequest(course: model.courseId, session: session.id, asked: true))) }
        if compact {
            Button(.sessionsTableWrapUp, systemImage: "checklist") { dismissThen(start) }
                .buttonStyle(.pointing(.borderedProminent))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
        } else {
            Button {
                dismissThen(start)
            } label: {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: "checklist").frame(width: Theme.Size.smallIcon).accessibilityHidden(true)
                    Text(.sessionsTableWrapUp).fontWeight(.semibold)
                    Spacer(minLength: Theme.Space.s)
                }
                .foregroundStyle(Theme.Palette.warning)
                .padding(.horizontal, Theme.Space.l)
                .frame(minHeight: Theme.Size.rowHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.pointing(.plain))
            Divider().padding(.leading, Theme.Space.l)
        }
    }

    // 팝오버가 닫히는 중에 시트를 띄우면 iPhone에서 시트가 뜨지 않았으므로 닫힌 뒤에 띄운다.
    func dismissThen(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            action()
        }
    }

    func openNote(_ id: UUID) { openLink(AppLink(.note, id), course: model.courseId) }
}
