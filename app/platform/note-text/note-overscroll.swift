import FolioDomain
import FolioMarkdown
import SwiftUI

enum NoteOverscroll {
    static func bottom(_ height: CGFloat) -> CGFloat { (height / 2).rounded() }
}
