import SpriteKit

enum WallStrength {
    case strong, weak
}

/// One destructible (or indestructible) wall. Owns 1+ chunks. Strong walls have
/// a single chunk with .max hp. Weak walls have 4 wedge chunks with hp 5 each.
final class Wall: Entity {
    static let weakChunkHP: Int = 5
    static let weakChunkCount: Int = 4

    static let strongStroke = SKColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    static let weakStroke   = SKColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1)

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat              // bounding circle of the whole wall
    var alive: Bool = true
    let strength: WallStrength
    private(set) var chunks: [Chunk] = []

    init(strength: WallStrength,
         centerPosition: CGPoint,
         radius: CGFloat,
         seed: UInt64) {
        self.strength = strength
        self.radius = radius
        let n = SKNode()
        n.position = centerPosition
        self.node = n

        let outerVerts = Shapes.wallVertices(radius: radius, seed: seed)
        switch strength {
        case .strong:
            let chunk = Chunk(
                centroid: .zero,
                vertices: outerVerts,
                originalVertices: outerVerts,
                hp: .max,
                shape: Shapes.wallChunk(vertices: outerVerts, color: Self.strongStroke),
                index: 0
            )
            n.addChild(chunk.shape)
            self.chunks = [chunk]
        case .weak:
            self.chunks = Wall.makeWeakWedges(from: outerVerts, parent: n)
        }
    }

    func update(dt: TimeInterval) { /* walls don't move */ }

    /// Returns true if `point` is inside any live chunk. Side effect: if the
    /// hit chunk is weak, decrements its hp and updates the visual.
    func registerBulletHit(at point: CGPoint) -> Bool {
        let local = CGPoint(x: point.x - node.position.x,
                            y: point.y - node.position.y)

        for i in 0..<chunks.count {
            guard chunks[i].alive else { continue }
            if Wall.pointInPolygon(local, polygon: chunks[i].vertices) {
                if strength == .weak {
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
        let nToMove = Int(rng.cgFloat(in: 1.0...2.0))
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

    /// Standard ray-cast point-in-polygon test (CCW polygon).
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

    /// Splits the wall polygon into 4 radial wedges from its centroid. Each
    /// wedge is convex, ~90° of the perimeter, with a small inner gap so
    /// chunks read as visually distinct from the start.
    private static func makeWeakWedges(from outerVerts: [CGPoint], parent: SKNode) -> [Chunk] {
        let centroid = polygonCentroid(outerVerts)
        let count = weakChunkCount
        var perAngleSlot: [[CGPoint]] = Array(repeating: [], count: count)
        // Bin outer vertices by their angle relative to the centroid.
        for v in outerVerts {
            let a = atan2(v.y - centroid.y, v.x - centroid.x)
            let normalized = a < 0 ? a + 2 * .pi : a
            let slot = min(count - 1, Int(normalized / (2 * .pi) * CGFloat(count)))
            perAngleSlot[slot].append(v)
        }
        // For each wedge, build a convex polygon: centroid + the slot's
        // outer vertices (sorted by angle) with a small inset toward the
        // centroid for the inner gap.
        let innerGap: CGFloat = 4
        var chunks: [Chunk] = []
        for (i, slotVerts) in perAngleSlot.enumerated() {
            // Add a leading + trailing boundary point at the wedge's
            // angular limits so all four wedges tile cleanly.
            let startAngle = (CGFloat(i)     / CGFloat(count)) * 2 * .pi
            let endAngle   = (CGFloat(i + 1) / CGFloat(count)) * 2 * .pi
            let r = max(slotVerts.map { hypot($0.x - centroid.x, $0.y - centroid.y) }.max() ?? 0,
                        20)
            let leading  = CGPoint(x: centroid.x + r * cos(startAngle),
                                   y: centroid.y + r * sin(startAngle))
            let trailing = CGPoint(x: centroid.x + r * cos(endAngle),
                                   y: centroid.y + r * sin(endAngle))
            var ringVerts: [CGPoint] = [leading] + slotVerts + [trailing]
            // Sort by normalized angle (0…2π) to match the binning step;
            // raw atan2 (-π…π) would break the wedge in the 180°–270° slot
            // because the leading-boundary point at +π would sort after
            // slot vertices at -π+ε, producing a self-intersecting polygon.
            let norm: (CGPoint) -> CGFloat = { v in
                let a = atan2(v.y - centroid.y, v.x - centroid.x)
                return a < 0 ? a + 2 * .pi : a
            }
            ringVerts.sort { norm($0) < norm($1) }
            // Build wedge: ring vertices + an inset centroid point.
            let wedge = ringVerts + [CGPoint(x: centroid.x + cos((startAngle + endAngle) / 2) * innerGap,
                                              y: centroid.y + sin((startAngle + endAngle) / 2) * innerGap)]
            let shape = Shapes.wallChunk(vertices: wedge, color: weakStroke)
            parent.addChild(shape)
            chunks.append(Chunk(
                centroid: centroid,
                vertices: wedge,
                originalVertices: wedge,
                hp: weakChunkHP,
                shape: shape,
                index: i
            ))
        }
        return chunks
    }

    private static func polygonCentroid(_ verts: [CGPoint]) -> CGPoint {
        var cx: CGFloat = 0
        var cy: CGFloat = 0
        for v in verts { cx += v.x; cy += v.y }
        let n = CGFloat(verts.count)
        return CGPoint(x: cx / n, y: cy / n)
    }
}

/// One destructible piece of a wall.
struct Chunk {
    let centroid: CGPoint        // wall-local
    var vertices: [CGPoint]      // wall-local; current (eroded) shape
    let originalVertices: [CGPoint]
    var hp: Int
    let shape: SKShapeNode
    let index: Int               // 0..<weakChunkCount; used as RNG seed
    var alive: Bool { hp > 0 }
}
