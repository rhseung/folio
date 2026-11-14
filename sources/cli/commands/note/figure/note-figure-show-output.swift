import FolioActions
import FolioDomain
import Foundation

extension NoteFigureShow: QueryOutput {
    func say(_ body: NoteFileBody, _ r: Resolver) throws { FolioCLI.say(body.text) }
}
