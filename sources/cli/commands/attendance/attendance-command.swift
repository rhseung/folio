import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

struct AttendanceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attendance", abstract: String(localized: .attendanceAbstract), subcommands: GeneratedCommands.attendance)
}
