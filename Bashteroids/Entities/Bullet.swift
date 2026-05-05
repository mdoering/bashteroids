import SpriteKit

final class Bullet: Entity {
    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat = 2
    var alive: Bool = true

    weak var owner: AnyObject?

    init(position: CGPoint, velocity: CGPoint, owner: AnyObject?) {
        self.velocity = velocity
        self.owner = owner

        let n = Shapes.bullet()
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        // Position is integrated by the Movement system; bullets have no
        // internal state to advance.
    }
}
