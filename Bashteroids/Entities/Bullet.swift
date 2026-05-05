import SpriteKit

final class Bullet: Entity {
    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat = 2
    var alive: Bool = true

    weak var owner: AnyObject?

    private let maxDistance: CGFloat?
    private var distanceTravelled: CGFloat = 0

    init(position: CGPoint,
         velocity: CGPoint,
         owner: AnyObject?,
         color: SKColor = .white,
         maxDistance: CGFloat? = nil) {
        self.velocity = velocity
        self.owner = owner
        self.maxDistance = maxDistance
        let heading = atan2(velocity.y, velocity.x)
        let n = Shapes.bullet(color: color, heading: heading)
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        guard let max = maxDistance else { return }
        distanceTravelled += velocity.length * CGFloat(dt)
        if distanceTravelled >= max { alive = false }
    }
}
