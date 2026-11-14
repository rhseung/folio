import FolioDomain
import SwiftUI

@MainActor
struct RecordingMenuSource: ItemMenuSource {
    let model: RecordingPlayerModel
    let host: MenuHost
    let remove: @MainActor () -> Void
    let openLink: OpenLinkAction

    var commands: [RecordingMenuCommand] {
        RecordingMenuCommand.commands(host: host, transcribes: model.recording.hasAudio, hasTranscript: model.hasLines)
    }

    func row(_ command: RecordingMenuCommand) -> MenuRow {
        switch command {
        case .open:
            .open(command) { openLink(AppLink(.recording, model.recording.id), course: model.courseId) }
        case .transcribe:
            MenuRow(
                command, model.hasLines ? .recordingRetranscribe : .recordingTranscribe, "waveform.badge.magnifyingglass",
                disabled: !model.canTranscribe, .action(model.transcribe))
        case .share:
            .share(command, AppLink(.recording, model.recording.id), course: model.courseId)
        case .copyTranscript:
            MenuRow(command, .recordingCopy, "doc.on.doc", .action { writePasteboard(model.transcriptText) })
        case .remove:
            MenuRow(command, .commonDeleteEllipsis, "trash", role: .destructive, disabled: model.removalRefusal != nil, .action(remove))
        }
    }
}
