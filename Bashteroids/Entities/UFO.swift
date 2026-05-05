import SpriteKit

final class UFO: Entity {
    static let speed: CGFloat = 140
    static let driftAmplitude: CGFloat = 0.6    // rad
    static let driftRate: CGFloat = 0.7         // rad/s phase advance
    static let collisionRadius: CGFloat = 14
    static let bulletSpeed: CGFloat = 260
    static let shootIntervalMin: CGFloat = 2.5
    static let shootIntervalMax: CGFloat = 4.5

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat = collisionRadius
    var alive: Bool = true

    private let baseHeading: CGFloat
    private var driftPhase: CGFloat
    private var shootCooldown: TimeInterval
    private var rng: SeededGenerator

    init(position: CGPoint, baseHeading: CGFloat, seed: UInt64) {
        self.baseHeading = baseHeading
        self.rng = SeededGenerator(seed: seed)
        self.driftPhase = rng.cgFloat(in: 0...(.pi * 2))
        self.shootCooldown = TimeInterval(rng.cgFloat(in: Self.shootIntervalMin...Self.shootIntervalMax))

        let n = Shapes.ufo()
        n.position = position
        self.node = n

        velocity = CGPoint.fromAngle(currentHeading, length: Self.speed)
    }

    private var currentHeading: CGFloat {
        baseHeading + sin(driftPhase) * Self.driftAmplitude
    }

    func update(dt: TimeInterval) {
        driftPhase += Self.driftRate * CGFloat(dt)
        velocity = CGPoint.fromAngle(currentHeading, length: Self.speed)
        shootCooldown = max(0, shootCooldown - dt)
    }

    var fireReady: Bool { alive && shootCooldown <= 0 }

    func fire(at target: CGPoint) -> Bullet {
        let aim = (target - position).normalized()
        let bulletVel = aim * Self.bulletSpeed
        let muzzle = position + aim * (radius + 4)

        shootCooldown = TimeInterval(rng.cgFloat(in: Self.shootIntervalMin...Self.shootIntervalMax))

        return Bullet(position: muzzle, velocity: bulletVel, owner: self, color: .white)
    }
}
