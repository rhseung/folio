import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

enum Built {
    @TaskLocal static var record: (@Sendable (String, JSONValue) -> Void)?
}
