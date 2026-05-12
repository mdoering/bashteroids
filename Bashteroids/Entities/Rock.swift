import SpriteKit

final class Rock: Entity {
    static let defaultRadius: CGFloat = 42

    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat
    var alive: Bool = true

    private let spin: CGFloat

    init(position: CGPoint, velocity: CGPoint, radius: CGFloat, seed: UInt64) {
        self.velocity = velocity
        self.radius = radius

        var rng = SeededGenerator(seed: seed &+ 0x90CC)
        self.spin = rng.cgFloat(in: -0.5...0.5)

        let n = Shapes.rock(radius: radius, seed: seed)
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        node.zRotation += spin * CGFloat(dt)
    }
}
