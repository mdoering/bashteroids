import SpriteKit

enum SpawnKind {
    case asteroid(radius: CGFloat, seed: UInt64)
    case ufo(baseHeading: CGFloat, seed: UInt64)
    case alienMonster(baseHeading: CGFloat, seed: UInt64)
    case powerUp(kind: PowerUpKind, speed: CGFloat)
    case mine
    case rock(radius: CGFloat, seed: UInt64)
    case snake(baseHeading: CGFloat, seed: UInt64)
}

struct Spawn {
    let kind: SpawnKind
    let position: CGPoint
    let velocity: CGPoint
    let side: ScreenSide
}

final class Spawner {
    static let warningDuration: TimeInterval = 3.0
    static let glowMaxAlpha: CGFloat = 0.35
    static let spawnInterval: TimeInterval = 2.0
    static let spawnIntervalJitter: TimeInterval = 0.4

    var bounds: CGRect

    private weak var glowParent: SKNode?
    private var rng: SeededGenerator

    private var elapsed: TimeInterval = 0
    private var timeToNextSpawn: TimeInterval = 0
    private var queue: [QueuedKind] = []
    private var pending: [Pending] = []

    private enum QueuedKind {
        case asteroid, ufo, alien, mine, rock, snake, powerUp
    }

    private struct Pending {
        let side: ScreenSide
        let glow: SKShapeNode?
        let spawnAt: TimeInterval
        let kind: PendingKind
    }

    private enum PendingKind {
        case asteroid(radius: CGFloat, speed: CGFloat, seed: UInt64)
        case ufo(seed: UInt64)
        case alien(seed: UInt64)
        case powerUp(kind: PowerUpKind)
        case mine
        case rock(radius: CGFloat, speed: CGFloat, seed: UInt64)
        case snake(seed: UInt64)
    }

    init(bounds: CGRect, glowParent: SKNode, seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) {
        self.bounds = bounds
        self.glowParent = glowParent
        self.rng = SeededGenerator(seed: seed)
    }

    /// Populate the queue for a fresh level. Drops any pending state.
    func startLevel(_ config: LevelConfig) {
        queue.removeAll(keepingCapacity: true)
        for p in pending { p.glow?.removeFromParent() }
        pending.removeAll(keepingCapacity: true)

        append(.asteroid, count: config.asteroids)
        append(.ufo,      count: config.ufos)
        append(.alien,    count: config.aliens)
        append(.mine,     count: config.mines)
        append(.rock,     count: config.rocks)
        append(.snake,    count: config.snakes)
        append(.powerUp,  count: config.powerUps)
        queue.shuffle(using: &rng)

        elapsed = 0
        timeToNextSpawn = 0.5
    }

    /// True if there are entities still queued or mid-warning.
    var hasMoreSpawns: Bool { !queue.isEmpty || !pending.isEmpty }

    func update(dt: TimeInterval) -> [Spawn] {
        elapsed += dt
        timeToNextSpawn -= dt

        if timeToNextSpawn <= 0, !queue.isEmpty {
            scheduleNext()
            timeToNextSpawn = nextSpawnDelay()
        }

        var ready: [Spawn] = []
        var remaining: [Pending] = []
        remaining.reserveCapacity(pending.count)

        for p in pending {
            if elapsed >= p.spawnAt {
                p.glow?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
                ready.append(makeSpawn(from: p))
            } else {
                remaining.append(p)
            }
        }
        pending = remaining
        return ready
    }

    // MARK: - Queue building

    private func append(_ kind: QueuedKind, count: Int) {
        for _ in 0..<count { queue.append(kind) }
    }

    // MARK: - Scheduling

    private func scheduleNext() {
        guard !queue.isEmpty else { return }
        let queuedKind = queue.removeFirst()
        let side = ScreenSide.allCases.randomElement(using: &rng) ?? .top

        let pendingKind: PendingKind
        let glowColor: SKColor

        switch queuedKind {
        case .asteroid:
            let speed = rng.cgFloat(in: 80...160)
            let radius = rng.cgFloat(in: 18...32)
            pendingKind = .asteroid(radius: radius, speed: speed, seed: rng.next())
            glowColor = .white

        case .ufo:
            pendingKind = .ufo(seed: rng.next())
            glowColor = SKColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1)

        case .alien:
            pendingKind = .alien(seed: rng.next())
            glowColor = SKColor(red: 0.8, green: 0.3, blue: 1.0, alpha: 1)

        case .mine:
            // No edge entry, no warning glow.
            pending.append(Pending(
                side: side,
                glow: nil,
                spawnAt: elapsed + Self.warningDuration,
                kind: .mine
            ))
            return

        case .rock:
            let radius = rng.cgFloat(in: 36...50)
            let speed  = rng.cgFloat(in: 60...110)
            pendingKind = .rock(radius: radius, speed: speed, seed: rng.next())
            glowColor = SKColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1)

        case .snake:
            pendingKind = .snake(seed: rng.next())
            glowColor = SKColor(red: 0.55, green: 0.85, blue: 0.30, alpha: 1)

        case .powerUp:
            let kinds: [PowerUpKind] = [.shield, .dualCanon, .boost]
            let kind = kinds.randomElement(using: &rng) ?? .shield
            pendingKind = .powerUp(kind: kind)
            glowColor = .white
        }

        let glow = Shapes.edgeGlow(side: side, bounds: bounds, color: glowColor)
        glow.run(.fadeAlpha(to: Self.glowMaxAlpha, duration: Self.warningDuration))
        glowParent?.addChild(glow)

        pending.append(Pending(
            side: side,
            glow: glow,
            spawnAt: elapsed + Self.warningDuration,
            kind: pendingKind
        ))
    }

    private func nextSpawnDelay() -> TimeInterval {
        let jitter = TimeInterval(rng.cgFloat(
            in: -CGFloat(Self.spawnIntervalJitter)...CGFloat(Self.spawnIntervalJitter)
        ))
        return max(0.2, Self.spawnInterval + jitter)
    }

    // MARK: - Spawn assembly

    private func makeSpawn(from p: Pending) -> Spawn {
        let position = entryPosition(side: p.side)
        let inwardAngle = inwardAngle(side: p.side)

        switch p.kind {
        case .asteroid(let radius, let speed, let seed):
            let angle = inwardAngle + rng.cgFloat(in: -0.6...0.6)
            let velocity = CGPoint.fromAngle(angle, length: speed)
            return Spawn(kind: .asteroid(radius: radius, seed: seed),
                         position: position,
                         velocity: velocity,
                         side: p.side)

        case .ufo(let seed):
            let baseHeading = inwardAngle + rng.cgFloat(in: -0.4...0.4)
            return Spawn(kind: .ufo(baseHeading: baseHeading, seed: seed),
                         position: position,
                         velocity: .zero,
                         side: p.side)

        case .powerUp(let kind):
            let angle = inwardAngle + rng.cgFloat(in: -0.4...0.4)
            let speed = rng.cgFloat(in: 50...90)
            let velocity = CGPoint.fromAngle(angle, length: speed)
            return Spawn(kind: .powerUp(kind: kind, speed: speed),
                         position: position,
                         velocity: velocity,
                         side: p.side)

        case .alien(let seed):
            let heading = inwardAngle + rng.cgFloat(in: -0.4...0.4)
            return Spawn(kind: .alienMonster(baseHeading: heading, seed: seed),
                         position: position,
                         velocity: .zero,
                         side: p.side)

        case .mine:
            return Spawn(kind: .mine,
                         position: interiorPosition(),
                         velocity: .zero,
                         side: p.side)

        case .rock(let radius, let speed, let seed):
            let angle = inwardAngle + rng.cgFloat(in: -0.3...0.3)
            let velocity = CGPoint.fromAngle(angle, length: speed)
            return Spawn(kind: .rock(radius: radius, seed: seed),
                         position: position,
                         velocity: velocity,
                         side: p.side)

        case .snake(let seed):
            let heading = inwardAngle + rng.cgFloat(in: -0.4...0.4)
            return Spawn(kind: .snake(baseHeading: heading, seed: seed),
                         position: position,
                         velocity: .zero,
                         side: p.side)
        }
    }

    private func interiorPosition() -> CGPoint {
        let margin: CGFloat = 80
        let x = rng.cgFloat(in: bounds.minX + margin ... bounds.maxX - margin)
        let y = rng.cgFloat(in: bounds.minY + margin ... bounds.maxY - margin)
        return CGPoint(x: x, y: y)
    }

    private func entryPosition(side: ScreenSide) -> CGPoint {
        let inset: CGFloat = 8
        switch side {
        case .top:
            let x = rng.cgFloat(in: bounds.minX + 40...bounds.maxX - 40)
            return CGPoint(x: x, y: bounds.maxY - inset)
        case .bottom:
            let x = rng.cgFloat(in: bounds.minX + 40...bounds.maxX - 40)
            return CGPoint(x: x, y: bounds.minY + inset)
        case .left:
            let y = rng.cgFloat(in: bounds.minY + 40...bounds.maxY - 40)
            return CGPoint(x: bounds.minX + inset, y: y)
        case .right:
            let y = rng.cgFloat(in: bounds.minY + 40...bounds.maxY - 40)
            return CGPoint(x: bounds.maxX - inset, y: y)
        }
    }

    private func inwardAngle(side: ScreenSide) -> CGFloat {
        switch side {
        case .top:    return -.pi / 2
        case .bottom: return  .pi / 2
        case .left:   return  0
        case .right:  return  .pi
        }
    }
}
