import SpriteKit

final class GameScene: SKScene {
    private let manager = ControllerManager.shared
    private let audio = AudioEngine.shared

    private static let hudHeight: CGFloat = 36

    private var ships: [Ship] = []
    private var asteroids: [Asteroid] = []
    private var ufos: [UFO] = []
    private var bullets: [Bullet] = []
    private var powerUps: [PowerUp] = []
    private var mines: [Mine] = []
    private var alienMonsters: [AlienMonster] = []

    private var spawner: Spawner!
    private var lastUpdateTime: TimeInterval = 0

    private var initialShipCount: Int = 0
    private var transitioning = false

    private let hudLayer = SKNode()
    private var scoreLabels: [SKLabelNode] = []

    private var playBounds: CGRect {
        CGRect(x: 0, y: 0, width: size.width, height: size.height - Self.hudHeight)
    }

    override var canBecomeFirstResponder: Bool { true }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        becomeFirstResponder()
        spawner = Spawner(bounds: playBounds, glowParent: self)

        spawnShipsForJoinedPlayers(in: playBounds)
        initialShipCount = ships.count

        addChild(hudLayer)
        buildHUD()
        updateHUD()

        manager.onStartPressed = nil
    }

    override func willMove(from view: SKView) {
        audio.stopAllThrust()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.key?.keyCode == .keyboardEscape {
                MacFullScreen.exitIfActive()
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        spawner?.bounds = playBounds
        repositionHUD()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt: TimeInterval
        if lastUpdateTime == 0 {
            dt = 0
        } else {
            dt = min(currentTime - lastUpdateTime, 1.0 / 30.0)
        }
        lastUpdateTime = currentTime
        guard dt > 0, !transitioning else { return }

        let bounds = playBounds

        applyInputs()

        for s in ships    { s.update(dt: dt) }
        for a in asteroids { a.update(dt: dt) }
        for u in ufos     { u.update(dt: dt) }
        for b in bullets  { b.update(dt: dt) }
        for pu in powerUps { pu.update(dt: dt) }
        for m in mines { m.update(dt: dt) }
        for a in alienMonsters { a.update(dt: dt) }
        Movement.stepWrapping(alienMonsters, dt: dt, bounds: bounds)
        fireAlienMonstersIfReady()

        fireUFOsIfReady()

        Movement.stepWrapping(ships,    dt: dt, bounds: bounds)
        Movement.stepWrapping(asteroids, dt: dt, bounds: bounds)
        Movement.stepWrapping(ufos,     dt: dt, bounds: bounds)
        Movement.stepBounded(bullets,  dt: dt, bounds: bounds)
        Movement.stepBounded(powerUps, dt: dt, bounds: bounds)

        Collision.resolve(ships: ships, asteroids: asteroids, ufos: ufos,
                          alienMonsters: alienMonsters,
                          bullets: bullets, powerUps: powerUps)

        for s in ships where s.alive { s.syncVisuals() }

        let spawns = spawner.update(dt: dt)
        for s in spawns { spawn(s) }

        reapDead()
        updateHUD()
        checkEndCondition()
    }

    // MARK: - Setup

    private func spawnShipsForJoinedPlayers(in bounds: CGRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 90
        let slots = manager.slots

        for (i, slot) in slots.enumerated() {
            let position: CGPoint
            let heading: CGFloat
            if slots.count == 1 {
                position = center
                heading = .pi / 2
            } else {
                let angle = CGFloat(i) / CGFloat(slots.count) * .pi * 2
                position = center + CGPoint.fromAngle(angle, length: radius)
                heading = angle
            }
            let ship = Ship(playerIndex: slot.index,
                            color: slot.color,
                            position: position,
                            heading: heading)
            ships.append(ship)
            addChild(ship.node)
            addChild(ship.reloadIndicator)
        }
    }

    // MARK: - Per-frame helpers

    private func applyInputs() {
        for (i, slot) in manager.slots.enumerated() {
            guard i < ships.count else { break }
            let ship = ships[i]
            guard ship.alive else {
                audio.setThrust(playerIndex: slot.index, on: false)
                continue
            }
            let input = slot.snapshot()
            ship.turnInput = input.turn
            ship.thrusting = input.thrust
            audio.setThrust(playerIndex: slot.index, on: input.thrust)

            if input.firePressedThisFrame, let bullet = ship.fire() {
                bullets.append(bullet)
                addChild(bullet.node)
                audio.playShoot()
            }
        }
    }

    private func fireUFOsIfReady() {
        for ufo in ufos where ufo.fireReady {
            guard let target = nearestShip(to: ufo.position) else { continue }
            let bullet = ufo.fire(at: target.position)
            bullets.append(bullet)
            addChild(bullet.node)
            audio.playShoot()
        }
    }

    private func fireAlienMonstersIfReady() {
        for alien in alienMonsters where alien.fireReady {
            guard let target = nearestShip(to: alien.position),
                  alien.position.distance(to: target.position) < AlienMonster.shootRange
            else { continue }
            let bullet = alien.fire(at: target.position)
            bullets.append(bullet)
            addChild(bullet.node)
            audio.playShoot()
        }
    }

    private func nearestShip(to point: CGPoint) -> Ship? {
        var best: Ship?
        var bestDist: CGFloat = .infinity
        for ship in ships where ship.alive {
            let d = ship.position.distanceSquared(to: point)
            if d < bestDist { bestDist = d; best = ship }
        }
        return best
    }

    private func spawn(_ s: Spawn) {
        switch s.kind {
        case .asteroid(let radius, let seed):
            let asteroid = Asteroid(position: s.position,
                                    velocity: s.velocity,
                                    radius: radius,
                                    seed: seed)
            asteroids.append(asteroid)
            addChild(asteroid.node)
        case .ufo(let baseHeading, let seed):
            let ufo = UFO(position: s.position, baseHeading: baseHeading, seed: seed)
            ufos.append(ufo)
            addChild(ufo.node)
        case .powerUp(let kind, _):
            let pu = PowerUp(kind: kind, position: s.position, velocity: s.velocity)
            powerUps.append(pu)
            addChild(pu.node)
        case .mine:
            let mine = Mine(position: s.position)
            mines.append(mine)
            addChild(mine.node)
        case .alienMonster(let baseHeading, let seed):
            let alien = AlienMonster(position: s.position, baseHeading: baseHeading, seed: seed)
            alienMonsters.append(alien)
            addChild(alien.node)
        }
    }

    private func reapDead() {
        mines.removeAll { dead in
            guard !dead.alive else { return false }
            if dead.exploded {
                Explosion.burst(at: dead.position,
                                radius: Mine.explosionRadius,
                                color: .white,
                                parent: self)
                audio.playExplosion()
                for ship in ships where ship.alive {
                    if ship.position.distance(to: dead.position) < Mine.explosionRadius {
                        if ship.hasShield { ship.hasShield = false } else { ship.alive = false }
                    }
                }
                for ufo in ufos where ufo.alive {
                    if ufo.position.distance(to: dead.position) < Mine.explosionRadius {
                        ufo.alive = false
                    }
                }
                for alien in alienMonsters where alien.alive {
                    if alien.position.distance(to: dead.position) < Mine.explosionRadius {
                        alien.alive = false
                    }
                }
                nearestShip(to: dead.position)?.score += 5
            }
            dead.node.removeFromParent()
            return true
        }

        for ship in ships where !ship.alive {
            if ship.node.parent != nil {
                Explosion.burst(at: ship.position,
                                radius: ship.radius * 1.4,
                                color: ship.color,
                                parent: self)
                audio.playExplosion()
                audio.setThrust(playerIndex: ship.playerIndex, on: false)
                ship.node.removeFromParent()
                ship.reloadIndicator.removeFromParent()
            }
        }

        asteroids.removeAll { dead in
            if !dead.alive {
                Explosion.burst(at: dead.position, radius: dead.radius, parent: self)
                audio.playExplosion()
                dead.node.removeFromParent()
                return true
            }
            return false
        }
        ufos.removeAll { dead in
            if !dead.alive {
                Explosion.burst(at: dead.position, radius: dead.radius * 1.2, parent: self)
                audio.playExplosion()
                dead.node.removeFromParent()
                return true
            }
            return false
        }
        bullets.removeAll { dead in
            if !dead.alive { dead.node.removeFromParent(); return true }
            return false
        }
        powerUps.removeAll { dead in
            if !dead.alive { dead.node.removeFromParent(); return true }
            return false
        }
        alienMonsters.removeAll { dead in
            if !dead.alive {
                Explosion.burst(at: dead.position, radius: dead.radius * 1.2, parent: self)
                audio.playExplosion()
                dead.node.removeFromParent()
                return true
            }
            return false
        }
    }

    // MARK: - End condition

    private func checkEndCondition() {
        let alive = ships.filter { $0.alive }
        if initialShipCount == 1 {
            if alive.isEmpty { finish(winner: nil) }
        } else {
            if alive.count <= 1 { finish(winner: alive.first) }
        }
    }

    // MARK: - HUD

    private func buildHUD() {
        scoreLabels.removeAll()
        hudLayer.removeAllChildren()

        for i in 0..<manager.slots.count {
            let label = SKLabelNode(text: "")
            label.fontName = "AvenirNext-Bold"
            label.fontSize = 16
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.fontColor = manager.slots[i].color
            hudLayer.addChild(label)
            scoreLabels.append(label)
        }
        repositionHUD()
    }

    private func repositionHUD() {
        let count = scoreLabels.count
        guard count > 0 else { return }
        let segmentWidth = size.width / CGFloat(count)
        let y = size.height - Self.hudHeight / 2
        for (i, label) in scoreLabels.enumerated() {
            label.position = CGPoint(x: segmentWidth * (CGFloat(i) + 0.5), y: y)
        }
    }

    private func updateHUD() {
        for (i, label) in scoreLabels.enumerated() {
            if i < ships.count {
                label.text = "P\(i + 1)  \(ships[i].score)"
            } else {
                label.text = "P\(i + 1)  --"
            }
        }
    }

    private func finish(winner: Ship?) {
        guard !transitioning else { return }
        transitioning = true
        audio.stopAllThrust()

        let topScore = ships.map(\.score).max() ?? 0
        HighScore.recordIfHigher(topScore)

        let result: GameOverScene.Result = winner.map { .winner(color: $0.color, label: "P\($0.playerIndex + 1) WINS") }
                                                ?? .gameOver

        let next = GameOverScene(size: size, result: result)
        next.scaleMode = scaleMode
        run(.sequence([
            .wait(forDuration: 1.2),
            .run { [weak self] in
                self?.view?.presentScene(next, transition: .fade(withDuration: 0.5))
            }
        ]))
    }
}
