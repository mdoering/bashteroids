import SpriteKit

final class Ship: Entity {
    static let thrustAccel: CGFloat = 220
    static let maxSpeed: CGFloat = 140
    static let boostedMaxSpeedL1: CGFloat = 200
    static let boostedMaxSpeedL2: CGFloat = 250
    static let turnRate: CGFloat = 4.0          // rad/s at full input
    static let reloadInterval: TimeInterval = 2.0
    static let maxShieldStack: Int = 2
    static let maxCanonLevel: Int = 2           // 0 = single, 1 = dual, 2 = quad
    static let maxBoostLevel: Int = 2           // 0 = base, 1 = +43%, 2 = +79%
    static let maxBattleHP: Int = 10            // Survival default stays at 1 (1-hit-kill).
    static let brakeDeceleration: CGFloat = 200 // px/s² when braking

    var effectiveReloadInterval: TimeInterval {
        switch canonLevel {
        case 1:  return Self.reloadInterval / 1.5
        case 2:  return Self.reloadInterval / 2.0
        default: return Self.reloadInterval
        }
    }
    static let bulletSpeed: CGFloat = 380
    static let collisionRadius: CGFloat = 10
    static let noseOffset: CGFloat = 14         // matches Shapes.shipV nose

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat = collisionRadius
    var alive: Bool = true
    var hp: Int = 1

    let playerIndex: Int
    let color: SKColor
    var score: Int = 0

    private let thrustFlame: SKShapeNode
    private let canonMarker: SKShapeNode
    private let boostMarker: SKShapeNode
    private let minelayerMarker: SKShapeNode

    /// 0 = no shield, 1 = single ring (one absorb), 2 = double ring (two absorbs).
    /// Losing a shield also drops `canonLevel` by 1, so a hit costs both layers
    /// of upgrade at once.
    var shieldCount: Int = 0 {
        didSet {
            guard shieldCount != oldValue else { return }
            if shieldCount < oldValue {
                canonLevel = max(0, canonLevel - 1)
            }
            updateShieldRings()
        }
    }

    /// 0 = single canon (default), 1 = dual (2 lines, +50% fire rate),
    /// 2 = quad (4 lines, +100% fire rate, wider laser bullet).
    var canonLevel: Int = 0 {
        didSet {
            guard canonLevel != oldValue else { return }
            canonMarker.path = Ship.canonMarkerPath(level: canonLevel)
            canonMarker.alpha = canonLevel > 0 ? 1 : 0
        }
    }

    var boostLevel: Int = 0 {
        didSet {
            guard boostLevel != oldValue else { return }
            // No separate visual for L2; marker is on for any boostLevel >= 1.
            boostMarker.alpha = boostLevel >= 1 ? 1 : 0
        }
    }

    var minelayerArmed: Bool = false {
        didSet {
            guard minelayerArmed != oldValue else { return }
            minelayerMarker.alpha = minelayerArmed ? 1 : 0
        }
    }
    weak var laidMine: Mine?

    var effectiveMaxSpeed: CGFloat {
        switch boostLevel {
        case 1:  return Self.boostedMaxSpeedL1
        case 2:  return Self.boostedMaxSpeedL2
        default: return Self.maxSpeed
        }
    }

    var heading: CGFloat = 0                    // radians; 0 = +X
    var turnInput: CGFloat = 0                  // -1...1, set per-frame by input
    var thrusting: Bool = false                 // held; set per-frame by input
    var braking: Bool = false                   // held; set per-frame by input
    var reloadRemaining: TimeInterval = 0

    init(playerIndex: Int, color: SKColor, position: CGPoint, heading: CGFloat = 0) {
        self.playerIndex = playerIndex
        self.color = color
        self.heading = heading

        let n = Shapes.shipV(color: color)
        n.position = position
        n.zRotation = heading
        self.node = n

        let flame = Ship.makeThrustFlame()
        flame.alpha = 0
        n.addChild(flame)
        self.thrustFlame = flame

        let marker = SKShapeNode()
        marker.strokeColor = .yellow
        marker.fillColor   = .clear
        marker.lineWidth   = 1
        marker.alpha       = 0
        n.addChild(marker)
        self.canonMarker = marker

        let boost = Ship.makeBoostMarker()
        boost.alpha = 0
        n.addChild(boost)
        self.boostMarker = boost

        let mineMarker = Ship.makeMinelayerMarker()
        mineMarker.alpha = 0
        n.addChild(mineMarker)
        self.minelayerMarker = mineMarker
    }

    func update(dt: TimeInterval) {
        guard alive else { return }

        // Negative because SpriteKit's zRotation is positive-counter-clockwise:
        // stick-left (turnInput < 0) → anti-clockwise; stick-right → clockwise.
        heading -= turnInput * Self.turnRate * CGFloat(dt)

        if thrusting {
            let push = CGPoint.fromAngle(heading, length: Self.thrustAccel * CGFloat(dt))
            velocity = (velocity + push).clampedMagnitude(to: effectiveMaxSpeed)
            thrustFlame.alpha = CGFloat.random(in: 0.6...1.0)
            thrustFlame.xScale = CGFloat.random(in: 0.85...1.15)
        } else {
            thrustFlame.alpha = 0
            if braking {
                let speed = velocity.length
                if speed > 0 {
                    let newSpeed = max(0, speed - Self.brakeDeceleration * CGFloat(dt))
                    velocity = velocity.normalized() * newSpeed
                }
            }
        }

        node.zRotation = heading
        reloadRemaining = max(0, reloadRemaining - dt)
    }

    var canFire: Bool { alive && reloadRemaining <= 0 }

    func fire() -> [Bullet] {
        guard canFire else { return [] }
        reloadRemaining = effectiveReloadInterval

        let nosePos   = position + CGPoint.fromAngle(heading, length: Self.noseOffset)
        let bulletVel = velocity + CGPoint.fromAngle(heading, length: Self.bulletSpeed)
        let width: CGFloat = canonLevel >= 2 ? 3.0 : 1.5

        return [Bullet(position: nosePos,
                       velocity: bulletVel,
                       owner: self,
                       color: color,
                       width: width)]
    }

    // MARK: - Visual helpers

    private func updateShieldRings() {
        node.childNode(withName: "shieldInner")?.removeFromParent()
        node.childNode(withName: "shieldOuter")?.removeFromParent()
        let stroke = SKColor(red: 0, green: 1, blue: 1, alpha: 1)
        if shieldCount >= 1 {
            let r = SKShapeNode(circleOfRadius: Self.collisionRadius + 6)
            r.name = "shieldInner"
            r.strokeColor = stroke
            r.fillColor = .clear
            r.lineWidth = 1
            r.alpha = 0.6
            node.addChild(r)
        }
        if shieldCount >= 2 {
            let r = SKShapeNode(circleOfRadius: Self.collisionRadius + 11)
            r.name = "shieldOuter"
            r.strokeColor = stroke
            r.fillColor = .clear
            r.lineWidth = 1
            r.alpha = 0.6
            node.addChild(r)
        }
    }

    private static func makeThrustFlame() -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -7,  y:  3))
        path.addLine(to: CGPoint(x: -16, y: 0))
        path.addLine(to: CGPoint(x: -7,  y: -3))
        path.closeSubpath()
        let n = SKShapeNode(path: path)
        n.strokeColor = SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        n.fillColor   = .clear
        n.lineWidth   = 1.5
        n.lineJoin    = .round
        return n
    }

    private static func canonMarkerPath(level: Int) -> CGPath {
        let path = CGMutablePath()
        switch level {
        case 1:
            path.move(to: CGPoint(x: -2, y:  3)); path.addLine(to: CGPoint(x: 8, y:  3))
            path.move(to: CGPoint(x: -2, y: -3)); path.addLine(to: CGPoint(x: 8, y: -3))
        case 2:
            path.move(to: CGPoint(x: -2, y:  6)); path.addLine(to: CGPoint(x: 8, y:  6))
            path.move(to: CGPoint(x: -2, y:  2)); path.addLine(to: CGPoint(x: 8, y:  2))
            path.move(to: CGPoint(x: -2, y: -2)); path.addLine(to: CGPoint(x: 8, y: -2))
            path.move(to: CGPoint(x: -2, y: -6)); path.addLine(to: CGPoint(x: 8, y: -6))
        default:
            break
        }
        return path
    }

    private static func makeMinelayerMarker() -> SKShapeNode {
        // Tiny mine silhouette near the rear of the ship.
        let r: CGFloat       = 2.5
        let spikeLen: CGFloat = 2.5
        let path = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * .pi * 2
            path.move(to:    CGPoint(x: -8 + r             * cos(a), y: r             * sin(a)))
            path.addLine(to: CGPoint(x: -8 + (r + spikeLen) * cos(a), y: (r + spikeLen) * sin(a)))
        }
        let n = SKShapeNode(path: path)
        n.strokeColor = SKColor(red: 0.85, green: 0.30, blue: 0.75, alpha: 1)
        n.fillColor   = .clear
        n.lineWidth   = 1
        n.isAntialiased = true

        let circle = SKShapeNode(circleOfRadius: r)
        circle.position = CGPoint(x: -8, y: 0)
        circle.strokeColor = SKColor(red: 0.85, green: 0.30, blue: 0.75, alpha: 1)
        circle.fillColor   = .clear
        circle.lineWidth   = 1
        circle.isAntialiased = true
        n.addChild(circle)
        return n
    }

    private static func makeBoostMarker() -> SKShapeNode {
        // Two small chevrons pointing forward (+x): looks like ">>" trailing
        // the ship, evoking speed. Drawn at the rear of the silhouette.
        let path = CGMutablePath()
        path.move(to:    CGPoint(x: -10, y:  3))
        path.addLine(to: CGPoint(x:  -6, y:  0))
        path.addLine(to: CGPoint(x: -10, y: -3))
        path.move(to:    CGPoint(x:  -6, y:  3))
        path.addLine(to: CGPoint(x:  -2, y:  0))
        path.addLine(to: CGPoint(x:  -6, y: -3))
        let n = SKShapeNode(path: path)
        n.strokeColor = SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        n.fillColor   = .clear
        n.lineWidth   = 1.5
        n.lineJoin    = .miter
        return n
    }
}
