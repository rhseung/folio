import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(help: ArgumentHelp(String(localized: .globalOptionsHelpGist), valueName: "path"))
    var gist: String?

    @Flag(help: ArgumentHelp(String(localized: .globalOptionsHelpJson)))
    var json = false

    @Flag(help: ArgumentHelp(String(localized: .globalOptionsHelpDryRun)))
    var dryRun = false

    @Flag(name: [.customShort("y"), .long], help: ArgumentHelp(String(localized: .globalOptionsHelpYes)))
    var yes = false

    @Flag(help: ArgumentHelp(String(localized: .globalOptionsHelpNoPick)))
    var noPick = false
}
