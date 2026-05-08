import SpriteKit

/// Player-fired homing missile. Steers toward a locked target (set at fire
/// time) up to Torpedo.maxTurnRate per second; carries straight if no target
/// is locked or once the target dies. Self-destructs on lifetime expiry, on
/// any collision, or on a single bullet hit. Deals `Torpedo.damage` HP.
final class Torpedo: Entity {
    static let speed:          CGFloat      = 200
    static let maxTurnRate:    CGFloat      = 4.0      // rad/s
    static let lifetime:       TimeInterval = 6.0
    static let damage:         Int          = 3
    static let scanRange:      CGFloat      = 400      // max lock distance
    static let scanHalfAngle:  CGFloat      = .pi / 4  // ±45° forward cone
    static let lockWindow:     TimeInterval = 3.0
    static let collisionRadius: CGFloat     = 6

    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat = collisionRadius
    var alive: Bool = true

    weak var owner: Ship?
    weak var target: Entity?

    private(set) var heading: CGFloat
    private var age: TimeInterval = 0

    init(owner: Ship, position: CGPoint, heading: CGFloat, target: Entity?) {
        self.owner = owner
        self.heading = heading
        self.target = target
        self.velocity = CGPoint.fromAngle(heading, length: Torpedo.speed)
        let n = Shapes.torpedo()
        n.position = position
        n.zRotation = heading
        self.node = n
    }

    func update(dt: TimeInterval) {
        guard alive else { return }
        age += dt
        if age >= Torpedo.lifetime { alive = false; return }

        if let t = target, !t.alive { target = nil }

        if let t = target {
            let dx = t.position.x - node.position.x
            let dy = t.position.y - node.position.y
            let targetHeading = atan2(dy, dx)
            var diff = targetHeading - heading
            while diff >  .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            let limit = Torpedo.maxTurnRate * CGFloat(dt)
            heading += max(-limit, min(limit, diff))
        }

        velocity = CGPoint.fromAngle(heading, length: Torpedo.speed)
        node.zRotation = heading
        // Position update is handled by Movement.stepBounded after this call.
    }
}
