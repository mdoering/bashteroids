import SpriteKit

enum BattleArena {
    static let edgeMargin: CGFloat = 80
    static let interWallMargin: CGFloat = 80
    static let strongRadiusRange: ClosedRange<CGFloat> = 35...55
    static let weakRadiusRange:   ClosedRange<CGFloat> = 25...40
    static let mazeClusterGap: CGFloat = 120
    static let placementTries = 50

    /// Generate the wall set for a BATTLE round. Caller adds each Wall.node
    /// as a child of the GameScene.
    static func generate(in bounds: CGRect, level: Int, seed: UInt64) -> [Wall] {
        var rng = SeededGenerator(seed: seed)
        let cfg = LevelRoster.battleConfig(for: level)
        let scale: CGFloat = 1 + CGFloat(level - 1) * 0.05

        var walls: [Wall] = []

        // Strong walls first.
        for _ in 0..<cfg.strong {
            let r = rng.cgFloat(in: strongRadiusRange) * scale
            if let pos = pickOpenSpot(in: bounds, walls: walls, radius: r, rng: &rng) {
                walls.append(Wall(strength: .strong,
                                  centerPosition: pos,
                                  radius: r,
                                  seed: rng.next()))
            }
        }

        // Weak walls — split into clustered (maze) and standalone.
        let standaloneWeak = max(0, cfg.weak - cfg.mazeClusters * 2)

        for _ in 0..<cfg.mazeClusters {
            // A cluster is 2 weak walls in a short L (or line) ~120 px apart.
            let r = rng.cgFloat(in: weakRadiusRange) * scale
            guard let anchor = pickOpenSpot(in: bounds, walls: walls,
                                            radius: r, rng: &rng) else { continue }
            walls.append(Wall(strength: .weak,
                              centerPosition: anchor,
                              radius: r,
                              seed: rng.next()))
            // Place the partner along a random cardinal direction.
            let dir = [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0),
                       CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)]
                .randomElement(using: &rng) ?? CGPoint(x: 1, y: 0)
            let partnerPos = CGPoint(
                x: anchor.x + dir.x * mazeClusterGap,
                y: anchor.y + dir.y * mazeClusterGap)
            // Only place the partner if it's still inside bounds + clear.
            if rectInsetByEdge(bounds).contains(partnerPos),
               !overlapsAny(partnerPos, radius: r, walls: walls) {
                walls.append(Wall(strength: .weak,
                                  centerPosition: partnerPos,
                                  radius: r,
                                  seed: rng.next()))
            }
        }

        for _ in 0..<standaloneWeak {
            let r = rng.cgFloat(in: weakRadiusRange) * scale
            if let pos = pickOpenSpot(in: bounds, walls: walls, radius: r, rng: &rng) {
                walls.append(Wall(strength: .weak,
                                  centerPosition: pos,
                                  radius: r,
                                  seed: rng.next()))
            }
        }

        return walls
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
                // Broad-phase: bounding circle of the whole wall.
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

        var bestPenetration: CGFloat = -.infinity
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

            // Distance from localShip to the line through (a,b).
            let toShip = CGPoint(x: localShip.x - a.x, y: localShip.y - a.y)
            let signedDist = toShip.x * normal.x + toShip.y * normal.y

            if signedDist < ship.radius {
                // Inside this edge plane (or close to it). Track the deepest
                // edge — that's the one we reflect off.
                let penetration = ship.radius - signedDist
                if penetration > bestPenetration {
                    bestPenetration = penetration
                    bestNormal = normal
                }
            }
        }

        guard bestPenetration > 0 else { return false }

        // Only reflect if the ship is moving INTO the wall.
        let vn = ship.velocity.x * bestNormal.x + ship.velocity.y * bestNormal.y
        guard vn < 0 else {
            // Already moving outward — just nudge out so we don't re-trigger.
            ship.position = CGPoint(x: ship.position.x + bestNormal.x * bestPenetration,
                                    y: ship.position.y + bestNormal.y * bestPenetration)
            return false
        }

        // Reflect velocity across the normal, with 50% energy loss.
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
