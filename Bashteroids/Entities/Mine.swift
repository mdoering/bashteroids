import SpriteKit

final class Mine: Entity {
    static let lifetime:        TimeInterval = 6.0
    static let innerKillRadius: CGFloat      = 60
    static let explosionRadius: CGFloat      = 140
    static let collisionRadius: CGFloat      = 14

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat   = collisionRadius
    var alive:  Bool      = true
    var exploded: Bool    = false

    private let effectiveLifetime: TimeInterval
    private var age:        TimeInterval = 0
    private var flashPhase: TimeInterval = 0

    init(position: CGPoint, lifetimeOverride: TimeInterval? = nil) {
        self.effectiveLifetime = lifetimeOverride ?? Self.lifetime
        let n = Shapes.mine()
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        age += dt
        if age >= effectiveLifetime {
            alive    = false
            exploded = true
            return
        }
        let t      = CGFloat(age / effectiveLifetime)
        let period = max(0.2, Double(1.5 - t * 1.3))
        flashPhase += dt
        flashPhase = flashPhase.truncatingRemainder(dividingBy: period)
        node.alpha = flashPhase < period / 2 ? 1.0 : 0.15
    }
}
