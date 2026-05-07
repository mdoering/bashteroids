import SpriteKit

enum BattleArena {
    static let edgeMargin: CGFloat = 200       // walls cluster centrally; perimeter stays open for ricochet
    static let interWallMargin: CGFloat = 60
    static let asteroidEdgeMargin: CGFloat = 100
    static let staticAsteroidRadiusRange: ClosedRange<CGFloat> = 18...32
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
            in: CGFloat(segmentCountRange.lowerBound)...(CGFloat(segmentCountRange.upperBound) + 0.999)))
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

    /// Place static asteroids at non-overlapping spots inside the arena.
    /// Caller constructs Asteroid entities with these (position, radius, seed)
    /// triples and `velocity = .zero`. Asteroid placement uses a smaller
    /// edge margin than walls so the perimeter still has some content,
    /// just less dense than the center.
    static func generateStaticAsteroids(in bounds: CGRect,
                                        count: Int,
                                        walls: [Wall],
                                        rng: inout SeededGenerator)
        -> [(position: CGPoint, radius: CGFloat, seed: UInt64)] {
        guard count > 0 else { return [] }
        let inner = bounds.insetBy(dx: asteroidEdgeMargin, dy: asteroidEdgeMargin)
        guard inner.width > 0 && inner.height > 0 else { return [] }

        var placed: [(CGPoint, CGFloat)] = []
        var result: [(position: CGPoint, radius: CGFloat, seed: UInt64)] = []
        let asteroidGap: CGFloat = 30   // breathing room between static asteroids

        for _ in 0..<count {
            let radius = rng.cgFloat(in: staticAsteroidRadiusRange)
            var picked: CGPoint?
            for _ in 0..<placementTries {
                let p = CGPoint(x: rng.cgFloat(in: inner.minX...inner.maxX),
                                y: rng.cgFloat(in: inner.minY...inner.maxY))
                if overlapsAny(p, radius: radius, walls: walls) { continue }
                var clashes = false
                for (q, qr) in placed {
                    let need = qr + radius + asteroidGap
                    if p.distanceSquared(to: q) < need * need { clashes = true; break }
                }
                if !clashes {
                    picked = p
                    break
                }
            }
            if let pos = picked {
                placed.append((pos, radius))
                result.append((position: pos, radius: radius, seed: rng.next()))
            }
        }
        return result
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
