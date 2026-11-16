import FolioActions
import FolioDomain
import Foundation

extension TranscriptList: QueryOutput {
    func say(_ rows: [TranscriptRow], _ r: Resolver) throws { TranscriptCommand.print(rows, semester: true) }
}
