import SpriteKit

enum Collision {
    static func resolve(ships: [Ship],
                        asteroids: [Asteroid],
                        ufos: [UFO],
                        bullets: [Bullet]) {

        // Ships die on contact with asteroids, UFOs, or other ships.
        for ship in ships where ship.alive {
            for ast in asteroids where ast.alive {
                if overlap(ship, ast) {
                    ship.alive = false
                    break
                }
            }
            if !ship.alive { continue }

            for ufo in ufos where ufo.alive {
                if overlap(ship, ufo) {
                    ship.alive = false
                    break
                }
            }
            if !ship.alive { continue }

            for other in ships where other !== ship && other.alive {
                if overlap(ship, other) {
                    ship.alive = false
                    other.alive = false
                }
            }
        }

        // Bullets vs targets. Owner is skipped so a ship can't shoot itself
        // and a UFO can't shoot itself. Score credits flow to the bullet's
        // owner if the owner is a Ship; UFO bullets earn nobody points.
        for bullet in bullets where bullet.alive {
            for ast in asteroids where ast.alive {
                if overlap(bullet, ast) {
                    bullet.alive = false
                    ast.alive = false
                    (bullet.owner as? Ship)?.score += Score.asteroid
                    break
                }
            }
            if !bullet.alive { continue }

            for ufo in ufos where ufo.alive {
                if bullet.owner === ufo { continue }
                if overlap(bullet, ufo) {
                    bullet.alive = false
                    ufo.alive = false
                    (bullet.owner as? Ship)?.score += Score.ufo
                    break
                }
            }
            if !bullet.alive { continue }

            for ship in ships where ship.alive {
                if bullet.owner === ship { continue }
                if overlap(bullet, ship) {
                    bullet.alive = false
                    ship.alive = false
                    (bullet.owner as? Ship)?.score += Score.ship
                    break
                }
            }
        }
    }

    enum Score {
        static let asteroid = 1
        static let ufo = 5
        static let ship = 20
    }

    private static func overlap(_ a: Entity, _ b: Entity) -> Bool {
        let r = a.radius + b.radius
        return a.position.distanceSquared(to: b.position) <= r * r
    }
}
