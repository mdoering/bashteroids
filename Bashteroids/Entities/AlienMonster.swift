import SpriteKit

final class AlienMonster: Entity {
    static let speed:            CGFloat      = 140
    static let driftAmplitude:   CGFloat      = 0.6
    static let driftRate:        CGFloat      = 0.7
    static let collisionRadius:  CGFloat      = 14
    static let bulletSpeed:      CGFloat      = 200
    static let shootIntervalMin: CGFloat      = 2.0
    static let shootIntervalMax: CGFloat      = 3.5
    static let shootRange:       CGFloat      = 200
    static let laserMaxDistance: CGFloat      = 140
    static let bulletHitsToKill: Int          = 2

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat   = collisionRadius
    var alive:  Bool      = true
    private(set) var hitsRemaining: Int = bulletHitsToKill

    private let baseHeading: CGFloat
    private var driftPhase:  CGFloat
    private var shootCooldown: TimeInterval
    private var rng: SeededGenerator

    init(position: CGPoint, baseHeading: CGFloat, seed: UInt64) {
        self.baseHeading   = baseHeading
        self.rng           = SeededGenerator(seed: seed)
        self.driftPhase    = rng.cgFloat(in: 0 ... .pi * 2)
        self.shootCooldown = TimeInterval(rng.cgFloat(in: Self.shootIntervalMin ...
                                                           Self.shootIntervalMax))
        let n = Shapes.alienMonster()
        n.position = position
        self.node = n
        velocity = CGPoint.fromAngle(currentHeading, length: Self.speed)
    }

    private var currentHeading: CGFloat {
        baseHeading + sin(driftPhase) * Self.driftAmplitude
    }

    func update(dt: TimeInterval) {
        driftPhase    += Self.driftRate * CGFloat(dt)
        velocity       = CGPoint.fromAngle(currentHeading, length: Self.speed)
        shootCooldown  = max(0, shootCooldown - dt)
    }

    var fireReady: Bool { alive && shootCooldown <= 0 }

    /// Apply a bullet hit. Returns true when the monster has run out of HP.
    @discardableResult
    func registerBulletHit() -> Bool {
        hitsRemaining -= 1
        node.run(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.04),
            .fadeAlpha(to: 1.0, duration: 0.10)
        ]))
        return hitsRemaining <= 0
    }

    func fire(at target: CGPoint) -> Bullet {
        let aim       = (target - position).normalized()
        let bulletVel = aim * Self.bulletSpeed
        let muzzle    = position + aim * (radius + 4)
        shootCooldown = TimeInterval(rng.cgFloat(in: Self.shootIntervalMin ...
                                                      Self.shootIntervalMax))
        return Bullet(position: muzzle, velocity: bulletVel, owner: self,
                      color: .white, maxDistance: Self.laserMaxDistance)
    }
}
