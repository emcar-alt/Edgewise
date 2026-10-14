// Run with `make test`. A tiny harness, since the Command Line Tools ship no XCTest.
import AppKit

@main
enum PushAccumulatorTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition {
            failures += 1
            print("FAIL (line \(line)): \(message)")
        }
    }

    /// Feeds `steps` pointer events `interval` apart, each moving `delta` toward `edge`.
    static func push(_ accumulator: inout PushAccumulator, edge: Side?, delta: CGFloat, steps: Int,
                     start: TimeInterval = 0, interval: TimeInterval = 0.016) -> (Side?, TimeInterval) {
        var time = start
        for _ in 0..<steps {
            time += interval
            if let side = accumulator.add(.init(pinnedEdge: edge, outward: delta, time: time)) { return (side, time) }
        }
        return (nil, time)
    }

    static func main() {
        // A firm, continuous push triggers once the threshold is crossed.
        var accumulator = PushAccumulator(threshold: Sensitivity.medium.threshold)
        let (side, _) = push(&accumulator, edge: .right, delta: 12, steps: 40)
        expect(side == .right, "continuous push to the right should trigger")

        // Ordinary overshoot when flicking to a scroll bar does not.
        accumulator = PushAccumulator(threshold: Sensitivity.medium.threshold)
        expect(push(&accumulator, edge: .right, delta: 25, steps: 4).0 == nil, "a short overshoot should not trigger")

        // Pausing longer than maxGap starts over.
        accumulator = PushAccumulator(threshold: Sensitivity.medium.threshold)
        var (result, time) = push(&accumulator, edge: .left, delta: 15, steps: 15)
        expect(result == nil, "first half of a push should not trigger yet")
        (result, time) = push(&accumulator, edge: .left, delta: 15, steps: 15, start: time + 0.5)
        expect(result == nil, "a push split by a pause should not add up")

        // Pulling back off the edge cancels.
        accumulator = PushAccumulator(threshold: Sensitivity.medium.threshold)
        _ = push(&accumulator, edge: .right, delta: 15, steps: 18)
        _ = accumulator.add(.init(pinnedEdge: .right, outward: -10, time: 0.5))
        expect(accumulator.total == 0, "moving back inward should reset the push")

        // Leaving the edge resets.
        accumulator = PushAccumulator(threshold: Sensitivity.medium.threshold)
        _ = push(&accumulator, edge: .right, delta: 15, steps: 18)
        _ = accumulator.add(.init(pinnedEdge: nil, outward: 0, time: 0.4))
        expect(accumulator.total == 0 && accumulator.edge == nil, "leaving the edge should reset the push")

        // Switching edges starts a fresh count.
        accumulator = PushAccumulator(threshold: Sensitivity.medium.threshold)
        _ = push(&accumulator, edge: .right, delta: 15, steps: 18)
        let (other, _) = push(&accumulator, edge: .left, delta: 15, steps: 5, start: 0.3)
        expect(other == nil && accumulator.edge == .left && accumulator.total == 75, "a new edge should start counting from zero")

        // A slow drift that takes longer than the window never triggers.
        accumulator = PushAccumulator(threshold: Sensitivity.medium.threshold)
        expect(push(&accumulator, edge: .right, delta: 1, steps: 400, interval: 0.2).0 == nil, "slow drift should not trigger")

        // Sensitivities are ordered and Light triggers sooner than Firm.
        expect(Sensitivity.light.threshold < Sensitivity.medium.threshold && Sensitivity.medium.threshold < Sensitivity.firm.threshold,
               "thresholds should increase from light to firm")
        var light = PushAccumulator(threshold: Sensitivity.light.threshold)
        var firm = PushAccumulator(threshold: Sensitivity.firm.threshold)
        let (_, lightTime) = push(&light, edge: .right, delta: 10, steps: 200)
        let (_, firmTime) = push(&firm, edge: .right, delta: 10, steps: 200)
        expect(lightTime < firmTime, "light should trigger before firm")

        // After triggering, the accumulator is clear for the next push.
        accumulator = PushAccumulator(threshold: Sensitivity.light.threshold)
        _ = push(&accumulator, edge: .right, delta: 20, steps: 20)
        expect(accumulator.total == 0, "state should reset after a trigger")

        print(failures == 0 ? "All PushAccumulator tests passed." : "\(failures) test(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
