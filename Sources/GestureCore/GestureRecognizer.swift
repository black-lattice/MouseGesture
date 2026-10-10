import Foundation
import CoreGraphics

public enum Direction: String, Codable, CaseIterable {
    case left = "L", right = "R", up = "U", down = "D"

    public var arrow: String {
        switch self {
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        }
    }
}

/// Input uses Quartz screen coordinates: positive Y points down.
public enum GestureRecognizer {
    public static func recognize(_ points: [CGPoint], minimumLength: Double = 50) -> [Direction]? {
        guard points.count >= 2, points.count <= 2048,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let simplified = simplify(points, tolerance: 10)
        var directions: [Direction] = []
        var total: Double = 0
        for (start, end) in zip(simplified, simplified.dropFirst()) {
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length >= 12 else { continue }
            total += length
            let horizontal = abs(dx) >= abs(dy)
            let major = max(abs(dx), abs(dy))
            let minor = min(abs(dx), abs(dy))
            // Ambiguous diagonals and scribbles must never become destructive actions.
            guard minor / major <= 0.55 else { return nil }
            let direction: Direction = horizontal ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
            if directions.last != direction { directions.append(direction) }
            guard directions.count <= 4 else { return nil }
        }
        return total >= minimumLength && !directions.isEmpty ? directions : nil
    }

    private static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        // Iterative Ramer–Douglas–Peucker avoids recursion on long noisy strokes.
        var keep: Set<Int> = [0, points.count - 1]
        var pending = [(0, points.count - 1)]
        while let (first, last) = pending.popLast() {
            guard last > first + 1 else { continue }
            let a = points[first], b = points[last]
            let dx = b.x - a.x, dy = b.y - a.y
            let squared = dx * dx + dy * dy
            var maximum = tolerance
            var split: Int?
            for index in (first + 1)..<last {
                let p = points[index]
                let t = squared == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / squared))
                let distance = hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
                if distance > maximum { maximum = distance; split = index }
            }
            if let split {
                keep.insert(split)
                pending.append((first, split))
                pending.append((split, last))
            }
        }
        return keep.sorted().map { points[$0] }
    }
}

public struct Stroke {
    public private(set) var points: [CGPoint]
    public private(set) var isGesture = false
    public private(set) var isCancelled = false

    public init(start: CGPoint) { points = [start] }

    public mutating func append(_ point: CGPoint) {
        guard !isCancelled, let first = points.first, let last = points.last else { return }
        if hypot(point.x - first.x, point.y - first.y) >= 16 { isGesture = true }
        guard hypot(point.x - last.x, point.y - last.y) >= 2 else { return }
        guard points.count < 2048 else { cancel(); return }
        points.append(point)
    }

    public mutating func cancel() { isCancelled = true }
    public var shouldReplayClick: Bool { !isGesture && !isCancelled }
    public func recognize(minimumLength: Double) -> [Direction]? {
        guard isGesture && !isCancelled else { return nil }
        return GestureRecognizer.recognize(points, minimumLength: minimumLength)
    }
}
