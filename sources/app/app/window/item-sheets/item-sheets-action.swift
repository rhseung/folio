import FolioDomain
import FolioStorage
import SwiftUI

struct ItemSheetsAction {
    var present: @MainActor (ItemSheet) -> Void = { _ in }
    var confirm: @MainActor (PendingAction?) -> Void = { _ in }
    var addFiles: @MainActor (FileIntake) -> Void = { _ in }
}
