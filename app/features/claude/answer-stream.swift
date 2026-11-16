import FolioAI
import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import Synchronization

#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class AnswerStream: Sendable {
    struct State: Sendable, Equatable {
        var text: String?
        var tool: String?
        var toolInput = ""
    }

    private let state = Mutex(State())

    var now: State { state.withLock { $0 } }

    func take(_ event: StreamEvent) {
        state.withLock { s in
            switch event {
            case .turn: s.text = nil
            case .text(let piece): s.text = (s.text ?? "") + piece; s.tool = nil
            case .tool(let name): s.tool = name; s.toolInput = ""
            case .toolInput(let piece): s.toolInput += piece
            }
        }
    }
}
