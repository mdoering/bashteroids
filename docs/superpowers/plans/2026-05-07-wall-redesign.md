# BATTLE Wall Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace round asteroid-shaped BATTLE walls with elongated polyline walls of rough quadrilateral segments, with strength tracked per-segment instead of per-wall.

**Architecture:** Single atomic commit overhauling four tightly-coupled files (`Wall.swift`, `BattleArena.swift`, `LevelRoster.swift`, `Shapes.swift`). The collision pipeline (`Collision.swift`, `BattleArena.reflectShipsOffWalls`) is chunk-agnostic and stays unchanged. README update lands as a follow-up commit.

**Tech Stack:** Swift 5 + SpriteKit. Single Xcode target. Three destinations (iOS / Mac Catalyst / tvOS).

**Spec:** `docs/superpowers/specs/2026-05-07-wall-redesign-design.md`

---

## File Structure

**Modified files (Task 1 — atomic):**
- `Bashteroids/Entities/Wall.swift` — `Wall.strength` field removed; `Chunk.strength` added; `Wall.init(...)` signature replaced; `makeSegmentChain(...)` added; `makeWeakWedges(...)` and `polygonCentroid(...)` removed; `Wall.weakChunkCount` removed (chunks vary 3–6 per wall now).
- `Bashteroids/Systems/LevelRoster.swift` — `BattleConfig` simplified to `(walls, mazeClusters)`; switch table re-tuned for the larger wall scale.
- `Bashteroids/Systems/BattleArena.swift` — constants block rewritten; `generate(...)` rewritten for the new construction and perpendicular cluster offsets.
- `Bashteroids/Render/Shapes.swift` — `wallVertices(...)` helper removed (no longer used).

**Modified file (Task 2):**
- `README.md` — wall description updated for the new geometry / mixed-strength model.

**No new files. No deletions of whole files.**

The four-file Task 1 is intentionally atomic because the API surfaces are tightly coupled: `Wall.init` parameters change, `BattleArena.generate` is the sole caller, and `LevelRoster.BattleConfig` is consumed only by `BattleArena.generate`. Splitting would leave the build red between commits.

---

## Task 1: Wall geometry + arena generation rewrite (atomic)

**Files:**
- Modify (whole-file rewrite): `Bashteroids/Entities/Wall.swift`
- Modify (whole-file rewrite): `Bashteroids/Systems/BattleArena.swift`
- Modify: `Bashteroids/Systems/LevelRoster.swift` — replace `BattleConfig` struct + `battleConfig(for:)` body
- Modify: `Bashteroids/Render/Shapes.swift` — remove `wallVertices(radius:seed:count:)` helper

### Step 1: Rewrite `Bashteroids/Entities/Wall.swift`

Replace the entire file contents with:

```swift
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

        // Center the chain around the wall's local origin: start at -halfChain
        // along the initial heading, end at +halfChain.
        let halfChain = CGFloat(segmentCount) * stepLen / 2
        let startDir = CGPoint(x: cos(initialHeading), y: sin(initialHeading))
        var cursor = CGPoint(x: -startDir.x * halfChain,
                             y: -startDir.y * halfChain)
        var theta = initialHeading

        var chunks: [Chunk] = []
        chunks.reserveCapacity(segmentCount)

        for i in 0..<segmentCount {
            let dir  = CGPoint(x: cos(theta), y: sin(theta))
            let perp = CGPoint(x: -dir.y, y: dir.x)
            let next = CGPoint(x: cursor.x + dir.x * stepLen,
                               y: cursor.y + dir.y * stepLen)

            // Four CCW corners with per-corner jitter on x and y.
            let jx: () -> CGFloat = { rng.cgFloat(in: -jitter...jitter) }

            let backRight  = CGPoint(x: cursor.x - perp.x * halfThick + jx(),
                                     y: cursor.y - perp.y * halfThick + jx())
            let frontRight = CGPoint(x: next.x   - perp.x * halfThick + jx(),
                                     y: next.y   - perp.y * halfThick + jx())
            let frontLeft  = CGPoint(x: next.x   + perp.x * halfThick + jx(),
                                     y: next.y   + perp.y * halfThick + jx())
            let backLeft   = CGPoint(x: cursor.x + perp.x * halfThick + jx(),
                                     y: cursor.y + perp.y * halfThick + jx())

            let verts = [backRight, frontRight, frontLeft, backLeft]
            let centroid = CGPoint(
                x: (backRight.x + frontRight.x + frontLeft.x + backLeft.x) / 4,
                y: (backRight.y + frontRight.y + frontLeft.y + backLeft.y) / 4
            )

            let isStrong = rng.cgFloat(in: 0...1) <= strengthBias
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

            cursor = next
            theta += rng.cgFloat(in: -bendAmplitude...bendAmplitude)
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
```

### Step 2: Rewrite `Bashteroids/Systems/BattleArena.swift`

Replace the entire file contents with:

```swift
import SpriteKit

enum BattleArena {
    static let edgeMargin: CGFloat = 80
    static let interWallMargin: CGFloat = 60
    static let segmentLength: CGFloat = 50
    static let segmentThickness: CGFloat = 30
    static let segmentCornerJitter: CGFloat = 5
    static let segmentCountRange: ClosedRange<Int> = 3...6
    static let bendAmplitudeRange: ClosedRange<CGFloat> = 0...0.6
    static let strengthBiasRange: ClosedRange<CGFloat> = 0...1
    static let mazeClusterGap: CGFloat = 100
    static let placementTries = 50

    /// Generate the wall set for a BATTLE round. Caller adds each `wall.node`
    /// as a child of the GameScene.
    static func generate(in bounds: CGRect, level: Int, seed: UInt64) -> [Wall] {
        var rng = SeededGenerator(seed: seed)
        let cfg = LevelRoster.battleConfig(for: level)

        var walls: [Wall] = []

        // Maze clusters first: pairs of parallel walls forming corridors.
        let pairWalls = min(cfg.mazeClusters * 2, cfg.walls)
        var clustersToPlace = cfg.mazeClusters
        var pairWallsPlaced = 0

        while clustersToPlace > 0 && pairWallsPlaced < pairWalls {
            let (heading, segCount, bend, bias) = drawWallParams(rng: &rng)
            let radius = wallRadius(segmentCount: segCount)

            guard let anchor = pickOpenSpot(in: bounds, walls: walls,
                                            radius: radius, rng: &rng) else {
                clustersToPlace -= 1
                continue
            }
            walls.append(Wall(
                centerPosition: anchor,
                heading: heading,
                segmentCount: segCount,
                bendAmplitude: bend,
                strengthBias: bias,
                seed: rng.next()
            ))
            pairWallsPlaced += 1

            // Partner: parallel to the primary, offset perpendicular to its
            // initial heading by mazeClusterGap (random side). Use the
            // partner's own radius for the overlap check.
            let perpSign: CGFloat = rng.cgFloat(in: 0...1) < 0.5 ? 1 : -1
            let perp = CGPoint(x: -sin(heading) * perpSign,
                               y:  cos(heading) * perpSign)
            let partnerPos = CGPoint(
                x: anchor.x + perp.x * mazeClusterGap,
                y: anchor.y + perp.y * mazeClusterGap)
            let (_, partSeg, partBend, partBias) = drawWallParams(rng: &rng)
            let partRadius = wallRadius(segmentCount: partSeg)

            if pairWallsPlaced < pairWalls,
               rectInsetByEdge(bounds).contains(partnerPos),
               !overlapsAny(partnerPos, radius: partRadius, walls: walls) {
                walls.append(Wall(
                    centerPosition: partnerPos,
                    heading: heading,
                    segmentCount: partSeg,
                    bendAmplitude: partBend,
                    strengthBias: partBias,
                    seed: rng.next()
                ))
                pairWallsPlaced += 1
            }
            clustersToPlace -= 1
        }

        // Fill remaining wall slots with single placements.
        let remaining = cfg.walls - walls.count
        for _ in 0..<max(0, remaining) {
            let (heading, segCount, bend, bias) = drawWallParams(rng: &rng)
            let radius = wallRadius(segmentCount: segCount)
            if let pos = pickOpenSpot(in: bounds, walls: walls,
                                      radius: radius, rng: &rng) {
                walls.append(Wall(
                    centerPosition: pos,
                    heading: heading,
                    segmentCount: segCount,
                    bendAmplitude: bend,
                    strengthBias: bias,
                    seed: rng.next()
                ))
            }
        }

        return walls
    }

    private static func drawWallParams(rng: inout SeededGenerator)
        -> (heading: CGFloat, segmentCount: Int, bend: CGFloat, bias: CGFloat) {
        let heading = rng.cgFloat(in: 0...(.pi * 2))
        let segCount = Int(rng.cgFloat(
            in: CGFloat(segmentCountRange.lowerBound)
                ...CGFloat(segmentCountRange.upperBound) + 0.999))
        let bend = rng.cgFloat(in: bendAmplitudeRange)
        let bias = rng.cgFloat(in: strengthBiasRange)
        return (heading, min(segCount, segmentCountRange.upperBound), bend, bias)
    }

    private static func wallRadius(segmentCount: Int) -> CGFloat {
        let halfLen = CGFloat(segmentCount) * segmentLength / 2
        let halfThick = segmentThickness / 2
        return sqrt(halfLen * halfLen + halfThick * halfThick) + 2
    }

    // MARK: - Geometry helpers

    private static func rectInsetByEdge(_ bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: edgeMargin, dy: edgeMargin)
    }

    private static func overlapsAny(_ p: CGPoint, radius: CGFloat, walls: [Wall]) -> Bool {
        for w in walls {
            let need = w.radius + radius + interWallMargin
            if w.node.position.distanceSquared(to: p) < need * need {
                return true
            }
        }
        return false
    }

    private static func pickOpenSpot(in bounds: CGRect,
                                     walls: [Wall],
                                     radius: CGFloat,
                                     rng: inout SeededGenerator) -> CGPoint? {
        let inner = rectInsetByEdge(bounds)
        guard inner.width > 0 && inner.height > 0 else { return nil }
        for _ in 0..<placementTries {
            let p = CGPoint(x: rng.cgFloat(in: inner.minX...inner.maxX),
                            y: rng.cgFloat(in: inner.minY...inner.maxY))
            if !overlapsAny(p, radius: radius, walls: walls) { return p }
        }
        return nil
    }

    // MARK: - Ship-vs-wall reflection

    /// Apply ship-vs-wall reflection physics in-place. Returns true if the
    /// ship was reflected (used by callers for sound effects).
    @discardableResult
    static func reflectShipsOffWalls(_ ships: [Ship], walls: [Wall]) -> Bool {
        var reflected = false
        for ship in ships where ship.alive {
            let shipPos = ship.position
            for wall in walls where wall.alive {
                let wallPos = wall.node.position
                let outer = wall.radius + ship.radius
                if shipPos.distanceSquared(to: wallPos) > outer * outer { continue }

                for chunkIdx in 0..<wall.chunks.count {
                    guard wall.chunks[chunkIdx].alive else { continue }
                    let chunk = wall.chunks[chunkIdx]
                    if reflectIfNeeded(ship: ship, wall: wall, chunk: chunk) {
                        reflected = true
                    }
                }
            }
        }
        return reflected
    }

    private static func reflectIfNeeded(ship: Ship, wall: Wall, chunk: Chunk) -> Bool {
        let wallPos = wall.node.position
        let localShip = CGPoint(x: ship.position.x - wallPos.x,
                                y: ship.position.y - wallPos.y)

        var bestPenetration: CGFloat = .infinity
        var bestNormal: CGPoint = .zero

        let n = chunk.vertices.count
        for i in 0..<n {
            let a = chunk.vertices[i]
            let b = chunk.vertices[(i + 1) % n]
            let edge = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let len = hypot(edge.x, edge.y)
            guard len > 0 else { continue }

            // Outward normal (right-hand perpendicular for CCW polygon).
            let nx = edge.y / len
            let ny = -edge.x / len
            let normal = CGPoint(x: nx, y: ny)

            let toShip = CGPoint(x: localShip.x - a.x, y: localShip.y - a.y)
            let signedDist = toShip.x * normal.x + toShip.y * normal.y

            // Separating axis: ship is fully outside this edge plane.
            if signedDist >= ship.radius { return false }

            // SAT: track the edge with the MINIMUM penetration. That's the
            // axis closest to separation, i.e. the correct response normal.
            let penetration = ship.radius - signedDist
            if penetration < bestPenetration {
                bestPenetration = penetration
                bestNormal = normal
            }
        }

        guard bestPenetration.isFinite, bestPenetration > 0 else { return false }

        // Only reflect if the ship is moving INTO the wall.
        let vn = ship.velocity.x * bestNormal.x + ship.velocity.y * bestNormal.y
        guard vn < 0 else {
            // Already moving outward — just nudge out so we don't re-trigger.
            ship.position = CGPoint(x: ship.position.x + bestNormal.x * bestPenetration,
                                    y: ship.position.y + bestNormal.y * bestPenetration)
            return false
        }

        // Reflect velocity across the normal, with 50% speed reduction.
        let reflectedVx = (ship.velocity.x - 2 * vn * bestNormal.x) * 0.5
        let reflectedVy = (ship.velocity.y - 2 * vn * bestNormal.y) * 0.5
        ship.velocity = CGPoint(x: reflectedVx, y: reflectedVy)

        // Push ship outside by the penetration depth + a small epsilon.
        ship.position = CGPoint(
            x: ship.position.x + bestNormal.x * (bestPenetration + 0.5),
            y: ship.position.y + bestNormal.y * (bestPenetration + 0.5)
        )
        return true
    }
}
```

The `reflectShipsOffWalls` and `reflectIfNeeded` blocks are byte-for-byte identical to the existing implementation (the spec is explicit that collision math is unchanged). Pasting them in keeps the file self-contained.

### Step 3: Update `Bashteroids/Systems/LevelRoster.swift`

Find the existing `BattleConfig` struct and `battleConfig(for:)` extension. Replace them with:

```swift
struct BattleConfig {
    let walls: Int
    let mazeClusters: Int
}

extension LevelRoster {
    static func battleConfig(for level: Int) -> BattleConfig {
        let l = max(1, min(9, level))
        switch l {
        case 1: return BattleConfig(walls: 3,  mazeClusters: 0)
        case 2: return BattleConfig(walls: 4,  mazeClusters: 0)
        case 3: return BattleConfig(walls: 5,  mazeClusters: 0)
        case 4: return BattleConfig(walls: 5,  mazeClusters: 1)
        case 5: return BattleConfig(walls: 6,  mazeClusters: 1)
        case 6: return BattleConfig(walls: 7,  mazeClusters: 1)
        case 7: return BattleConfig(walls: 8,  mazeClusters: 2)
        case 8: return BattleConfig(walls: 9,  mazeClusters: 2)
        case 9: return BattleConfig(walls: 10, mazeClusters: 3)
        default: return BattleConfig(walls: 3, mazeClusters: 0)
        }
    }
}
```

The pre-existing parts of `LevelRoster.swift` (the `LevelConfig` struct, `LevelRoster.config(for:)`, the curated array, `extrapolated(for:)`) are unchanged.

### Step 4: Remove `wallVertices(...)` from `Bashteroids/Render/Shapes.swift`

Locate the helper:

```swift
    /// Builds the local-coordinate vertices of an irregular hollow polygon
    /// suitable for a wall. Same `seed` ⇒ same shape. Vertices are returned
    /// CCW around the polygon centroid.
    static func wallVertices(radius: CGFloat, seed: UInt64, count: Int = 9) -> [CGPoint] {
        var rng = SeededGenerator(seed: seed)
        var verts: [CGPoint] = []
        verts.reserveCapacity(count)
        for i in 0..<count {
            let baseAngle = CGFloat(i) / CGFloat(count) * .pi * 2
            let angleJitter = rng.cgFloat(in: -0.10...0.10)
            let radiusJitter = rng.cgFloat(in: 0.85...1.10)
            let r = radius * radiusJitter
            let a = baseAngle + angleJitter
            verts.append(CGPoint(x: r * cos(a), y: r * sin(a)))
        }
        return verts
    }
```

Delete the whole method. `Shapes.wallChunk(vertices:color:)` stays — it's still used by `Wall.makeSegmentChain`.

### Step 5: Build all three destinations

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three end with `** BUILD SUCCEEDED **`. Zero new warnings beyond the pre-existing `appintentsmetadataprocessor` advisory.

If a build fails, the most likely issues are:

1. **Stray reference to the old `Wall.strength` field somewhere.** Run `grep -rn 'wall\.strength\|Wall.strength' Bashteroids/` — only `Chunk.strength` and `WallStrength` references (the enum) should remain. The `Wall.strength` property is gone.

2. **Stray reference to `Wall.weakChunkCount` or `WallVertices`.** Run `grep -rn 'weakChunkCount\|wallVertices' Bashteroids/` — should be empty.

3. **Stray reference to old `BattleConfig.strong` / `BattleConfig.weak` fields.** Run `grep -rn 'cfg\.strong\|cfg\.weak\|BattleConfig.*strong' Bashteroids/` — only `cfg.walls` and `cfg.mazeClusters` should appear.

4. **Stray reference to the old `Wall(strength:centerPosition:radius:seed:)` initializer signature.** Run `grep -rn 'Wall(strength:' Bashteroids/` — should be empty.

Fix any matches found. If something else fails, read the build error and report.

### Step 6: Commit

```bash
git add Bashteroids/Entities/Wall.swift \
        Bashteroids/Systems/BattleArena.swift \
        Bashteroids/Systems/LevelRoster.swift \
        Bashteroids/Render/Shapes.swift
git commit -m "feat(battle): elongated polyline walls with per-chunk strength

Replaces round asteroid-shaped walls with chains of 3-6 rough
quadrilateral segments arranged along a meandering polyline.
Strength moves from the wall to the segment, so a single wall
can mix solid and destructible sections (each segment rolls
strong with probability = per-wall strengthBias).

Per-wall: free-rotated initial heading, bendAmplitude in
[0, 0.6 rad] for per-step rotation jitter, strengthBias in
[0, 1]. Maze cluster partners are now placed perpendicular to
the primary's heading instead of along a cardinal axis.

LevelRoster.BattleConfig drops (strong, weak) for a single
walls field. Counts retuned for the larger wall footprint.
The collision pipeline (bullet erosion + ship reflection) is
chunk-agnostic and unchanged."
```

---

## Task 2: README documentation

**Files:**
- Modify: `README.md`

### Step 1: Update the Modes section's Battle bullet

The bullet currently mentions "destructible vector walls" without specifics. Find the BATTLE bullet text in the Modes section and update the wall-related clause to:

```
The arena is dotted with **elongated walls** — chains of 3–6 rough vector segments along a meandering polyline. Each segment is independently **strong** (warm gray, indestructible — bullets die, ships bounce off losing 50% of their normal-component velocity) or **weak** (warm orange, 5 hp — bullets erode the segment visually as it loses hp). A single wall can mix strong and weak segments, so some walls are solid barriers, some are tear-down-able, and many are partial.
```

### Step 2: Update the Entities table

Find the existing two wall rows ("Wall (strong)" and "Wall (weak)" — both listed as separate entities). Replace both with a single row:

```markdown
| **Wall (BATTLE)** | — | per-segment | A chain of 3–6 rough quadrilateral segments along a meandering polyline. Each segment is independently strong (warm gray, indestructible) or weak (warm orange, 5 hp). Bullets die on any segment; weak segments visually erode and vanish at 0 hp. Ships bounce off any segment, losing 50% of their normal-component velocity. The wall dies once all its segments are destroyed; walls with strong segments persist forever. Only spawns in BATTLE mode. | — |
```

### Step 3: Final smoke build all three destinations

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero new warnings.

### Step 4: Commit

```bash
git add README.md
git commit -m "docs(readme): describe new elongated polyline walls

Replaces the two strong/weak wall entries with a single BATTLE
wall row that explains the polyline + per-segment strength
model. Updates the Modes section's Battle bullet to match."
```

---

## Manual verification (after both tasks land)

The headless build can't exercise the new wall geometry visually. Manual checks:

1. Run on Mac Catalyst, start a BATTLE round at L1.
2. Confirm walls are visibly elongated (not roundish) with rough/jagged outlines.
3. Confirm walls run at random angles (not just horizontal/vertical).
4. Confirm some walls are entirely gray (solid), some entirely orange (destructible), some mixed.
5. Shoot a weak segment 5 times — confirm it erodes visually (vertices pull in, alpha drops) and vanishes.
6. Fly a ship into a wall — confirm bounce physics (50% speed loss on the bounce).
7. Try a wall with strong segments and weak ones in the middle — shoot through the weak section, confirm a corridor opens up.
8. Increase the level (1 → 9) and confirm wall density increases roughly linearly.
9. Confirm maze clusters at L4+ form parallel pairs (not scattered).
