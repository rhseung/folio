import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct ReviewBadge: View {
    let state: ReviewState?
    let today: LocalDate

    var body: some View {
        if let state {
            if state.settled && state.due == nil {
                Chip(String(localized: .unitsReviewDone), tone: .success)
            } else if let due = state.due {
                let late = due.days(until: today)
                if state.writeNoteFirst && late >= 0 {
                    Chip(String(localized: late > 0 ? .unitsBadgeNoteLate(late) : .unitsBadgeNote), tone: .warning)
                } else if late > 0 {
                    Chip(String(localized: .unitsDaysLate(late)), tone: .danger)
                } else if late == 0 {
                    Chip(String(localized: .unitsToday), tone: .accent)
                } else {
                    Chip(due.shortLabel)
                }
            }
        } else {
            Chip(String(localized: .unitsBadgeNotStarted))
        }
    }
}
