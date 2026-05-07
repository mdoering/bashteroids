import SpriteKit
import GameController

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
    private var rocks: [Rock] = []
    private var snakes: [Snake] = []
    private var walls: [Wall] = []

    private var spawner: Spawner!
    private var lastUpdateTime: TimeInterval = 0

    private var initialShipCount: Int = 0
    private var transitioning = false

    // Level state machine.
    private enum LevelState { case transitioning, spawning }
    let mode: GameMode
    private var currentLevel: Int = 1
    private var levelState: LevelState = .transitioning
    private var transitionTime: TimeInterval = 0
    private var bannerStarted: Bool = false
    private var flashStarted: Bool = false

    private static let transitionCalm:   TimeInterval = 0.6
    private static let transitionBanner: TimeInterval = 1.6
    private static let transitionFlash:  TimeInterval = 1.0

    private let hudLayer = SKNode()
    private var scoreLabels: [SKLabelNode] = []

    private var safeInsets: UIEdgeInsets { view?.safeAreaInsets ?? .zero }

    init(size: CGSize, level: Int, mode: GameMode) {
        self.mode = mode
        super.init(size: size)
        self.currentLevel = max(1, min(9, level))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    var playBounds: CGRect {
        let insets = safeInsets
        return CGRect(
            x: insets.left,
            y: insets.bottom,
            width: size.width - insets.left - insets.right,
            height: size.height - insets.top - insets.bottom - Self.hudHeight
        )
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        GameSettings.lastPlayedLevel = currentLevel
        spawner = Spawner(bounds: playBounds, glowParent: self)

        spawnShipsForJoinedPlayers(in: playBounds)
        initialShipCount = ships.count

        addChild(hudLayer)
        buildHUD()
        updateHUD()

        manager.onStartPressed = nil

        KeyboardManager.shared.onKeyDown = { [weak self] code in
            self?.handleKeyDown(code)
        }

        levelState = .transitioning
        transitionTime = 0
        bannerStarted = false
        flashStarted = false
    }

    override func willMove(from view: SKView) {
        audio.stopAllThrust()
        manager.keyboardInput.releaseAll()
    }

    private func handleKeyDown(_ code: GCKeyCode) {
        switch code {
        case .escape:    MacFullScreen.exitIfActive()
        case .spacebar:  manager.keyboardInput.spaceDown()
        default: break
        }

        #if DEBUG
        debugHandleKey(code)
        #endif
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
        for r in rocks { r.update(dt: dt) }
        for s in snakes {
            s.target = nearestShip(to: s.position)?.position
            s.update(dt: dt)
            if s.alive { s.wrap(in: bounds) }
        }
        Movement.stepWrapping(alienMonsters, dt: dt, bounds: bounds)
        fireAlienMonstersIfReady()

        fireUFOsIfReady()

        Movement.stepWrapping(ships,    dt: dt, bounds: bounds)
        Movement.stepWrapping(asteroids, dt: dt, bounds: bounds)
        Movement.stepWrapping(ufos,     dt: dt, bounds: bounds)
        Movement.stepBounded(bullets,  dt: dt, bounds: bounds)
        Movement.stepBounded(powerUps, dt: dt, bounds: bounds)
        Movement.stepBounded(rocks, dt: dt, bounds: bounds.insetBy(dx: -60, dy: -60))

        let pvpEnabled = (levelState == .spawning)

        Collision.resolve(ships: ships, asteroids: asteroids, ufos: ufos,
                          alienMonsters: alienMonsters,
                          bullets: bullets, powerUps: powerUps,
                          rocks: rocks, mines: mines,
                          snakes: snakes,
                          walls: walls,
                          shipsCollideWithEachOther: pvpEnabled)

        if levelState == .transitioning {
            handleLevelTransition(dt: dt)
        } else {
            let spawns = spawner.update(dt: dt)
            for s in spawns { spawn(s) }
        }

        reapDead()
        updateHUD()
        checkEndCondition()
        checkLevelComplete()
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
            ship.braking   = input.brake
            audio.setThrust(playerIndex: slot.index, on: input.thrust)

            if input.firePressedThisFrame {
                let newBullets = ship.fire()
                if !newBullets.isEmpty {
                    for b in newBullets {
                        bullets.append(b)
                        addChild(b.node)
                    }
                    audio.playShoot()
                }
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

    func spawn(_ s: Spawn) {
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
        case .rock(let radius, let seed):
            let rock = Rock(position: s.position,
                            velocity: s.velocity,
                            radius: radius,
                            seed: seed)
            rocks.append(rock)
            addChild(rock.node)
        case .snake(let baseHeading, let seed):
            let snake = Snake(position: s.position, baseHeading: baseHeading, seed: seed)
            snakes.append(snake)
            addChild(snake.node)
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
                        if ship.shieldCount > 0 {
                            ship.shieldCount -= 1
                        } else {
                            ship.alive = false
                        }
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
        rocks.removeAll { dead in
            if !dead.alive { dead.node.removeFromParent(); return true }
            return false
        }
        snakes.removeAll { dead in
            if !dead.alive {
                Explosion.burst(at: dead.position,
                                radius: Snake.headRadius * 1.4,
                                color: Snake.bodyColor,
                                parent: self)
                audio.playExplosion()
                dead.node.removeFromParent()
                return true
            }
            return false
        }
    }

    // MARK: - Level transitions

    private func checkLevelComplete() {
        guard levelState == .spawning, !transitioning else { return }
        let killTargetsAlive = !asteroids.isEmpty || !ufos.isEmpty
            || !alienMonsters.isEmpty || !snakes.isEmpty
        if !spawner.hasMoreSpawns && !killTargetsAlive {
            currentLevel += 1
            GameSettings.lastPlayedLevel = currentLevel
            beginLevelTransition()
        }
    }

    private func beginLevelTransition() {
        levelState = .transitioning
        transitionTime = 0
        bannerStarted = false
        flashStarted = false

        // Wipe lingering hazards so the transition is a clean slate.
        for b in bullets { b.alive = false }
        for m in mines   { m.alive = false }   // mine.exploded stays false → no blast
        for r in rocks   { r.alive = false }
    }

    private func handleLevelTransition(dt: TimeInterval) {
        transitionTime += dt
        let calm      = Self.transitionCalm
        let bannerEnd = calm + Self.transitionBanner
        let flashEnd  = bannerEnd + Self.transitionFlash

        if !bannerStarted, transitionTime >= calm {
            bannerStarted = true
            let label = SKLabelNode(text: "LEVEL \(currentLevel)")
            label.fontName = "AvenirNext-Bold"
            label.fontSize = 56
            label.fontColor = .white
            label.position = CGPoint(x: size.width / 2, y: size.height / 2)
            label.alpha = 0
            addChild(label)
            label.run(.sequence([
                .fadeIn(withDuration: 0.4),
                .wait(forDuration: max(0, Self.transitionBanner - 0.8)),
                .fadeOut(withDuration: 0.4),
                .removeFromParent()
            ]))
        }

        if !flashStarted, transitionTime >= bannerEnd {
            flashStarted = true
            let cycle = SKAction.sequence([
                .fadeAlpha(to: 0.3, duration: 0.1),
                .fadeAlpha(to: 1.0, duration: 0.1)
            ])
            for ship in ships where ship.alive {
                ship.node.run(.repeat(cycle, count: 5))
            }
        }

        if transitionTime >= flashEnd {
            levelState = .spawning
            spawner.startLevel(LevelRoster.config(for: currentLevel))
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
        let y = size.height - safeInsets.top - Self.hudHeight / 2
        for (i, label) in scoreLabels.enumerated() {
            label.position = CGPoint(x: segmentWidth * (CGFloat(i) + 0.5), y: y)
        }
    }

    private func updateHUD() {
        for (i, label) in scoreLabels.enumerated() {
            guard i < ships.count else { continue }
            let name = UserDefaults.standard.string(forKey: "player_name_\(i)") ?? "P\(i + 1)"
            label.text = "\(name)  \(ships[i].score)"
        }
    }

    private func finish(winner: Ship?) {
        guard !transitioning else { return }
        transitioning = true
        audio.stopAllThrust()

        for ship in ships {
            let name = UserDefaults.standard.string(forKey: "player_name_\(ship.playerIndex)")
                ?? "P\(ship.playerIndex + 1)"
            HighScore.record(name: name, score: ship.score, level: currentLevel)
        }

        let topScore = ships.map(\.score).max() ?? 0
        let result: GameOverScene.Result = winner.map {
            let name = UserDefaults.standard.string(forKey: "player_name_\($0.playerIndex)") ?? "P\($0.playerIndex + 1)"
            return .winner(color: $0.color, label: "\(name) WINS", score: $0.score)
        } ?? .gameOver(topScore: topScore)

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
