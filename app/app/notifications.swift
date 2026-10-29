import FolioDomain
import Foundation
import UserNotifications

/// Turns the notification plan into pending local notifications (docs/SPEC.md "알림").
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
            content.title = String(localized: "\(course) · \(item.subject) 마감 \(hours)시간 전")
            content.body = String(localized: "마감 \(when)")
        case .examDayBefore:
            content.title = String(localized: "내일 \(course) \(item.subject)")
            content.body = when
        case .examMorning:
            content.title = String(localized: "오늘 \(course) \(item.subject)")
            content.body = when
        case .dailyReview(let count):
            content.title = String(localized: "오늘 복습할 단원 \(count)개")
            content.body = String(localized: "오늘 화면에서 우선순위 순으로 볼 수 있습니다")
        case .attendanceOneAway(let absences):
            content.title = String(localized: "\(course) 결석 \(absences)회")
            content.body = String(localized: "한 번 더 결석하면 성적 상한이 적용됩니다")
        }
        return content
    }
}
