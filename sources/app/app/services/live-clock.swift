import Foundation
import Observation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// The one clock the live parts of the app (Today's ribbon, header and wash, the sidebar's class under way, a session
// row's under-way state) draw against. Each used to run its own TimelineView, and they disagreed: the ribbon read the
// time inside a GeometryReader, whose closure a tick does not run again, so its now line stayed put while the wash
// beside it had moved on. A view that reads `now` here is redrawn by observation instead, wherever it reads it.
//
// Ticks on the minute, since every time these views show is in minutes, and again whenever the time may have jumped:
// the app coming back to the front, the Mac waking, the clock or time zone changing.
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

    /// The start of the minute after `date`, when a time shown in minutes next changes.
    nonisolated static func nextMinute(after date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: ((date.timeIntervalSinceReferenceDate / 60).rounded(.down) + 1) * 60)
    }

    private func start() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                // From the wall clock each time, so a late wake-up doesn't push the next tick off the minute.
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

/// Hands its content the live time where a screen needs it in one part only, so the rest isn't redrawn each minute.
struct LiveTime<Content: View>: View {
    let workspace: Workspace
    @ViewBuilder let content: (Date) -> Content

    init(_ workspace: Workspace, @ViewBuilder content: @escaping (Date) -> Content) {
        self.workspace = workspace
        self.content = content
    }

    var body: some View { content(workspace.liveNow) }
}
