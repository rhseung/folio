import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

protocol CLIText {
    init(cli text: String, _ r: Resolver, in course: CourseRef?) throws
}
