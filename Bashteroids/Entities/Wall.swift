import SpriteKit

enum WallStrength {
    case strong, weak
}

/// One BATTLE wall. A chain of 3–6 rough quadrilateral segments arranged along
/// a meandering polyline. Each segment's strength is independent: strong
/// segments are indestructible, weak segments take 5 hp before vanishing.
final class Wall: Entity {
    static let weakChunkHP: Int = 5

    static let strongStroke = SKColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    static let weakStroke   = SKColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1)

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat            // bounding circle of the whole wall
    var alive: Bool = true
    private(set) var chunks: [Chunk] = []

    init(centerPosition: CGPoint,
         heading: CGFloat,
         segmentCount: Int,
         bendAmplitude: CGFloat,
         strengthBias: CGFloat,
         seed: UInt64) {
        // Conservative bounding-circle estimate: ignores bend.
        let halfLen = CGFloat(segmentCount) * BattleArena.segmentLength / 2
        let halfThick = BattleArena.segmentThickness / 2
        self.radius = sqrt(halfLen * halfLen + halfThick * halfThick) + 2

        let n = SKNode()
        n.position = centerPosition
        self.node = n

        var rng = SeededGenerator(seed: seed)
        self.chunks = Wall.makeSegmentChain(
            heading: heading,
            segmentCount: segmentCount,
            bendAmplitude: bendAmplitude,
            strengthBias: strengthBias,
            parent: n,
            rng: &rng
        )
    }

    func update(dt: TimeInterval) { /* walls don't move */ }

    /// Returns true if `point` is inside any live chunk. Side effect: weak
    /// chunks lose hp + erode, and the wall dies once all chunks are dead.
    func registerBulletHit(at point: CGPoint) -> Bool {
        let local = CGPoint(x: point.x - node.position.x,
                            y: point.y - node.position.y)

        for i in 0..<chunks.count {
            guard chunks[i].alive else { continue }
            if Wall.pointInPolygon(local, polygon: chunks[i].vertices) {
                if chunks[i].strength == .weak {
                    chunks[i].hp -= 1
                    if chunks[i].hp <= 0 {
                        chunks[i].shape.removeFromParent()
                    } else {
                        Wall.erodeChunk(&chunks[i])
                    }
                    if !chunks.contains(where: { $0.alive }) {
                        alive = false
                    }
                }
                return true
            }
        }
        return false
    }

    private static func erodeChunk(_ chunk: inout Chunk) {
        // Pick 1-2 vertices and pull them toward the chunk's local centroid by 8-14%.
        var rng = SeededGenerator(seed: UInt64(chunk.index) * 31 + UInt64(max(0, chunk.hp)))
        let nToMove = rng.cgFloat(in: 0...1) < 0.5 ? 1 : 2
        let count = chunk.originalVertices.count
        var newVerts = chunk.vertices
        for _ in 0..<nToMove {
            let idx = min(count - 1, Int(rng.cgFloat(in: 0...CGFloat(count - 1))))
            let pull = rng.cgFloat(in: 0.08...0.14)
            let v = newVerts[idx]
            newVerts[idx] = CGPoint(
                x: v.x + (chunk.centroid.x - v.x) * pull,
                y: v.y + (chunk.centroid.y - v.y) * pull
            )
        }
        chunk.vertices = newVerts

        let path = CGMutablePath()
        for (i, v) in newVerts.enumerated() {
            if i == 0 { path.move(to: v) } else { path.addLine(to: v) }
        }
        path.closeSubpath()
        chunk.shape.path = path
        chunk.shape.alpha = 0.5 + 0.1 * CGFloat(chunk.hp)
    }

    /// Standard ray-cast point-in-polygon test (works for any simple polygon).
    static func pointInPolygon(_ p: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xIntersect = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xIntersect { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Walks `segmentCount` quadrilateral segments along a polyline starting at
    /// the wall-local origin, advancing along the current heading by
    /// `BattleArena.segmentLength` each step and rotating the heading by a
    /// random amount in `[-bendAmplitude, +bendAmplitude]` between segments.
    /// Each segment rolls strong with probability `strengthBias`, else weak.
    private static func makeSegmentChain(heading initialHeading: CGFloat,
                                         segmentCount: Int,
                                         bendAmplitude: CGFloat,
                                         strengthBias: CGFloat,
                                         parent: SKNode,
                                         rng: inout SeededGenerator) -> [Chunk] {
        let stepLen = BattleArena.segmentLength
        let halfThick = BattleArena.segmentThickness / 2
        let jitter = BattleArena.segmentCornerJitter

        // Build the polyline path: N+1 knuckles, N segment headings.
        let halfChain = CGFloat(segmentCount) * stepLen / 2
        let startDir = CGPoint(x: cos(initialHeading), y: sin(initialHeading))
        var knuckles: [CGPoint] = [
            CGPoint(x: -startDir.x * halfChain, y: -startDir.y * halfChain)
        ]
        var segmentHeadings: [CGFloat] = []
        var theta = initialHeading
        for _ in 0..<segmentCount {
            segmentHeadings.append(theta)
            let dir = CGPoint(x: cos(theta), y: sin(theta))
            let last = knuckles[knuckles.count - 1]
            knuckles.append(CGPoint(x: last.x + dir.x * stepLen,
                                    y: last.y + dir.y * stepLen))
            theta += rng.cgFloat(in: -bendAmplitude...bendAmplitude)
        }

        // For each knuckle, compute its "wall direction" — endpoint knuckles
        // use the single adjacent segment's heading; interior knuckles use
        // the bisector (mean) of the two adjacent segment headings. Then
        // compute one perpendicular per knuckle.
        var perps: [CGPoint] = []
        for k in 0..<knuckles.count {
            let theta_k: CGFloat
            if k == 0 {
                theta_k = segmentHeadings[0]
            } else if k == knuckles.count - 1 {
                theta_k = segmentHeadings[segmentHeadings.count - 1]
            } else {
                // Bisector via averaged direction vector (handles wrap-around).
                let a = segmentHeadings[k - 1]
                let b = segmentHeadings[k]
                let avgX = cos(a) + cos(b)
                let avgY = sin(a) + sin(b)
                theta_k = atan2(avgY, avgX)
            }
            let d = CGPoint(x: cos(theta_k), y: sin(theta_k))
            perps.append(CGPoint(x: -d.y, y: d.x))
        }

        // Two jittered edge points per knuckle.
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []
        for k in 0..<knuckles.count {
            let p = perps[k]
            let kn = knuckles[k]
            leftEdge.append(CGPoint(
                x: kn.x + p.x * halfThick + rng.cgFloat(in: -jitter...jitter),
                y: kn.y + p.y * halfThick + rng.cgFloat(in: -jitter...jitter)
            ))
            rightEdge.append(CGPoint(
                x: kn.x - p.x * halfThick + rng.cgFloat(in: -jitter...jitter),
                y: kn.y - p.y * halfThick + rng.cgFloat(in: -jitter...jitter)
            ))
        }

        // Build segments. Each segment's CCW corner order:
        //   rightEdge[i], rightEdge[i+1], leftEdge[i+1], leftEdge[i]
        var chunks: [Chunk] = []
        chunks.reserveCapacity(segmentCount)
        for i in 0..<segmentCount {
            let backRight  = rightEdge[i]
            let frontRight = rightEdge[i + 1]
            let frontLeft  = leftEdge[i + 1]
            let backLeft   = leftEdge[i]

            let verts = [backRight, frontRight, frontLeft, backLeft]
            let centroid = CGPoint(
                x: (backRight.x + frontRight.x + frontLeft.x + backLeft.x) / 4,
                y: (backRight.y + frontRight.y + frontLeft.y + backLeft.y) / 4
            )

            let isStrong = rng.cgFloat(in: 0...1) < strengthBias
            let strength: WallStrength = isStrong ? .strong : .weak
            let color = isStrong ? Self.strongStroke : Self.weakStroke
            let hp    = isStrong ? Int.max : Self.weakChunkHP

            let shape = Shapes.wallChunk(vertices: verts, color: color)
            parent.addChild(shape)

            chunks.append(Chunk(
                centroid: centroid,
                vertices: verts,
                originalVertices: verts,
                hp: hp,
                shape: shape,
                index: i,
                strength: strength
            ))
        }

        return chunks
    }
}

/// One destructible piece of a wall.
struct Chunk {
    let centroid: CGPoint        // wall-local
    var vertices: [CGPoint]      // wall-local; current (eroded) shape
    let originalVertices: [CGPoint]
    var hp: Int
    let shape: SKShapeNode
    let index: Int               // 0..<segmentCount; used as RNG seed
    let strength: WallStrength
    var alive: Bool { hp > 0 }
}
