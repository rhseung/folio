import FolioDomain
import Foundation
import Observation

protocol ReleaseFeed: Sendable {
    func releases() async throws -> [PatchNotes.Release]
}
