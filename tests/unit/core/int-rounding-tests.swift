import FolioCore
import PropertyBased
import Testing

struct IntRoundingTests {
    @Test func valuesOutsideTheRangeStopAtItsEnds() {
        #expect(Int(rounding: 1e19, in: 0...100) == 100)
        #expect(Int(rounding: -1e19, in: 0...100) == 0)
        #expect(Int(rounding: .infinity, in: 1...30) == 30)
        #expect(Int(rounding: .nan, in: 1...30) == 1)
        #expect(Int(rounding: 1e300, in: Int.min...Int.max) == .max)
        #expect(Int(rounding: -1e300, in: Int.min...Int.max) == .min)
        #expect(Int(rounding: 2.5, in: 0...10) == 3)
    }

    @Test func aValueInRangeRoundsAndEveryResultStaysInRange() async {
        await propertyCheck(input: Gen.int(in: -1000...1000), Gen.int(in: 0...1000), Gen.double(in: -1e20...1e20)) { low, span, x in
            let bounds = low...(low + span)
            let n = Int(rounding: x, in: bounds)
            #expect(bounds.contains(n))
            if x.rounded() >= Double(bounds.lowerBound), x.rounded() <= Double(bounds.upperBound) { #expect(Double(n) == x.rounded()) }
        }
    }
}
