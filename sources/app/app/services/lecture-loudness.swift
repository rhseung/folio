import AVFoundation
import FolioDomain
import Speech

#if os(iOS)
import UIKit
#endif

// 범위는 책상 위 노트북이 듣는 수업 소리를 기준으로, 녹음한 강의를 1초 단위로 잰 값이다. -57dB는 문장 사이의 교실
// 소리(10번째 백분위수)이고, -42dB는 강의자가 목소리를 높일 때(95번째 백분위수)다. 예전의 -55dB에서 -5dB까지의
// 범위에서는 수업 전체가 눈금의 3분의 1 아래에 머물러, 미터와 카드의 빛이 거의 움직이지 않았다.
enum LectureLoudness {
    static let quiet: Float = -57
    static let loud: Float = -42

    static func level(_ decibels: Float) -> Float {
        max(0, min(1, (decibels - quiet) / (loud - quiet)))
    }
}
