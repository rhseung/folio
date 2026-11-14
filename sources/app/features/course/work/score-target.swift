import FolioActions
import FolioDomain
import Foundation
import Observation

enum ScoreTarget: Hashable {
    case none, component(UUID), group(String)
}
