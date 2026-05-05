import SpriteKit

final class Ship: Entity {
    static let thrustAccel: CGFloat = 220
    static let maxSpeed: CGFloat = 280
    static let turnRate: CGFloat = 4.0          // rad/s at full input
    static let reloadInterval: TimeInterval = 2.0

    var effectiveReloadInterval: TimeInterval {
        hasDualCanon ? Self.reloadInterval / 1.5 : Self.reloadInterval
    }
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

    var hasShield: Bool = false {
        didSet {
            if hasShield {
                let ring = SKShapeNode(circleOfRadius: Self.collisionRadius + 6)
                ring.name = "shieldRing"
                ring.strokeColor = .white
                ring.fillColor = .clear
                ring.lineWidth = 1
                ring.alpha = 0.4
                node.addChild(ring)
            } else {
                node.childNode(withName: "shieldRing")?.removeFromParent()
            }
        }
    }
    var hasDualCanon: Bool = false
    private var canonAlternate: Bool = false

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
        reloadRemaining = effectiveReloadInterval

        if hasDualCanon {
            canonAlternate.toggle()
            let side: CGFloat = canonAlternate ? 1 : -1
            let offset = CGPoint.fromAngle(heading + side * .pi / 2, length: 4)
            let muzzle = position + CGPoint.fromAngle(heading, length: Self.noseOffset) + offset
            let bulletVel = velocity + CGPoint.fromAngle(heading, length: Self.bulletSpeed)
            return Bullet(position: muzzle, velocity: bulletVel, owner: self, color: color)
        } else {
            let nose = position + CGPoint.fromAngle(heading, length: Self.noseOffset)
            let bulletVel = velocity + CGPoint.fromAngle(heading, length: Self.bulletSpeed)
            return Bullet(position: nose, velocity: bulletVel, owner: self, color: color)
        }
    }
}
