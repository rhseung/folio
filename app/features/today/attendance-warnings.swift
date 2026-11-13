import FolioDomain
import SwiftUI

struct AttendanceWarnings: View {
    let model: TodayModel

    var body: some View {
        let warnings = model.attendanceWarnings
        if !warnings.isEmpty {
            Card {
                ForEach(Array(warnings.enumerated()), id: \.element.course.id) { i, w in
                    CardRow(last: i == warnings.count - 1) {
                        CourseMark(model.workspace, w.course.id)
                        Text(.todayAttendanceAbsences(w.course.title, w.absences))
                        Spacer()
                        Chip(model.capLabel(w.cap), tone: .warning)
                    }
                }
            }
        }
    }
}
