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

    /// Advance entities and reflect off the bounds rectangle. Each bounce
    /// scrubs `energyLoss` of the normal-component velocity (default 50%).
    /// Used in BATTLE so ships ricochet off the arena edges instead of
    /// screen-wrapping.
    static func stepBouncing<E: Entity>(_ entities: [E], dt: TimeInterval, bounds: CGRect, energyLoss: CGFloat = 0.5) {
        let dtf = CGFloat(dt)
        for e in entities where e.alive {
            e.position = e.position + e.velocity * dtf
            var p = e.position
            var v = e.velocity
            let r = e.radius
            if p.x - r < bounds.minX {
                p.x = bounds.minX + r
                v.x = -v.x * energyLoss
            } else if p.x + r > bounds.maxX {
                p.x = bounds.maxX - r
                v.x = -v.x * energyLoss
            }
            if p.y - r < bounds.minY {
                p.y = bounds.minY + r
                v.y = -v.y * energyLoss
            } else if p.y + r > bounds.maxY {
                p.y = bounds.maxY - r
                v.y = -v.y * energyLoss
            }
            e.position = p
            e.velocity = v
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
