import AVFoundation
import FolioDomain
import Speech

#if os(iOS)
import UIKit
#endif

// input node는 sample rate를 변환하지 못한다. 하드웨어와 다른 rate를 읽는 동안 tap을 걸면 아무것도 녹음되지
// 않거나("config change pending") Objective-C 예외가 난다(`installTapOnBus` "Format mismatch: input hw 48000 Hz,
// client 24000 Hz"). Swift는 이 예외를 잡지 못하므로 앱이 종료된다.
enum MicrophoneTap {
    struct Stream: Equatable {
        var sampleRate: Double
        var channels: UInt32
    }

    enum Plan: Equatable { case tap, rebuild, noInput }

    static let stall: TimeInterval = 2
    static let settle: TimeInterval = 1

    static func plan(hardware: Stream, node: Stream) -> Plan {
        guard hardware.sampleRate > 0, hardware.channels > 0 else { return .noInput }
        return node.sampleRate == hardware.sampleRate && node.channels > 0 ? .tap : .rebuild
    }

    static func restartDue(running: Bool, sinceHeard: TimeInterval, sinceRestart: TimeInterval) -> Bool {
        sinceRestart > settle && (!running || sinceHeard > stall)
    }
}

extension MicrophoneTap.Stream {
    init(_ format: AVAudioFormat) {
        self.init(sampleRate: format.sampleRate, channels: format.channelCount)
    }
}
