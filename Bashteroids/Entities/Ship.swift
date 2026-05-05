import SpriteKit

final class Ship: Entity {
    static let thrustAccel: CGFloat = 220
    static let maxSpeed: CGFloat = 280
    static let turnRate: CGFloat = 4.0          // rad/s at full input
    static let reloadInterval: TimeInterval = 2.0
    static let bulletSpeed: CGFloat = 380
    static let collisionRadius: CGFloat = 10
    static let noseOffset: CGFloat = 14         // matches Shapes.shipV nose

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat = collisionRadius
    var alive: Bool = true

    let playerIndex: Int
    let color: SKColor
    let reloadIndicator: SKShapeNode
    var score: Int = 0

    var heading: CGFloat = 0                    // radians; 0 = +X
    var turnInput: CGFloat = 0                  // -1...1, set per-frame by input
    var thrusting: Bool = false                 // held; set per-frame by input
    var reloadRemaining: TimeInterval = 0

    init(playerIndex: Int, color: SKColor, position: CGPoint, heading: CGFloat = 0) {
        self.playerIndex = playerIndex
        self.color = color
        self.heading = heading

        let n = Shapes.shipV(color: color)
        n.position = position
        n.zRotation = heading
        self.node = n

        let dot = SKShapeNode(circleOfRadius: 3)
        dot.strokeColor = color
        dot.fillColor = color
        dot.lineWidth = 1
        dot.position = position + CGPoint(x: 0, y: -16)
        self.reloadIndicator = dot
    }

    func update(dt: TimeInterval) {
        guard alive else { return }

        // Negative because SpriteKit's zRotation is positive-counter-clockwise:
        // stick-left (turnInput < 0) → anti-clockwise; stick-right → clockwise.
        heading -= turnInput * Self.turnRate * CGFloat(dt)

        if thrusting {
            let push = CGPoint.fromAngle(heading, length: Self.thrustAccel * CGFloat(dt))
            velocity = (velocity + push).clampedMagnitude(to: Self.maxSpeed)
        }

        node.zRotation = heading
        reloadRemaining = max(0, reloadRemaining - dt)
    }

    func syncVisuals() {
        let progress = CGFloat(max(0, 1 - reloadRemaining / Self.reloadInterval))
        reloadIndicator.fillColor = color.withAlphaComponent(progress)
        reloadIndicator.position = position + CGPoint(x: 0, y: -16)
    }

    var canFire: Bool { alive && reloadRemaining <= 0 }

    func fire() -> Bullet? {
        guard canFire else { return nil }
        reloadRemaining = Self.reloadInterval

        let nose = position + CGPoint.fromAngle(heading, length: Self.noseOffset)
        let bulletVel = velocity + CGPoint.fromAngle(heading, length: Self.bulletSpeed)
        return Bullet(position: nose, velocity: bulletVel, owner: self, color: color)
    }
}
