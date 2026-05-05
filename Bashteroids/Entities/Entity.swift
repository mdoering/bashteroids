import SpriteKit

protocol Entity: AnyObject {
    var node: SKNode { get }
    var velocity: CGPoint { get set }
    var radius: CGFloat { get }
    var alive: Bool { get set }
    func update(dt: TimeInterval)
}

extension Entity {
    var position: CGPoint {
        get { node.position }
        set { node.position = newValue }
    }
}
