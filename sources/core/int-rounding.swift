extension Int {
    // `Int(Double)`는 값이 `Int`의 범위를 넘거나 NaN이면 앱을 멈춘다. 그래서 범위로 먼저 자른 뒤에 바꾸고, NaN은 아래 끝으로 읽는다.
    public init(rounding value: Double, in bounds: ClosedRange<Int>) {
        let r = value.rounded()
        if !(r > Double(bounds.lowerBound)) {
            self = bounds.lowerBound
        } else if r < Double(bounds.upperBound) {
            self = Int(r)
        } else {
            self = bounds.upperBound
        }
    }
}
