import FolioCore
import Foundation

public struct CardFlipEvent: LogEvent, Equatable {
    public static let type = "card_flip"
    public var cardId: UUID
    public var known: Bool

    public init(cardId: UUID, known: Bool) {
        self.cardId = cardId
        self.known = known
    }
}
