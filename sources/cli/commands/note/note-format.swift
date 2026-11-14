import ArgumentParser
import FolioDomain
import FolioStorage
import Foundation

extension NoteCommand {
    struct Format: ParsableCommand, HandRead {
        static let reason = "노트 형식 안내는 --json에서도 글 그대로 준다"
        static let panel = true
        static let configuration = CommandConfiguration(abstract: String(localized: .noteFormatAbstract))
        @OptionGroup var g: GlobalOptions

        func run() throws { say(NoteWritingGuide.text) }
    }
}
