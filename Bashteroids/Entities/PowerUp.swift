import SpriteKit

enum PowerUpKind { case shield, dualCanon, boost }

final class PowerUp: Entity {
    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat = 14
    var alive: Bool = true
    let kind: PowerUpKind

    init(kind: PowerUpKind, position: CGPoint, velocity: CGPoint) {
        self.kind = kind
        self.velocity = velocity
        let n = Shapes.powerUp(kind: kind)
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {}
}
