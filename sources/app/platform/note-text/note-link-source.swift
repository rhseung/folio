import FolioDomain
import FolioMarkdown
import SwiftUI

@MainActor protocol NoteLinkSource: AnyObject {
    func candidates(for query: CompletionQuery, text: String) async -> [CompletionItem]
    func take(_ item: CompletionItem, for query: CompletionQuery, text: String) -> (item: CompletionItem, own: SourceEditing.Edit?)?
}
