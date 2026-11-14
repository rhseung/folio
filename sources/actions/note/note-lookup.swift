import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

func note(_ ctx: ActionContext, course: UUID, path: String) throws -> NoteFile {
    guard let note = try ctx.store(course).note(at: path, in: ctx.file(course)) else {
        throw ActionError.notFound(String(localized: .errorNotFoundNote("\(path)")))
    }
    return note
}

func note(_ ctx: ActionContext, course: UUID, id: UUID) throws -> NoteFile {
    guard let note = try ctx.store(course).note(id: id, in: ctx.file(course)) else {
        throw ActionError.notFound(String(localized: .errorNotFoundNote("\(id)")))
    }
    return note
}
