import FolioDomain
import Foundation
import UserNotifications

@MainActor
enum NotificationScheduler {
    /// Attendance warnings fire right away, so the ones already shown are remembered per device.
    static let sentKey = "notifications.sentAttendance"
    /// macOS and iPadOS keep at most 64 pending requests per app.
    static let pendingLimit = 60

    static func reschedule(_ workspace: Workspace) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let now = Date.now
        let current = workspace.currentCourses
        let plan = NotificationPlan.build(
            courses: current.map(\.file),
            reviewCount: { date in workspace.reviewQueue(now: date).filter { $0.item.deferred == nil }.count },
            settings: workspace.settings.notifications, now: now, calendar: workspace.calendar
        )
        center.removeAllPendingNotificationRequests()
        var sent = Set(UserDefaults.standard.stringArray(forKey: sentKey) ?? [])
        for item in plan.prefix(pendingLimit) {
            let trigger: UNNotificationTrigger?
            if case .attendanceOneAway = item.kind {
                guard sent.insert(item.id).inserted else { continue }
                trigger = nil
            } else {
                trigger = UNCalendarNotificationTrigger(
                    dateMatching: workspace.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date), repeats: false)
            }
            try? await center.add(UNNotificationRequest(identifier: item.id, content: content(item, workspace), trigger: trigger))
        }
        UserDefaults.standard.set(Array(sent), forKey: sentKey)
    }

    static func content(_ item: PlannedNotification, _ workspace: Workspace) -> UNMutableNotificationContent {
        let course = item.courseId.flatMap { workspace.course($0)?.title } ?? ""
        let when = item.at?.formatted(.dateTime.month().day().weekday().hour().minute()) ?? ""
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch item.kind {
        case .assignmentDue(let hours):
            content.title = String(localized: .notifyDue(course, item.subject, hours))
            content.body = String(localized: .notifyDueAt(when))
        case .examDayBefore:
            content.title = String(localized: .notifyExamTomorrow(course, item.subject))
            content.body = when
        case .examMorning:
            content.title = String(localized: .notifyExamToday(course, item.subject))
            content.body = when
        case .dailyReview(let count):
            content.title = String(localized: .notifyReview(count))
            content.body = String(localized: .notifyReviewDetail)
        case .attendanceOneAway(let absences):
            content.title = String(localized: .notifyAbsences(course, absences))
            content.body = String(localized: .notifyAbsencesDetail)
        }
        return content
    }
}
