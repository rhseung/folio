#if DEBUG && os(macOS)
import AppKit
import Darwin
import FolioDomain

// 활동 모니터의 "메모리" 열은 `phys_footprint`다. RSS는 파일에서 다시 읽을 수 있는 쪽(모델 가중치의 mmap)까지 세어서 그 숫자와 다르다.
@MainActor enum MemoryProbe {
    static let environment = ProcessInfo.processInfo.environment
    static let file = environment["FOLIO_MEMORY_PROBE"].map { URL(filePath: $0) }
    private static var log = ""

    nonisolated static func footprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    static func megabytes() -> String { "\(footprint() / 1_048_576)MB" }

    static func mark(_ line: String) {
        guard let file else { return }
        log += "\(line) footprint=\(megabytes())\n"
        // folio:not-an-action debug measurements, outside the GIST folder
        try? log.write(to: file, atomically: true, encoding: .utf8)
    }

    // 받아쓰기 한 번이 모델을 올렸다가 내리는지 본다. 녹음을 멈추면 받아쓰기가 저절로 돌므로, 녹음을 켜지 않은 앱도 이 모델을 들고 있을 수 있다.
    static func run() async {
        guard file != nil else { return }
        try? await Task.sleep(for: .seconds(4))
        mark("idle")
        if let audio = environment["FOLIO_MEMORY_AUDIO"].map({ URL(filePath: $0) }) {
            for round in 1...2 {
                let lines = (try? await WhisperTranscriber.shared.transcribe(audio, hints: nil) { _ in })?.lines.count ?? -1
                mark("transcribed#\(round) lines=\(lines)")
                var waited = 0
                for seconds in [5, 30, 70] {
                    try? await Task.sleep(for: .seconds(seconds - waited))
                    waited = seconds
                    mark("transcribed#\(round)+\(seconds)s")
                }
            }
        }
        if let count = environment["FOLIO_MEMORY_MATH"].flatMap(Int.init) { await typeMath(count) }
        NSApp.terminate(nil)
    }

    // 편집 보기에서 수식을 칠 때처럼 매번 다른 수식의 말풍선 그림을 요청한다. 덜 친 수식은 그려지지 않아 캐시에 들지 않으므로 닫힌 수식만 쓴다.
    private static func typeMath(_ count: Int) async {
        guard let host = NSApp.windows.first(where: \.isVisible)?.contentView else { return mark("math no-window") }
        let math = NoteMath.shared
        var drawn = 0
        let started = ContinuousClock.now
        for i in 0..<count {
            let source =
                #"\frac{\partial^2 u_{"# + "\(i)"
                + #"}}{\partial x^2} + \sum_{k=1}^{n} \alpha_k \begin{pmatrix} a_{11} & a_{12} \\ a_{21} & a_{22} \end{pmatrix}"#
            math.host(in: host)
            var ready = false
            if math.picture(source, syntax: .latex, display: true, size: 16, dark: false, trim: true, ready: { ready = true }) == nil {
                let until = ContinuousClock.now + .seconds(5)
                while !ready, ContinuousClock.now < until { try? await Task.sleep(for: .milliseconds(10)) }
            }
            drawn += 1
            if drawn % 500 == 0 { mark("math drawn=\(drawn) after=\(ContinuousClock.now - started)") }
        }
        try? await Task.sleep(for: .seconds(5))
        mark("math done=\(drawn)")
    }
}
#endif
