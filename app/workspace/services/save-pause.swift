import Foundation

// 입력이 멈춘 뒤 파일에 쓰기까지 기다리는 시간이다. 글자나 값이 바뀔 때마다 쓰면 iCloud가 같은 파일을 연달아 올리고, 너무
// 오래 기다리면 창을 닫거나 화면을 옮길 때 마지막 입력이 남지 않는다.
enum SavePause {
    static let delay: Duration = .milliseconds(800)
}
