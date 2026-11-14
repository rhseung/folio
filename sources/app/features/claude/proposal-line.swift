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

struct ProposalLine: Equatable {
    var text: String
    var refusal: String?
    var change: Change?

    enum Change: Equatable {
        case rewrite([TextDiff.Line])
        case edit([NoteEdit.Replacement], append: String?)
        case figure(String)
    }
}
