import SpriteKit

enum Collision {
    static func resolve(ships: [Ship],
                        asteroids: [Asteroid],
                        ufos: [UFO],
                        alienMonsters: [AlienMonster],
                        bullets: [Bullet],
                        powerUps: [PowerUp],
                        rocks: [Rock],
                        mines: [Mine],
                        snakes: [Snake],
                        walls: [Wall],
                        shipsCollideWithEachOther: Bool) {

        for rock in rocks where rock.alive {
            for ship in ships where ship.alive {
                if overlap(rock, ship) { ship.alive = false }
            }
            for ast in asteroids where ast.alive {
                if overlap(rock, ast) { ast.alive = false }
            }
            for ufo in ufos where ufo.alive {
                if overlap(rock, ufo) { ufo.alive = false }
            }
            for alien in alienMonsters where alien.alive {
                if overlap(rock, alien) { alien.alive = false }
            }
            for bullet in bullets where bullet.alive {
                if overlap(rock, bullet) { bullet.alive = false }
            }
            for pu in powerUps where pu.alive {
                if overlap(rock, pu) { pu.alive = false }
            }
            for mine in mines where mine.alive {
                if overlap(rock, mine) {
                    mine.alive = false
                    mine.exploded = true
                }
            }
            for snake in snakes where snake.alive {
                if snake.hitTest(point: rock.position, radius: rock.radius) {
                    snake.alive = false
                }
            }
        }

        for ship in ships where ship.alive {
            for ast in asteroids where ast.alive {
                if overlap(ship, ast) {
                    if hitShip(ship) { ast.alive = false }
                    break
                }
            }
            if !ship.alive { continue }
            for ufo in ufos where ufo.alive {
                if overlap(ship, ufo) {
                    if hitShip(ship) { ufo.alive = false }
                    break
                }
            }
            if !ship.alive { continue }
            for alien in alienMonsters where alien.alive {
                if overlap(ship, alien) {
                    if hitShip(ship) { alien.alive = false }
                    break
                }
            }
            if !ship.alive { continue }
            for snake in snakes where snake.alive {
                if snake.hitTest(point: ship.position, radius: ship.radius) {
                    if hitShip(ship) {
                        if snake.registerBulletHit() { snake.alive = false }
                    }
                    break
                }
            }
            if !ship.alive { continue }
            if shipsCollideWithEachOther {
                for other in ships where other !== ship && other.alive {
                    if overlap(ship, other) {
                        switch (ship.shieldCount > 0, other.shieldCount > 0) {
                        case (true,  true):  ship.shieldCount -= 1; other.shieldCount -= 1
                        case (true,  false): ship.shieldCount -= 1; other.alive = false
                        case (false, true):  other.shieldCount -= 1; ship.alive = false
                        case (false, false): ship.alive = false; other.alive = false
                        }
                    }
                }
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
                    if alien.registerBulletHit() {
                        alien.alive = false
                        (bullet.owner as? Ship)?.score += Score.alienMonster
                    }
                    break
                }
            }
            if !bullet.alive { continue }
            for snake in snakes where snake.alive {
                if snake.hitTest(point: bullet.position, radius: bullet.radius) {
                    bullet.alive = false
                    if snake.registerBulletHit() {
                        snake.alive = false
                        (bullet.owner as? Ship)?.score += Score.snake
                    }
                    break
                }
            }
            if !bullet.alive { continue }
            for ship in ships where ship.alive {
                if bullet.owner === ship { continue }
                if !shipsCollideWithEachOther, bullet.owner is Ship { continue }
                if overlap(bullet, ship) {
                    bullet.alive = false
                    hitShip(ship)
                    (bullet.owner as? Ship)?.score += Score.ship
                    break
                }
            }
            if !bullet.alive { continue }
            for wall in walls where wall.alive {
                let outer = wall.radius + bullet.radius
                if wall.node.position.distanceSquared(to: bullet.position) > outer * outer { continue }
                if wall.registerBulletHit(at: bullet.position) {
                    bullet.alive = false
                    break
                }
            }
        }

        for ship in ships where ship.alive {
            for pu in powerUps where pu.alive {
                if overlap(ship, pu) {
                    pu.alive = false
                    switch pu.kind {
                    case .shield:    ship.shieldCount = min(ship.shieldCount + 1, Ship.maxShieldStack)
                    case .dualCanon: ship.canonLevel  = min(ship.canonLevel + 1, Ship.maxCanonLevel)
                    case .boost:     ship.boostLevel  = min(ship.boostLevel + 1, Ship.maxBoostLevel)
                    case .minelayer:
                        if !ship.minelayerArmed && ship.laidMine == nil {
                            ship.minelayerArmed = true
                        }
                        // else: already armed or has placed mine — pickup consumed but no-op.
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
        static let snake        = 15
    }

    @discardableResult
    private static func hitShip(_ ship: Ship) -> Bool {
        if ship.shieldCount > 0 {
            ship.shieldCount -= 1
            return true
        } else {
            ship.alive = false
            return false
        }
    }

    private static func overlap(_ a: Entity, _ b: Entity) -> Bool {
        let r = a.radius + b.radius
        return a.position.distanceSquared(to: b.position) <= r * r
    }
}
