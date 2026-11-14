import FolioDomain
import FolioStorage
import SwiftUI

struct PDFContent: View {
    let model: FileViewModel
    let controller: PDFController
    var thumbnails = true

    var body: some View {
        if let shown = model.splitting, let course = model.course {
            // 닫을 때 화면의 뷰는 이 바인딩으로 한 번 더 그려진다. 뷰는 보이던 나누기를 읽고, 닫은 뒤의 쓰기는 화면을 다시 열지 않는다. 여기에 임시 나누기를 두면 구역이 하나뿐이라, 아직 셋째
            // 구역을 가진 행이 끝을 넘어갔다.
            LectureSplitPane(
                controller: controller,
                split: Binding(
                    get: { model.splitting ?? shown },
                    set: { if model.splitting != nil { model.splitting = $0 } }),
                units: course.file.units, note: model.splitNote,
                claude: model.claudeFailed ? ClaudeSplitButton(asking: model.askingClaude) { Task { await model.retryClaude() } } : nil,
                save: model.saveSplit, cancel: model.cancelSplit
            )
            .courseAccent(model.accent(course))
        } else if let course = model.course {
            PDFPane(controller: controller, thumbnails: thumbnails, strip: model.pageStrip(pageCount: controller.pageCount))
                .courseAccent(model.accent(course))
        } else {
            PDFPane(controller: controller, thumbnails: thumbnails, strip: model.pageStrip(pageCount: controller.pageCount))
        }
    }
}
