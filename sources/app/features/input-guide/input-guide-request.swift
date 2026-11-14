import FolioDomain
import FolioMarkdown
import Foundation
import Observation

struct InputGuideRequest: Identifiable {
    let id = UUID()
    let syntax: MathSyntax
}
