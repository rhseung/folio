import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

func kindLabel(_ s: Session) -> String? {
    switch s.kind {
    case .lecture: nil
    case .cancelled: String(localized: .sessionListCancelled)
    case .makeup: String(localized: .sessionListMakeup)
    }
}

struct SessionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "session", abstract: String(localized: .sessionAbstract),
        subcommands: subcommandTypes)
}
