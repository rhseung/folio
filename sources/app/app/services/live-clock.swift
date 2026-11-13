import Foundation
import Observation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 각 뷰가 TimelineView를 따로 돌리면 시각이 서로 어긋난다. GeometryReader의 closure는 tick이 다시 실행하지 않아,
// ribbon의 지금 선은 멈춘 채 옆의 wash만 움직였다. 이 시계의 `now`를 읽는 뷰는 observation으로 다시 그려진다. 앱이
// 앞으로 오거나 Mac이 깨어나거나 시계나 시간대가 바뀌면 시각이 건너뛸 수 있으므로 그때도 tick한다.
@MainActor @Observable
final class LiveClock {
    private(set) var now: Date
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(now: Date = .now) {
        self.now = now
        start()
    }

    isolated deinit {
        ticker?.cancel()
        for (center, token) in observers { center.removeObserver(token) }
    }

    func refresh(at date: Date = .now) { now = date }

    nonisolated static func nextMinute(after date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: ((date.timeIntervalSinceReferenceDate / 60).rounded(.down) + 1) * 60)
    }

    private func start() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                // 매번 벽시계에서 계산해야 늦게 깨어나도 다음 tick이 분의 시작에서 밀리지 않는다.
                let wait = Self.nextMinute(after: .now).timeIntervalSinceNow
                try? await Task.sleep(for: .seconds(wait), tolerance: .milliseconds(200))
                guard let self else { return }
                self.refresh()
            }
        }
        #if os(macOS)
        watch(NotificationCenter.default, NSApplication.didBecomeActiveNotification)
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
        watch(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification)
        watch(NotificationCenter.default, .NSSystemClockDidChange)
        #else
        watch(NotificationCenter.default, UIApplication.didBecomeActiveNotification)
        watch(NotificationCenter.default, UIApplication.significantTimeChangeNotification)
        #endif
        watch(NotificationCenter.default, .NSSystemTimeZoneDidChange)
    }

    private func watch(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append((center, token))
    }
}

struct LiveTime<Content: View>: View {
    let workspace: Workspace
    @ViewBuilder let content: (Date) -> Content

    init(_ workspace: Workspace, @ViewBuilder content: @escaping (Date) -> Content) {
        self.workspace = workspace
        self.content = content
    }

    var body: some View { content(workspace.liveNow) }
}
