import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension SettingsCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: String(localized: .settingsShowAbstract), discussion: String(localized: .settingsShowDiscussion))
        @OptionGroup var g: GlobalOptions

        func run() throws {
            let s = try CLI.context(g).settings()
            if g.json { return try printJSON(s) }
            say(
                String(localized: .settingsShowDayBoundary).styled(.bold)
                    + String(format: "  %02d:%02d", s.dayBoundaryMinutes / 60, s.dayBoundaryMinutes % 60))
            say(String(localized: .settingsShowClassMinutes).styled(.bold) + "  " + String(localized: .settingsShowMinutes(s.classMinutes)))
            say(
                String(localized: .settingsShowIntervals).styled(.bold) + "  "
                    + s.review.intervals.map { String(localized: .settingsShowDays($0)) }.joined(separator: ", "))
            say(String(localized: .settingsShowNewNoteMath).styled(.bold) + "  \(s.newNoteMath.rawValue)")
            say(
                String(localized: .settingsShowBackup).styled(.bold)
                    + "  \(s.backup.enabled ? s.backup.folder : String(localized: .settingsShowOff))")
        }
    }
}
