import SpriteKit

final class Snake: Entity {
    static let segmentCount: Int    = 24
    static let neckHalfWidth: CGFloat = 3     // body half-width at neck
    static let tailHalfWidth: CGFloat = 2     // body half-width at tail
    static let segmentSpacing: CGFloat = 8
    static let speed: CGFloat       = 80
    static let driftAmplitude: CGFloat = 0.85   // wider lateral swing → more meander
    static let driftRate: CGFloat   = 1.5      // slightly faster phase advance
    static let turnRate: CGFloat    = 1.4
    static let bulletHitsToKill: Int = 4

    // Head dimensions (local +x is the snake's heading).
    static let headHalfLength: CGFloat = 12
    static let headHalfWidth: CGFloat  = 8
    static let headInset: CGFloat      = 4    // octagonal corner inset
    static let headRadius: CGFloat     = 11   // collision approximation

    // Reference cyan. Tweak here if you want a different terminal accent.
    static let bodyColor = SKColor(red: 0.10, green: 0.95, blue: 0.95, alpha: 1)

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat   = headRadius
    var alive: Bool       = true

    var target: CGPoint?
    private(set) var hitsRemaining: Int = bulletHitsToKill

    private var heading: CGFloat
    private var driftPhase: CGFloat
    private var bodyPositions: [CGPoint]
    private let bodyOutline: SKShapeNode
    private let headNode: SKShapeNode

    init(position: CGPoint, baseHeading: CGFloat, seed: UInt64) {
        self.heading = baseHeading
        var rng = SeededGenerator(seed: seed)
        self.driftPhase = rng.cgFloat(in: 0 ... .pi * 2)

        var positions: [CGPoint] = []
        for i in 1...Self.segmentCount {
            let backward = CGPoint.fromAngle(baseHeading + .pi,
                                             length: CGFloat(i) * Self.segmentSpacing)
            positions.append(position + backward)
        }
        self.bodyPositions = positions

        let container = SKNode()
        container.position = position
        self.node = container

        let outline = SKShapeNode()
        outline.strokeColor = Self.bodyColor
        outline.fillColor   = .clear
        outline.lineWidth   = 1.5
        outline.lineJoin    = .miter
        container.addChild(outline)
        self.bodyOutline = outline

        let head = SKShapeNode(path: Snake.headOutlinePath())
        head.strokeColor = Self.bodyColor
        head.fillColor   = .clear
        head.lineWidth   = 1.5
        head.lineJoin    = .miter
        head.zRotation   = baseHeading
        container.addChild(head)
        self.headNode = head

        // Slit eyes (angled inward, like angry brows).
        for sign: CGFloat in [-1, 1] {
            let eye = SKShapeNode(path: Snake.eyePath(sign: sign))
            eye.fillColor   = Self.bodyColor
            eye.strokeColor = .clear
            head.addChild(eye)
        }

        // Two fang triangles at the front-bottom of the mouth.
        let fangs = SKShapeNode(path: Snake.fangsPath())
        fangs.strokeColor = Self.bodyColor
        fangs.fillColor   = .clear
        fangs.lineWidth   = 1.5
        fangs.lineJoin    = .miter
        head.addChild(fangs)

        syncRendering()
    }

    func update(dt: TimeInterval) {
        guard alive else { return }

        if let target {
            let targetDir = atan2(target.y - position.y, target.x - position.x)
            let diff = Snake.wrapAngle(targetDir - heading)
            let limit = Self.turnRate * CGFloat(dt)
            heading += max(-limit, min(limit, diff))
        }

        driftPhase += Self.driftRate * CGFloat(dt)
        let actualHeading = heading + sin(driftPhase) * Self.driftAmplitude

        velocity = CGPoint.fromAngle(actualHeading, length: Self.speed)
        position = position + velocity * CGFloat(dt)

        var prev = position
        for i in 0..<bodyPositions.count {
            let dir = (prev - bodyPositions[i]).normalized()
            bodyPositions[i] = prev - dir * Self.segmentSpacing
            prev = bodyPositions[i]
        }

        syncRendering()
    }

    func wrap(in bounds: CGRect) {
        var p = position
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if p.x < bounds.minX { dx = bounds.width;  p.x += bounds.width }
        else if p.x > bounds.maxX { dx = -bounds.width; p.x -= bounds.width }
        if p.y < bounds.minY { dy = bounds.height; p.y += bounds.height }
        else if p.y > bounds.maxY { dy = -bounds.height; p.y -= bounds.height }
        if dx != 0 || dy != 0 {
            position = p
            for i in 0..<bodyPositions.count {
                bodyPositions[i].x += dx
                bodyPositions[i].y += dy
            }
            syncRendering()
        }
    }

    /// Hits anywhere along the snake's body or head register.
    func hitTest(point: CGPoint, radius: CGFloat) -> Bool {
        let h = Self.headRadius + radius
        if position.distanceSquared(to: point) <= h * h { return true }
        for (i, p) in bodyPositions.enumerated() {
            // Use the segment's half-width plus a small fudge as the hit radius.
            let s = Self.halfWidth(at: i + 1) + 2 + radius
            if p.distanceSquared(to: point) <= s * s { return true }
        }
        return false
    }

    @discardableResult
    func registerBulletHit() -> Bool {
        hitsRemaining -= 1
        let flash = SKAction.sequence([
            .fadeAlpha(to: 0.3, duration: 0.05),
            .fadeAlpha(to: 1.0, duration: 0.10)
        ])
        bodyOutline.run(flash)
        headNode.run(flash)
        return hitsRemaining <= 0
    }

    // MARK: - Rendering

    private func syncRendering() {
        headNode.zRotation = heading
        bodyOutline.path   = buildBodyPath()
    }

    /// Builds the ribbon-outline polygon in container-local coords (head at origin).
    /// Open at the neck so the head shape closes the silhouette.
    private func buildBodyPath() -> CGPath {
        var trail: [CGPoint] = [position]
        trail.append(contentsOf: bodyPositions)
        let n = trail.count

        var leftEdge:  [CGPoint] = []
        var rightEdge: [CGPoint] = []
        leftEdge.reserveCapacity(n)
        rightEdge.reserveCapacity(n)

        for i in 0..<n {
            let dir = direction(at: i, in: trail)
            let perp = CGPoint(x: -dir.y, y: dir.x)
            let half = Self.halfWidth(at: i)
            leftEdge.append(trail[i]  + perp * half)
            rightEdge.append(trail[i] - perp * half)
        }

        let path = CGMutablePath()
        // Right edge from neck down to tail
        path.move(to: rightEdge[0] - position)
        for i in 1..<n {
            path.addLine(to: rightEdge[i] - position)
        }
        // Tail cap (flat)
        path.addLine(to: leftEdge[n - 1] - position)
        // Left edge back from tail to neck
        for i in stride(from: n - 2, through: 0, by: -1) {
            path.addLine(to: leftEdge[i] - position)
        }
        // Open at neck — the head outline visually closes the silhouette.
        return path
    }

    /// Tangent direction at trail index `i`, pointing forward (toward head).
    private func direction(at i: Int, in trail: [CGPoint]) -> CGPoint {
        if trail.count == 1 { return CGPoint.fromAngle(heading) }
        if i == 0 {
            let d = (trail[0] - trail[1]).normalized()
            return d.lengthSquared > 0 ? d : CGPoint.fromAngle(heading)
        } else if i == trail.count - 1 {
            return (trail[i - 1] - trail[i]).normalized()
        } else {
            return (trail[i - 1] - trail[i + 1]).normalized()
        }
    }

    /// Tapered half-width along the trail. Index 0 = head-end (neck width).
    static func halfWidth(at i: Int) -> CGFloat {
        let total = CGFloat(segmentCount)
        let t = max(0, min(1, CGFloat(i) / total))
        let taperStart: CGFloat = 0.75
        if t < taperStart { return neckHalfWidth }
        let s = (t - taperStart) / (1 - taperStart)
        return neckHalfWidth - s * (neckHalfWidth - tailHalfWidth)
    }

    // MARK: - Head / face paths

    /// Octagonal head outline. Open at the back so the body's neck flows in.
    private static func headOutlinePath() -> CGPath {
        let hl = headHalfLength
        let hw = headHalfWidth
        let inset = headInset
        let path = CGMutablePath()
        // Start at back-top — the neck-attach point on the upper edge.
        path.move(to: CGPoint(x: -hl,         y:  neckHalfWidth))
        path.addLine(to: CGPoint(x: -hl,      y:  hw))
        path.addLine(to: CGPoint(x: -hl + inset, y:  hw))
        path.addLine(to: CGPoint(x:  hl - inset, y:  hw))
        path.addLine(to: CGPoint(x:  hl,      y:  hw - inset))
        path.addLine(to: CGPoint(x:  hl,      y: -hw + inset))
        path.addLine(to: CGPoint(x:  hl - inset, y: -hw))
        path.addLine(to: CGPoint(x: -hl + inset, y: -hw))
        path.addLine(to: CGPoint(x: -hl,      y: -hw))
        path.addLine(to: CGPoint(x: -hl,      y: -neckHalfWidth))
        return path
    }

    /// One angular slit eye. `sign = +1` for the upper, `-1` for the lower.
    private static func eyePath(sign: CGFloat) -> CGPath {
        let yMid: CGFloat = sign * 4
        let path = CGMutablePath()
        // Slanted parallelogram pointing forward+outward.
        path.move(to: CGPoint(x: 2, y: yMid - sign * 1.5))
        path.addLine(to: CGPoint(x: 7, y: yMid + sign * 1.8))
        path.addLine(to: CGPoint(x: 9, y: yMid + sign * 0.8))
        path.addLine(to: CGPoint(x: 4, y: yMid - sign * 2.5))
        path.closeSubpath()
        return path
    }

    /// Two small triangular fangs at the front of the mouth.
    private static func fangsPath() -> CGPath {
        let path = CGMutablePath()
        // Upper fang
        path.move(to: CGPoint(x: 11, y: 2))
        path.addLine(to: CGPoint(x: 14, y: 0.5))
        path.addLine(to: CGPoint(x: 12, y: 0))
        path.closeSubpath()
        // Lower fang
        path.move(to: CGPoint(x: 11, y: -2))
        path.addLine(to: CGPoint(x: 14, y: -0.5))
        path.addLine(to: CGPoint(x: 12, y:  0))
        path.closeSubpath()
        return path
    }

    private static func wrapAngle(_ a: CGFloat) -> CGFloat {
        var x = a
        while x > .pi  { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }
}
