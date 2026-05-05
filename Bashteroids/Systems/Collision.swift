import SpriteKit

enum Collision {
    static func resolve(ships: [Ship],
                        asteroids: [Asteroid],
                        ufos: [UFO],
                        alienMonsters: [AlienMonster],
                        bullets: [Bullet],
                        powerUps: [PowerUp]) {

        for ship in ships where ship.alive {
            for ast in asteroids where ast.alive {
                if overlap(ship, ast) { hitShip(ship); break }
            }
            if !ship.alive { continue }
            for ufo in ufos where ufo.alive {
                if overlap(ship, ufo) { hitShip(ship); break }
            }
            if !ship.alive { continue }
            for alien in alienMonsters where alien.alive {
                if overlap(ship, alien) { hitShip(ship); break }
            }
            if !ship.alive { continue }
            for other in ships where other !== ship && other.alive {
                if overlap(ship, other) { hitShip(ship); hitShip(other) }
            }
        }

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
            for alien in alienMonsters where alien.alive {
                if bullet.owner === alien { continue }
                if overlap(bullet, alien) {
                    bullet.alive = false
                    alien.alive  = false
                    (bullet.owner as? Ship)?.score += Score.alienMonster
                    break
                }
            }
            if !bullet.alive { continue }
            for ship in ships where ship.alive {
                if bullet.owner === ship { continue }
                if overlap(bullet, ship) {
                    bullet.alive = false
                    hitShip(ship)
                    (bullet.owner as? Ship)?.score += Score.ship
                    break
                }
            }
        }

        for ship in ships where ship.alive {
            for pu in powerUps where pu.alive {
                if overlap(ship, pu) {
                    pu.alive = false
                    switch pu.kind {
                    case .shield:    if !ship.hasShield    { ship.hasShield    = true }
                    case .dualCanon: if !ship.hasDualCanon { ship.hasDualCanon = true }
                    }
                }
            }
        }
    }

    enum Score {
        static let asteroid     = 1
        static let ufo          = 5
        static let ship         = 20
        static let alienMonster = 10
    }

    private static func hitShip(_ ship: Ship) {
        if ship.hasShield {
            ship.hasShield = false
        } else {
            ship.alive = false
        }
    }

    private static func overlap(_ a: Entity, _ b: Entity) -> Bool {
        let r = a.radius + b.radius
        return a.position.distanceSquared(to: b.position) <= r * r
    }
}
