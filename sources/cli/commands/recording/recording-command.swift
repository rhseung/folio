import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct RecordingCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recording", abstract: String(localized: .recordingAbstract),
        subcommands: [Transcript.self] + GeneratedCommands.recording)

}
