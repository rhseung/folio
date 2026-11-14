import Foundation

// MARK: Recording

public enum RecordingMenuCommand: ItemCommand {
    case open
    case transcribe
    case share
    case copyTranscript
    case remove

    public var group: MenuGroup {
        switch self {
        case .open: .open
        case .transcribe: .start
        case .share, .copyTranscript: .share
        case .remove: .remove
        }
    }

    public static func commands(host: MenuHost, transcribes: Bool, hasTranscript: Bool) -> [RecordingMenuCommand] {
        var commands: [RecordingMenuCommand] = host.opensItem ? [.open] : []
        if transcribes { commands.append(.transcribe) }
        commands.append(.share)
        if hasTranscript { commands.append(.copyTranscript) }
        commands.append(.remove)
        return commands.inMenuOrder()
    }
}
