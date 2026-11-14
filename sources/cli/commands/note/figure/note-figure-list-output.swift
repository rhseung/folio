import FolioActions
import FolioDomain
import Foundation

extension NoteFigureList: QueryOutput {
    func say(_ items: [NoteFileItem], _ r: Resolver) throws { sayFiles(items) }
}
