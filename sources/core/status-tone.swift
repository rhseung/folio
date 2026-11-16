import Foundation

// 상태 값의 색이다. 앱의 칩과 명령줄 출력의 색이 같은 값을 읽는다.
public enum StatusTone: Sendable {
    case plain, good, caution, bad, info, muted
}
