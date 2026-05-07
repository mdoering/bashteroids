import SpriteKit

enum PowerUpKind { case shield, twinLaser, boost, minelayer }

final class PowerUp: Entity {
    static let fadeWindow: TimeInterval = 5

    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat = 14
    var alive: Bool = true
    let kind: PowerUpKind
    var lifetime: TimeInterval?
    private var age: TimeInterval = 0

    init(kind: PowerUpKind, position: CGPoint, velocity: CGPoint) {
        self.kind = kind
        self.velocity = velocity
        let n = Shapes.powerUp(kind: kind)
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        guard let life = lifetime else { return }
        age += dt
        let remaining = life - age
        if remaining <= 0 {
            alive = false
            return
        }
        if remaining < Self.fadeWindow {
            node.alpha = max(0, CGFloat(remaining / Self.fadeWindow))
        }
    }
}
