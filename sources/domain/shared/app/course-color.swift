import Foundation

public enum CourseColor {
    public static let cycle = ["violet", "blue", "orange", "green", "pink", "olive", "teal", "red"]
    // 조용히 둘 과목(콜로퀴움)에는 고를 수 있게 하지만, 색을 정하지 않은 과목에는 고르지 않는다. 고르면
    // 사용자가 정하지 않았는데도 과목이 회색이 된다.
    public static let neutral = "graphite"
    public static let presets = cycle + [neutral]

    // `#RRGGBB`로 저장한 예전 색을 가장 가까운 이름으로 읽을 때만 쓴다. 값은 `CourseAccent.presets`의 라이트
    // 값이고, 앱 테스트 `presetsReadAsThemselves`가 graphite를 포함한 각 값이 자기 이름으로 읽히는지 확인한다.
    static let anchors: [(name: String, hex: UInt32)] = [
        ("violet", 0x8B7CF6), ("blue", 0x3B5BDB), ("orange", 0xE9A02C), ("green", 0x2D7A62),
        ("pink", 0xFF3D7F), ("olive", 0x8A8A3C), ("teal", 0x1D8FA8), ("red", 0xFF6B4A),
    ]
    // 저장한 색의 OKLab 채도가 이 값보다 낮으면 무채색으로 읽는다. 가장 흐린 프리셋인 green은 0.085, 슬레이트
    // 블루는 0.07이고, 파랑이나 갈색이 살짝 섞인 회색은 0.035보다 낮다.
    static let neutralChroma = 0.04

    public static func token(_ stored: String, position: Int) -> String {
        if presets.contains(stored) { return stored }
        // 프리셋이 생기기 전의 과목은 gray라는 이름을 쓸 수 있었고, 앱은 이 이름을 무채색으로 그렸다.
        if stored == "gray" { return neutral }
        if stored.count == 7, stored.first == "#", let hex = UInt32(stored.dropFirst(), radix: 16) { return nearest(hex) }
        return cycle[position % cycle.count]
    }

    // 보이는 색 차이를 따르는 OKLab 거리로 가장 가까운 색을 고른다. RGB 거리로 고르면 짙은 남색이 보라로
    // 읽힌다. 회색은 채도로 먼저 가른다. 명도가 색상만큼 반영되는 거리만으로 고르면 밝은 회색이 amber로, 짙은
    // 슬레이트 블루가 graphite로 읽힌다.
    static func nearest(_ hex: UInt32) -> String {
        let p = oklab(hex)
        if (p[1] * p[1] + p[2] * p[2]).squareRoot() < neutralChroma { return neutral }
        return anchors.min { a, b in
            let x = oklab(a.hex), y = oklab(b.hex)
            return zip(p, x).map { ($0 - $1) * ($0 - $1) }.reduce(0, +) < zip(p, y).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)
        }!.name
    }

    static func oklab(_ hex: UInt32) -> [Double] {
        let lin = [16, 8, 0].map { shift -> Double in
            let c = Double(hex >> UInt32(shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = (lin[0], lin[1], lin[2])
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return [
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
        ]
    }
}
