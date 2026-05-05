import SpriteKit

final class Asteroid: Entity {
    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat
    var alive: Bool = true

    private let spin: CGFloat                   // rad/s

    init(position: CGPoint, velocity: CGPoint, radius: CGFloat, seed: UInt64) {
        self.velocity = velocity
        self.radius = radius

        var rng = SeededGenerator(seed: seed &+ 0xA570)
        self.spin = rng.cgFloat(in: -1.2...1.2)

        let n = Shapes.asteroid(radius: radius, seed: seed)
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        node.zRotation += spin * CGFloat(dt)
    }
}
