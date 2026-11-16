import FolioDomain
import SwiftUI

// 오늘 화면에는 새 보고가 있다는 것만 알린다. 목록과 내보내기는 설정의 앱 정보에 있다.
struct DiagnosticNotice: View {
    @State private var model: DiagnosticsModel
    @Environment(\.openLink) private var openLink

    init(workspace: Workspace) { _model = State(initialValue: DiagnosticsModel(workspace: workspace)) }

    var body: some View {
        if model.newCount > 0 {
            NoticeCard(title: model.noticeTitle, detail: model.noticeDetail, systemImage: "stethoscope", tone: .info) {
                HStack(spacing: Theme.Space.s) {
                    Button(.commonClose) { model.markSeen() }.buttonStyle(.ghost)
                    Button(.diagnosticsNoticeOpen) { openLink(.settings(.about)) }.buttonStyle(.prominent)
                }
            }
        }
    }
}
