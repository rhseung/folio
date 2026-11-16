import ArgumentParser
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct Staging: Sendable {
    var folder: StagedFolder
    var writes: Bool
}
