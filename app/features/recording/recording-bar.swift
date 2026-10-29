import SwiftUI

struct RecordingBar: View {
    @Environment(Workspace.self) private var workspace
    @State private var expanded = false

    var body: some View {
        let recorder = workspace.recorder
        let recording = recorder.state == .recording
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            ForEach(Array(recorder.lines.suffix(40).enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                    Text(RecordingTime.label(line.start)).font(Theme.Typeface.label).monospacedDigit()
                                        .foregroundStyle(Theme.Palette.textTertiary).frame(width: 44, alignment: .leading)
                                    Text(line.text).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            if !recorder.volatile.isEmpty {
                                Text(recorder.volatile).foregroundStyle(Theme.Palette.textTertiary).padding(.leading, 52)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                    }
                    .frame(height: 220)
                    .onChange(of: recorder.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                    .onChange(of: recorder.volatile) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: Theme.Space.m) {
                Circle()
                    .fill(recording ? Theme.Palette.danger : Theme.Palette.textTertiary)
                    .frame(width: 10, height: 10)
                    .phaseAnimator([1.0, 0.35]) { dot, phase in dot.opacity(recording ? phase : 1) } animation: { _ in .easeInOut(duration: 0.8) }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text(recorder.state == .preparing ? "받아쓰기 준비 중…" : recorder.title)
                        .font(Theme.Typeface.label).foregroundStyle(Theme.Palette.textSecondary).lineLimit(1)
                    Text(recorder.volatile.isEmpty ? (recorder.lines.last?.text ?? recorder.transcriptionNote ?? "듣는 중…") : recorder.volatile)
                        .lineLimit(1).truncationMode(.head)
                        .foregroundStyle(recorder.volatile.isEmpty ? Theme.Palette.text : Theme.Palette.textSecondary)
                        .contentTransition(.opacity)
                }
                .frame(width: 300, alignment: .leading)
                LevelMeter(level: recorder.level)
                Text(RecordingTime.label(recorder.elapsed)).font(Theme.Typeface.bodyStrong).monospacedDigit().frame(width: 64)
                Button { recorder.bookmark() } label: { Image(systemName: "bookmark") }
                    .help("지금 이 지점 표시 (\(recorder.bookmarks.count)개)")
                    .symbolEffect(.bounce, value: recorder.bookmarks.count)
                Button { if recording { recorder.pause() } else { workspace.perform { try recorder.resume() } } } label: {
                    Image(systemName: recording ? "pause.fill" : "record.circle").contentTransition(.symbolEffect(.replace))
                }
                .help(recording ? "일시 정지" : "이어서 녹음")
                .disabled(recorder.state == .preparing)
                Button { Task { await workspace.stopRecording() } } label: {
                    Image(systemName: "stop.fill").foregroundStyle(Theme.Palette.danger)
                }
                .help("녹음 끝내기")
                .disabled(recorder.state == .preparing)
                Button { withAnimation(.snappy(duration: 0.3)) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.up").rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .help(expanded ? "받아쓰기 접기" : "받아쓰기 펼치기")
            }
            .buttonStyle(.ghost)
        }
        .font(Theme.Typeface.body)
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
        .frame(width: 620)
        .floatingGlass()
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.xxs) {
            ForEach(0..<5, id: \.self) { i in
                let lit = Float(i) / 5 < level
                Capsule()
                    .fill(lit ? Theme.Palette.success : Theme.Palette.textTertiary.opacity(0.3))
                    .frame(width: 4, height: 6 + CGFloat([0, 4, 8, 4, 0][i]) + (lit ? CGFloat(level) * 6 : 0))
            }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.15), value: level)
        .accessibilityHidden(true)
    }
}

enum RecordingTime {
    static func label(_ seconds: TimeInterval) -> String {
        let s = Int(max(seconds, 0))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
