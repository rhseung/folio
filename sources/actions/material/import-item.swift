import FolioDomain
import FolioStorage
import Foundation

public struct ImportItem: Codable, Sendable, Hashable {
    public var file: String
    public var folder: String
    public var session: Session.ID?
    public var sections: [LectureCut]?

    public init(file: String, folder: String, session: Session.ID? = nil, sections: [LectureCut]? = nil) {
        (self.file, self.folder, self.session, self.sections) = (file, folder, session, sections)
    }
}
