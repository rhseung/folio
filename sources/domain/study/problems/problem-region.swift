import Foundation

// 문제지 PDF의 한 쪽에서 문제나 그림이 차지하는 칸이다. 좌표는 쪽의 왼쪽 위를 원점으로 한 폭과 높이의 비율(0–1)이다. 쪽의
// 크기와 상관없이 같은 값이 같은 자리를 가리키게 하려는 것이다. 앱은 이 칸을 PDF에서 그대로 잘라 그린다.
public struct ProblemRegion: Codable, Sendable, Hashable {
    public var page: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    // 쪽 밖으로 나간 값은 쪽 안으로 줄인다. 넓이가 없거나 쪽 번호가 없는 칸은 nil이다. Claude가 어림한 값이라 조금 넘칠 수 있다.
    public init?(page: Int, x: Double, y: Double, width: Double, height: Double) {
        let left = min(max(x, 0), 1), top = min(max(y, 0), 1)
        let right = min(max(x + width, 0), 1), bottom = min(max(y + height, 0), 1)
        guard page >= 1, right - left > 0.005, bottom - top > 0.005, [x, y, width, height].allSatisfy(\.isFinite) else { return nil }
        self.page = page
        self.x = left
        self.y = top
        self.width = right - left
        self.height = bottom - top
    }

    // Claude가 어림한 칸은 가장자리의 글자나 선을 자르기 쉬워서, 그릴 때는 쪽 폭의 비율로 여백을 더한다.
    public func padded(by margin: Double) -> ProblemRegion {
        ProblemRegion(page: page, x: x - margin, y: y - margin, width: width + 2 * margin, height: height + 2 * margin) ?? self
    }

    // 두 칸이 같은 그림인지 본다. 소문제마다 따로 어림하면 같은 그림도 값이 조금씩 다르다.
    public func overlaps(_ other: ProblemRegion, atLeast share: Double = 0.8) -> Bool {
        guard page == other.page else { return false }
        let w = min(x + width, other.x + other.width) - max(x, other.x)
        let h = min(y + height, other.y + other.height) - max(y, other.y)
        guard w > 0, h > 0 else { return false }
        return w * h >= share * min(width * height, other.width * other.height)
    }
}
