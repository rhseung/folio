import FolioActions
import FolioDomain
import Foundation

extension NoteShow: QueryOutput {
    func say(_ body: Body, _ r: Resolver) throws { FolioCLI.say(body.text) }
}
