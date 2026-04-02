// BezierPathfinder.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics
import GameplayKit

/// Calculates smooth bezier spline segments for connector curves that avoid obstacles.
///
/// Uses GameplayKit to find an obstacle-aware route, then converts the route
/// into a multi-segment cubic bezier spline for a continuous, smooth stroke.
struct BezierPathfinder {

    static func calculateSegments(
        from start: CGPoint,
        to end: CGPoint,
        obstacles: [CGRect] = [],
        clearance: CGFloat = 16,
        startPort: PortPosition? = nil,
        endPort: PortPosition? = nil
    ) -> [BezierSegment] {
        guard start != end else { return [] }

        let startHint = startPort.map { portDirection($0, isStart: true) }
        let endHint = endPort.map { portDirection($0, isStart: false) }

        let direct = directCurve(from: start, to: end, startDirection: startHint, endDirection: endHint)
        if obstacles.isEmpty { return [direct] }

        if !segmentsIntersectObstacles([direct], obstacles: obstacles, clearance: clearance) {
            return [direct]
        }

        let clearanceSteps: [CGFloat] = [
            clearance * 0.6, clearance * 0.8, clearance,
            clearance * 1.2, clearance * 1.6, clearance * 2.2
        ].map { max(4, $0) }

        let tensionSteps: [CGFloat] = [0.05, 0.15, 0.3, 0.5, 0.7, 0.85, 1.0]

        for step in clearanceSteps {
            let waypoints = findPath(from: start, to: end, obstacles: obstacles, clearance: step)
            if waypoints.count < 2 { continue }

            let simplified = simplify(waypoints, obstacles: obstacles, clearance: step)
            if simplified.count < 2 { continue }

            let startDirection = blendedDirection(
                preferred: startHint,
                fallback: direction(from: simplified.first ?? start, to: simplified.dropFirst().first ?? end),
                weight: 0.8
            )
            let endDirection = blendedDirection(
                preferred: endHint,
                fallback: direction(from: simplified.dropLast().last ?? start, to: simplified.last ?? end),
                weight: 0.8
            )

            for tension in tensionSteps {
                let segments = smoothSplineToBezier(
                    points: simplified,
                    tension: tension,
                    startDirection: startDirection,
                    endDirection: endDirection,
                    clearance: step
                )
                if segments.isEmpty { continue }
                if !segmentsIntersectObstacles(segments, obstacles: obstacles, clearance: step) {
                    return segments
                }
            }
        }

        return []
    }
}

private extension BezierPathfinder {
    // MARK: - Pathfinding

    private static func findPath(
        from start: CGPoint,
        to end: CGPoint,
        obstacles: [CGRect],
        clearance: CGFloat
    ) -> [CGPoint] {
        guard !obstacles.isEmpty else { return [start, end] }

        let inflatedObstacles = obstacles.map { $0.insetBy(dx: -clearance, dy: -clearance) }

        let graphObstacles = inflatedObstacles.map { rect -> GKPolygonObstacle in
            let points = [
                vector_float2(Float(rect.minX), Float(rect.minY)),
                vector_float2(Float(rect.maxX), Float(rect.minY)),
                vector_float2(Float(rect.maxX), Float(rect.maxY)),
                vector_float2(Float(rect.minX), Float(rect.maxY))
            ]
            return GKPolygonObstacle(points: points)
        }

        let bufferRadius = max(4, clearance * 0.35)
        let graph = GKObstacleGraph(obstacles: graphObstacles, bufferRadius: Float(bufferRadius))
        let startNode = GKGraphNode2D(point: vector_float2(Float(start.x), Float(start.y)))
        let endNode = GKGraphNode2D(point: vector_float2(Float(end.x), Float(end.y)))

        graph.connectUsingObstacles(node: startNode)
        graph.connectUsingObstacles(node: endNode)

        let pathNodes = graph.findPath(from: startNode, to: endNode) as? [GKGraphNode2D] ?? []
        guard !pathNodes.isEmpty else { return [start, end] }

        return pathNodes.map { CGPoint(x: CGFloat($0.position.x), y: CGFloat($0.position.y)) }
    }

    // MARK: - Simplification

    private static func simplify(_ points: [CGPoint], obstacles: [CGRect], clearance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }

        let inflated = obstacles.map { $0.insetBy(dx: -clearance, dy: -clearance) }
        let minSegmentLength: CGFloat = 6
        var deduped: [CGPoint] = [points[0]]

        for point in points.dropFirst()
            where distance(deduped.last ?? point, point) >= minSegmentLength {
            deduped.append(point)
        }

        if deduped.count <= 2 { return deduped }

        var simplified: [CGPoint] = [deduped[0]]
        for index in 1..<(deduped.count - 1) {
            let a = simplified.last ?? deduped[index - 1]
            let b = deduped[index]
            let c = deduped[index + 1]
            if isColinear(a, b, c),
               !segmentIntersectsObstacles(from: a, to: c, obstacles: inflated) {
                continue
            }
            simplified.append(b)
        }
        simplified.append(deduped.last ?? points.last ?? .zero)
        return simplified
    }

    private static func isColinear(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let bc = CGPoint(x: c.x - b.x, y: c.y - b.y)
        let cross = abs(ab.x * bc.y - ab.y * bc.x)
        let denom = max(1, distance(a, b) * distance(b, c))
        return (cross / denom) < 0.02
    }

    // MARK: - Spline Smoothing

    private static func smoothSplineToBezier(
        points: [CGPoint],
        tension: CGFloat,
        startDirection: CGPoint?,
        endDirection: CGPoint?,
        clearance: CGFloat
    ) -> [BezierSegment] {
        guard points.count >= 2 else { return [] }

        if points.count == 2 {
            return [
                directCurve(
                    from: points[0],
                    to: points[1],
                    startDirection: startDirection,
                    endDirection: endDirection
                )
            ]
        }

        let clampedTension = clamp(tension, 0, 1)
        let tangents = computeTangents(
            points: points,
            tension: clampedTension,
            startDirection: startDirection,
            endDirection: endDirection,
            clearance: clearance
        )
        return buildSegments(points: points, tangents: tangents)
    }

    private static func computeTangents(
        points: [CGPoint],
        tension: CGFloat,
        startDirection: CGPoint?,
        endDirection: CGPoint?,
        clearance: CGFloat
    ) -> [CGPoint] {
        var tangents: [CGPoint] = Array(repeating: .zero, count: points.count)

        for index in 0..<points.count {
            if index == 0 {
                tangents[index] = endpointTangent(
                    point: points[0],
                    neighbor: points[1],
                    preferredDirection: startDirection,
                    tension: tension,
                    clearance: clearance
                )
            } else if index == points.count - 1 {
                tangents[index] = endpointTangent(
                    point: points[index],
                    neighbor: points[index - 1],
                    preferredDirection: endDirection,
                    tension: tension,
                    clearance: clearance
                )
            } else {
                tangents[index] = interiorTangent(
                    prev: points[index - 1],
                    current: points[index],
                    next: points[index + 1],
                    tension: tension
                )
            }
        }

        return tangents
    }

    private static func endpointTangent(
        point: CGPoint,
        neighbor: CGPoint,
        preferredDirection: CGPoint?,
        tension: CGFloat,
        clearance: CGFloat
    ) -> CGPoint {
        let fallback = direction(from: point, to: neighbor)
        let dir = blendedDirection(preferred: preferredDirection, fallback: fallback, weight: 0.85)
        let length = endpointTangentLength(distance(point, neighbor), tension: tension, clearance: clearance)
        return scale(dir, length)
    }

    private static func interiorTangent(
        prev: CGPoint,
        current: CGPoint,
        next: CGPoint,
        tension: CGFloat
    ) -> CGPoint {
        let scaleFactor = (1 - tension) * 0.5
        var tangent = CGPoint(x: (next.x - prev.x) * scaleFactor, y: (next.y - prev.y) * scaleFactor)

        let dirIn = direction(from: prev, to: current)
        let dirOut = direction(from: current, to: next)
        let angle = angleBetween(dirIn, dirOut)
        let cornerScale = max(0.2, 1 - angle / .pi)
        tangent = Self.scale(tangent, cornerScale)

        let maxLen = min(distance(prev, current), distance(current, next)) * 0.8
        return clampLength(tangent, max: maxLen)
    }

    private static func buildSegments(points: [CGPoint], tangents: [CGPoint]) -> [BezierSegment] {
        var segments: [BezierSegment] = []
        for index in 0..<(points.count - 1) {
            let p0 = points[index]
            let p1 = points[index + 1]
            let c1 = CGPoint(x: p0.x + tangents[index].x / 3, y: p0.y + tangents[index].y / 3)
            let c2 = CGPoint(x: p1.x - tangents[index + 1].x / 3, y: p1.y - tangents[index + 1].y / 3)
            segments.append(BezierSegment(start: p0, control1: c1, control2: c2, end: p1))
        }
        return segments
    }

    private static func directCurve(
        from start: CGPoint,
        to end: CGPoint,
        startDirection: CGPoint? = nil,
        endDirection: CGPoint? = nil
    ) -> BezierSegment {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let dist = sqrt(dx * dx + dy * dy)
        let base = dist * 0.45
        let offset = min(max(base, 60), 220)

        let axisDirection: CGPoint
        if abs(dx) >= abs(dy) {
            axisDirection = CGPoint(x: dx >= 0 ? 1 : -1, y: 0)
        } else {
            axisDirection = CGPoint(x: 0, y: dy >= 0 ? 1 : -1)
        }

        let startDir = startDirection ?? axisDirection
        let endDir = endDirection ?? CGPoint(x: -axisDirection.x, y: -axisDirection.y)

        let c1 = CGPoint(x: start.x + startDir.x * offset, y: start.y + startDir.y * offset)
        let c2 = CGPoint(x: end.x + endDir.x * offset, y: end.y + endDir.y * offset)

        return BezierSegment(start: start, control1: c1, control2: c2, end: end)
    }

}

private extension BezierPathfinder {
    // MARK: - Intersection Tests

    private static func segmentsIntersectObstacles(
        _ segments: [BezierSegment],
        obstacles: [CGRect],
        clearance: CGFloat
    ) -> Bool {
        let inflated = obstacles.map { $0.insetBy(dx: -clearance * 0.5, dy: -clearance * 0.5) }
        for segment in segments {
            let bounds = segmentBounds(segment).insetBy(dx: -2, dy: -2)
            let nearby = inflated.filter { $0.intersects(bounds) }
            guard !nearby.isEmpty else { continue }
            for rect in nearby where curveIntersectsRect(segment: segment, rect: rect, depth: 0) {
                return true
            }
        }
        return false
    }

    private static func segmentBounds(_ segment: BezierSegment) -> CGRect {
        let xs = [segment.start.x, segment.control1.x, segment.control2.x, segment.end.x]
        let ys = [segment.start.y, segment.control1.y, segment.control2.y, segment.end.y]
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func segmentIntersectsObstacles(from start: CGPoint, to end: CGPoint, obstacles: [CGRect]) -> Bool {
        let bounds = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: max(abs(end.x - start.x), 1),
            height: max(abs(end.y - start.y), 1)
        )
        for rect in obstacles where rect.intersects(bounds) {
            if rect.contains(start) || rect.contains(end) { return true }
            if lineIntersectsRect(start: start, end: end, rect: rect) { return true }
        }
        return false
    }

    private static func curveIntersectsRect(segment: BezierSegment, rect: CGRect, depth: Int) -> Bool {
        let bounds = segmentBounds(segment)
        guard rect.intersects(bounds) else { return false }
        if rect.contains(segment.start) || rect.contains(segment.end) { return true }
        if depth >= 12 { return true }
        if curveIsFlat(segment, threshold: 0.5) {
            return lineIntersectsRect(start: segment.start, end: segment.end, rect: rect)
                || rect.intersects(bounds)
        }
        let (left, right) = subdivide(segment)
        return curveIntersectsRect(segment: left, rect: rect, depth: depth + 1)
            || curveIntersectsRect(segment: right, rect: rect, depth: depth + 1)
    }

    private static func curveIsFlat(_ segment: BezierSegment, threshold: CGFloat) -> Bool {
        let d1 = distanceFromPointToLine(point: segment.control1, lineStart: segment.start, lineEnd: segment.end)
        let d2 = distanceFromPointToLine(point: segment.control2, lineStart: segment.start, lineEnd: segment.end)
        return max(d1, d2) <= threshold
    }

    private static func distanceFromPointToLine(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x; let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared == 0 { return distance(point, lineStart) }
        let t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared
        let projection = CGPoint(x: lineStart.x + t * dx, y: lineStart.y + t * dy)
        return distance(point, projection)
    }

    private static func subdivide(_ segment: BezierSegment) -> (BezierSegment, BezierSegment) {
        let p0 = segment.start
        let p1 = segment.control1
        let p2 = segment.control2
        let p3 = segment.end

        let p01 = midpoint(p0, p1)
        let p12 = midpoint(p1, p2)
        let p23 = midpoint(p2, p3)
        let p012 = midpoint(p01, p12)
        let p123 = midpoint(p12, p23)
        let p0123 = midpoint(p012, p123)

        return (
            BezierSegment(
                start: p0,
                control1: p01,
                control2: p012,
                end: p0123
            ),
            BezierSegment(
                start: p0123,
                control1: p123,
                control2: p23,
                end: p3
            )
        )
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    private static func lineIntersectsRect(start: CGPoint, end: CGPoint, rect: CGRect) -> Bool {
        let tl = CGPoint(x: rect.minX, y: rect.minY)
        let tr = CGPoint(x: rect.maxX, y: rect.minY)
        let bl = CGPoint(x: rect.minX, y: rect.maxY)
        let br = CGPoint(x: rect.maxX, y: rect.maxY)

        return segmentsIntersect(start, end, tl, tr)
            || segmentsIntersect(start, end, tr, br)
            || segmentsIntersect(start, end, br, bl)
            || segmentsIntersect(start, end, bl, tl)
    }

    private static func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ q1: CGPoint, _ q2: CGPoint) -> Bool {
        let o1 = orientation(p1, p2, q1)
        let o2 = orientation(p1, p2, q2)
        let o3 = orientation(q1, q2, p1)
        let o4 = orientation(q1, q2, p2)

        if o1 != o2 && o3 != o4 { return true }
        if o1 == 0 && onSegment(p1, q1, p2) { return true }
        if o2 == 0 && onSegment(p1, q2, p2) { return true }
        if o3 == 0 && onSegment(q1, p1, q2) { return true }
        if o4 == 0 && onSegment(q1, p2, q2) { return true }
        return false
    }

    private static func orientation(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Int {
        let value = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
        if abs(value) < 0.0001 { return 0 }
        return value > 0 ? 1 : 2
    }

    private static func onSegment(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let withinX = b.x >= min(a.x, c.x) - 0.0001 && b.x <= max(a.x, c.x) + 0.0001
        let withinY = b.y >= min(a.y, c.y) - 0.0001 && b.y <= max(a.y, c.y) + 0.0001
        return withinX && withinY
    }

}

extension BezierPathfinder {
    // MARK: - Bezier Math (Public)

    static func bezierPoint(on segment: BezierSegment, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        let t2 = t * t
        let t3 = t2 * t

        let x = mt3 * segment.start.x
            + 3 * mt2 * t * segment.control1.x
            + 3 * mt * t2 * segment.control2.x
            + t3 * segment.end.x
        let y = mt3 * segment.start.y
            + 3 * mt2 * t * segment.control1.y
            + 3 * mt * t2 * segment.control2.y
            + t3 * segment.end.y
        return CGPoint(x: x, y: y)
    }

    static func bezierTangent(on segment: BezierSegment, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t
        let dx1 = segment.control1.x - segment.start.x
        let dx2 = segment.control2.x - segment.control1.x
        let dx3 = segment.end.x - segment.control2.x
        let dy1 = segment.control1.y - segment.start.y
        let dy2 = segment.control2.y - segment.control1.y
        let dy3 = segment.end.y - segment.control2.y
        return CGPoint(
            x: 3 * mt2 * dx1 + 6 * mt * t * dx2 + 3 * t2 * dx3,
            y: 3 * mt2 * dy1 + 6 * mt * t * dy2 + 3 * t2 * dy3
        )
    }

}

private extension BezierPathfinder {
    // MARK: - Helpers

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x; let dy = a.y - b.y; return sqrt(dx * dx + dy * dy)
    }
    private static func normalize(_ v: CGPoint) -> CGPoint {
        let len = sqrt(v.x * v.x + v.y * v.y); guard len > 0 else { return .zero }
        return CGPoint(x: v.x / len, y: v.y / len)
    }
    private static func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, value)) }
    private static func portDirection(_ port: PortPosition, isStart: Bool) -> CGPoint {
        switch port {
        case .left: return isStart ? CGPoint(x: -1, y: 0) : CGPoint(x: 1, y: 0)
        case .right: return isStart ? CGPoint(x: 1, y: 0) : CGPoint(x: -1, y: 0)
        }
    }
    private static func direction(from a: CGPoint, to b: CGPoint) -> CGPoint {
        normalize(CGPoint(x: b.x - a.x, y: b.y - a.y))
    }
    private static func blendedDirection(preferred: CGPoint?, fallback: CGPoint, weight: CGFloat) -> CGPoint {
        let fn = normalize(fallback); guard let preferred else { return fn }
        let pn = normalize(preferred); if fn == .zero { return pn }
        let w = clamp(weight, 0, 1)
        return normalize(CGPoint(x: pn.x * w + fn.x * (1 - w), y: pn.y * w + fn.y * (1 - w)))
    }
    private static func endpointTangentLength(
        _ neighborDist: CGFloat,
        tension: CGFloat,
        clearance: CGFloat
    ) -> CGFloat {
        let base = min(max(neighborDist * 0.75, 30), 240)
        let s = 1 - tension * 0.9
        let minLen = max(6, clearance * (0.2 + 0.6 * (1 - tension)))
        return max(minLen, base * s)
    }
    private static func clampLength(_ v: CGPoint, max maxLen: CGFloat) -> CGPoint {
        let len = sqrt(v.x * v.x + v.y * v.y); guard len > 0 else { return .zero }
        if len <= maxLen { return v }; let s = maxLen / len
        return CGPoint(x: v.x * s, y: v.y * s)
    }
    private static func scale(_ v: CGPoint, _ factor: CGFloat) -> CGPoint {
        CGPoint(x: v.x * factor, y: v.y * factor)
    }
    private static func angleBetween(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let na = normalize(a); let nb = normalize(b)
        if na == .zero || nb == .zero { return 0 }
        return acos(clamp(na.x * nb.x + na.y * nb.y, -1, 1))
    }
}

/// A cubic bezier curve segment.
public struct BezierSegment: Equatable, Sendable {
    public let start: CGPoint
    public let control1: CGPoint
    public let control2: CGPoint
    public let end: CGPoint

    public init(start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint) {
        self.start = start
        self.control1 = control1
        self.control2 = control2
        self.end = end
    }
}
