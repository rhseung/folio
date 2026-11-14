import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct Format: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: String(localized: .noteFormatAbstract))
        @OptionGroup var g: GlobalOptions

        func run() throws { say(NoteWritingGuide.text) }
    }
}
