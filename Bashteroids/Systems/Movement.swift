import SpriteKit

enum Movement {
    static func stepWrapping<E: Entity>(_ entities: [E], dt: TimeInterval, bounds: CGRect) {
        let dtf = CGFloat(dt)
        for e in entities where e.alive {
            e.position = e.position + e.velocity * dtf
            wrap(e, in: bounds)
        }
    }

    static func stepBounded<E: Entity>(_ entities: [E], dt: TimeInterval, bounds: CGRect) {
        let dtf = CGFloat(dt)
        for e in entities where e.alive {
            e.position = e.position + e.velocity * dtf
            if !bounds.contains(e.position) {
                e.alive = false
            }
        }
    }

    private static func wrap(_ entity: Entity, in bounds: CGRect) {
        var p = entity.position
        if p.x < bounds.minX { p.x += bounds.width }
        else if p.x > bounds.maxX { p.x -= bounds.width }
        if p.y < bounds.minY { p.y += bounds.height }
        else if p.y > bounds.maxY { p.y -= bounds.height }
        entity.position = p
    }
}
