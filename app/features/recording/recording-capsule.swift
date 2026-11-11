import FolioDomain
import SwiftUI

/// The recorder's place in the toolbar, a group of its own after the search field (#62, 2026-11-11 사용자): a round
/// mic while nothing records, widening where it stands into the course's capsule once a class records with the
/// sidebar's card folded away. Kept out of the other buttons' group: inside it, starting moved the button out of the
/// group, and the time sat among them unnoticed.
///
/// The capsule holds only what a class needs a hand for: the time, which pauses (not stops: ending a lecture by a
/// slip is the costly mistake), and the mark. Paused, it goes gray and offers the stop, the one way to end it here.
struct RecordingCapsule<Idle: View>: View {
    @State private var model: RecordingBarModel
    let expanded: Bool
    /// When set, the time opens this rather than pausing, and the capsule holds the time alone: the iPad's toolbar
    /// buttons are too small to share, so its card opens in a popover instead.
    let openCard: (() -> Void)?
    @ViewBuilder let idle: Idle

    init(workspace: Workspace, expanded: Bool, openCard: (() -> Void)? = nil, @ViewBuilder idle: () -> Idle) {
        _model = State(initialValue: RecordingBarModel(workspace: workspace))
        self.expanded = expanded
        self.openCard = openCard
        self.idle = idle()
    }

    var body: some View {
        HStack(spacing: 0) {
            if expanded {
                time
                if openCard == nil {
                    divider
                    // The marks sit a little further from the round end than from the rule: the end's curve eats
                    // into the room, and measured evenly the mark looked pushed against it (2026-11-11 사용자).
                    HStack(spacing: Theme.Space.xs) {
                        mark
                        if model.paused { stop.transition(.opacity.combined(with: .scale(scale: 0.6))) }
                    }
                    .buttonStyle(CapsuleIconStyle())
                    .padding(.leading, Theme.Space.s)
                    .padding(.trailing, Theme.Space.m)
                }
            } else {
                idle.transition(.opacity)
            }
        }
        .buttonStyle(.toolbar)
        .toolbarGroup()
        .background {
            if expanded {
                RecordingFace(shape: Capsule(), accent: model.paused ? CourseAccent.gray : model.accent, recording: model.recording,
                              level: model.recorder.level) { size in CGPoint(x: Self.dotCenter, y: size.height / 2) }
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.34), value: expanded)
        .animation(.smooth(duration: 0.34), value: model.paused)
    }

    // From the capsule's leading edge to the dot's middle: the time's padding, half the dot.
    static var dotCenter: CGFloat { Theme.Space.m + Theme.Size.dot / 2 }

    var time: some View {
        Button {
            if let openCard { openCard() } else { model.toggle() }
        } label: {
            HStack(spacing: Theme.Space.tight) {
                if model.paused {
                    Image(systemName: "pause.fill").font(Theme.Glyph.regular).foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Circle().fill(Theme.Palette.danger).frame(width: Theme.Size.dot, height: Theme.Size.dot)
                }
                Text(RecordingTime.label(model.recorder.elapsed))
                    .font(Theme.Typeface.bodyStrong).monospacedDigit()
                    .foregroundStyle(model.paused ? Theme.Palette.textSecondary : Theme.Palette.text)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Theme.Space.m)
        }
        .disabled(openCard == nil && model.settling)
        .help(Text(openCard != nil ? .rootRecording : model.paused ? .recordingResume : .recordingPause))
        .accessibilityLabel(Text(openCard != nil ? .rootRecording : model.paused ? .recordingResume : .recordingPause))
        .accessibilityValue(Text(RecordingTime.label(model.recorder.elapsed)))
    }

    var divider: some View {
        (model.paused ? CourseAccent.gray : model.accent).color.opacity(Theme.Opacity.innerFill * 2)
            .frame(width: 1, height: Theme.Space.l)
    }

    var mark: some View {
        let count = model.recorder.bookmarks.count
        return Button { model.recorder.bookmark() } label: {
            // Filled once marked, as on the card: an outline that only bounced looked as if the click did nothing.
            Label(String(localized: .recordingBookmarkHelp(count)), systemImage: count == 0 ? "bookmark" : "bookmark.fill")
                .symbolEffect(.bounce, value: count)
                .contentTransition(.symbolEffect(.replace))
        }
        .help(Text(.recordingBookmarkHelp(count)))
        .disabled(model.settling)
    }

    var stop: some View {
        Button(String(localized: .recordingStop), systemImage: "stop.fill") { Task { await model.stop() } }
            .help(Text(.recordingStop))
            .disabled(model.settling)
    }
}

/// The capsule's mark and stop: the time's size, not a toolbar button's, so they don't loom over the digits, and a
/// circle to hover that fits the capsule's height.
private struct CapsuleIconStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CapsuleIcon(configuration: configuration)
    }
}

private struct CapsuleIcon: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label.labelStyle(.iconOnly)
            .font(Theme.Typeface.bodyStrong)
            .foregroundStyle(Theme.Palette.chromeIcon)
            .frame(width: Self.side, height: Self.side)
            .background {
                Circle().fill(Theme.Palette.text).opacity(configuration.isPressed ? Theme.Opacity.pressed : hovering && isEnabled ? Theme.Opacity.hover : 0)
            }
            .frame(height: Theme.Size.toolbarButton)
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : Theme.Opacity.disabled)
            .onHover { hovering = $0 }
    }

    static let side = Theme.Size.toolbarButton - Theme.Space.s
}
