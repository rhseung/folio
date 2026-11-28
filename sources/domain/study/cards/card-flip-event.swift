import FolioCore
import Foundation

public struct CardFlipEvent: LogEvent, Equatable {
    public static let type = "card_flip"
    public var cardId: UUID
    public var known: Bool
    // 참·거짓 카드에서 고른 답이다. 앞뒤 카드를 넘긴 줄에는 없다.
    public var answer: Bool?

    public init(cardId: UUID, known: Bool, answer: Bool? = nil) {
        self.cardId = cardId
        self.known = known
        self.answer = answer
    }
}
