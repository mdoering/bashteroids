import SpriteKit

enum SpawnKind {
    case asteroid(radius: CGFloat, seed: UInt64)
    case ufo(baseHeading: CGFloat, seed: UInt64)
    case powerUp(kind: PowerUpKind, speed: CGFloat)
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

    var bounds: CGRect

    private weak var glowParent: SKNode?
    private var elapsed: TimeInterval = 0
    private var timeToNextDecision: TimeInterval = 1.5
    private var rng: SeededGenerator

    private struct Pending {
        let side: ScreenSide
        let glow: SKShapeNode
        let spawnAt: TimeInterval
        let kind: PendingKind
    }

    private enum PendingKind {
        case asteroid(radius: CGFloat, speed: CGFloat, seed: UInt64)
        case ufo(seed: UInt64)
        case powerUp(kind: PowerUpKind)
    }

    private var pending: [Pending] = []

    init(bounds: CGRect, glowParent: SKNode, seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) {
        self.bounds = bounds
        self.glowParent = glowParent
        self.rng = SeededGenerator(seed: seed)
    }

    func reset() {
        elapsed = 0
        timeToNextDecision = 1.5
        for p in pending { p.glow.removeFromParent() }
        pending.removeAll()
    }

    func update(dt: TimeInterval) -> [Spawn] {
        elapsed += dt
        timeToNextDecision -= dt

        if timeToNextDecision <= 0 {
            scheduleNext()
            timeToNextDecision = nextDecisionDelay()
        }

        var ready: [Spawn] = []
        var remaining: [Pending] = []
        remaining.reserveCapacity(pending.count)

        for p in pending {
            if elapsed >= p.spawnAt {
                p.glow.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
                ready.append(makeSpawn(from: p))
            } else {
                remaining.append(p)
            }
        }
        pending = remaining
        return ready
    }

    // MARK: - Scheduling

    private func scheduleNext() {
        let side = ScreenSide.allCases.randomElement(using: &rng) ?? .top

        let pendingKind: PendingKind
        let glowColor: SKColor
        if rollPowerUp() {
            let kind: PowerUpKind = rng.cgFloat(in: 0...1) < 0.5 ? .shield : .dualCanon
            pendingKind = .powerUp(kind: kind)
            glowColor = .white
        } else if rollUFO() {
            pendingKind = .ufo(seed: rng.next())
            glowColor = SKColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1)
        } else {
            let minSpeed = min(110, 60 + CGFloat(elapsed) / 180 * 50)
            let maxSpeed = min(200, 120 + CGFloat(elapsed) / 180 * 80)
            let speed = rng.cgFloat(in: minSpeed...maxSpeed)
            let maxRadius = elapsed > 120 ? max(18, 32 - CGFloat(elapsed - 120) / 60 * 7) : 32
            let radius = rng.cgFloat(in: 18...maxRadius)
            pendingKind = .asteroid(radius: radius, speed: speed, seed: rng.next())
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

    private func nextDecisionDelay() -> TimeInterval {
        // 5s at start, ramps down to ~1.2s after a couple of minutes.
        let base = max(1.2, 5.0 - elapsed * 0.04)
        let jitter = TimeInterval(rng.cgFloat(in: -0.4...0.4))
        return max(0.5, base + jitter)
    }

    private func rollUFO() -> Bool {
        let chance = min(0.35, elapsed / 60.0 * 0.35)
        return Double(rng.cgFloat(in: 0...1)) < chance
    }

    private func rollPowerUp() -> Bool {
        guard elapsed > 30 else { return false }
        return Double(rng.cgFloat(in: 0...1)) < 0.15
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
                         velocity: .zero, // UFO recomputes its own velocity
                         side: p.side)

        case .powerUp(let kind):
            let angle = inwardAngle + rng.cgFloat(in: -0.4...0.4)
            let speed = rng.cgFloat(in: 50...90)
            let velocity = CGPoint.fromAngle(angle, length: speed)
            return Spawn(kind: .powerUp(kind: kind, speed: speed),
                         position: position,
                         velocity: velocity,
                         side: p.side)
        }
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
        case .top:    return -.pi / 2     // moving down
        case .bottom: return  .pi / 2     // moving up
        case .left:   return  0           // moving right
        case .right:  return  .pi         // moving left
        }
    }
}
