import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct Overrides: Sendable {
    var gist: URL
    var device: DeviceID
    var now: Date
    var gradesUnlocked = true
}
