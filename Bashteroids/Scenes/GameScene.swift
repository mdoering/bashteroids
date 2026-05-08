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
    private var torpedoes: [Torpedo] = []
    private var lockCircles: [ObjectIdentifier: SKShapeNode] = [:]
    private var powerUps: [PowerUp] = []
    private var mines: [Mine] = []
    private var alienMonsters: [AlienMonster] = []
    private var rocks: [Rock] = []
    private var snakes: [Snake] = []
    private var walls: [Wall] = []

    private var spawner: Spawner!
    private var lastUpdateTime: TimeInterval = 0
    private var battleRNG = SeededGenerator(seed: UInt64(Date().timeIntervalSince1970 * 1000))

    private var initialShipCount: Int = 0
    private var transitioning = false
    private var deathTickCounter: Int = 0
    private var shipDeathTick: [Int: Int] = [:]

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
    private var hpBarOutlines: [SKShapeNode] = []
    private var hpBarFills: [SKShapeNode] = []

    private var safeInsetTop:    CGFloat { view?.safeAreaInsets.top    ?? 0 }
    private var safeInsetBottom: CGFloat { view?.safeAreaInsets.bottom ?? 0 }
    private var safeInsetLeft:   CGFloat { view?.safeAreaInsets.left   ?? 0 }
    private var safeInsetRight:  CGFloat { view?.safeAreaInsets.right  ?? 0 }

    init(size: CGSize, level: Int, mode: GameMode) {
        self.mode = mode
        super.init(size: size)
        self.currentLevel = max(1, min(9, level))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    var playBounds: CGRect {
        CGRect(
            x: safeInsetLeft,
            y: safeInsetBottom,
            width: size.width - safeInsetLeft - safeInsetRight,
            height: size.height - safeInsetTop - safeInsetBottom - Self.hudHeight
        )
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        TouchOverlayState.shared.setScene(.game)
        GameSettings.lastPlayedLevel = currentLevel
        spawner = Spawner(bounds: playBounds, glowParent: self)
        spawner.mode = mode

        if mode == .battle {
            generateBattleWalls()
            spawnShipsForBattle(in: playBounds)
        } else {
            spawnShipsForJoinedPlayers(in: playBounds)
        }
        initialShipCount = ships.count

        addChild(hudLayer)
        buildHUD()
        updateHUD()

        manager.onStartPressed = nil

        KeyboardManager.shared.onKeyDown = { [weak self] code in
            self?.handleKeyDown(code)
        }

        if mode == .battle {
            levelState = .spawning
            spawner.startLevel(LevelRoster.config(for: currentLevel))
        } else {
            levelState = .transitioning
            transitionTime = 0
            bannerStarted = false
            flashStarted = false
        }
    }

    override func willMove(from view: SKView) {
        audio.stopAllThrust()
        manager.keyboardInput.releaseAll()
        TouchInputState.shared.releaseAll()
        TouchOverlayState.shared.setScene(.other)
    }

    private func handleKeyDown(_ code: GCKeyCode) {
        switch code {
        case .escape:    MacFullScreen.exitIfActive()
        case .spacebar:  manager.keyboardInput.spaceDown()
        case .keyM:      manager.keyboardInput.mPressed()
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

        deathTickCounter += 1
        let bounds = playBounds

        applyInputs()

        for s in ships    { s.update(dt: dt) }
        for a in asteroids { a.update(dt: dt) }
        for u in ufos     { u.update(dt: dt) }
        for b in bullets  { b.update(dt: dt) }
        for t in torpedoes { t.update(dt: dt) }
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

        if mode == .battle {
            Movement.stepBouncing(ships, dt: dt, bounds: bounds)
        } else {
            Movement.stepWrapping(ships, dt: dt, bounds: bounds)
        }
        Movement.stepWrapping(asteroids, dt: dt, bounds: bounds)
        Movement.stepWrapping(ufos,     dt: dt, bounds: bounds)
        Movement.stepBounded(bullets,  dt: dt, bounds: bounds)
        Movement.stepBounded(torpedoes, dt: dt, bounds: bounds)
        Movement.stepBounded(powerUps, dt: dt, bounds: bounds)
        Movement.stepBounded(rocks, dt: dt, bounds: bounds.insetBy(dx: -60, dy: -60))

        if mode == .battle && !walls.isEmpty {
            BattleArena.reflectShipsOffWalls(ships, walls: walls)
        }

        let pvpEnabled = (levelState == .spawning)

        Collision.resolve(ships: ships, asteroids: asteroids, ufos: ufos,
                          alienMonsters: alienMonsters,
                          bullets: bullets, powerUps: powerUps,
                          rocks: rocks, mines: mines,
                          snakes: snakes,
                          torpedoes: torpedoes,
                          walls: walls,
                          shipsCollideWithEachOther: pvpEnabled,
                          contactParent: self)

        if mode == .battle {
            _ = spawner.update(dt: dt)  // advance elapsed only
            if let pu = spawner.updateBattlePowerUps(walls: walls, rng: &battleRNG) {
                spawn(pu)
            }
        } else if levelState == .transitioning {
            handleLevelTransition(dt: dt)
        } else {
            let spawns = spawner.update(dt: dt)
            for s in spawns { spawn(s) }
        }

        reapDead()
        updateLockCircles()
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

    private func generateBattleWalls() {
        let seed = UInt64(Date().timeIntervalSince1970 * 1000)
        walls = BattleArena.generate(in: playBounds, level: currentLevel, seed: seed)
        for wall in walls {
            addChild(wall.node)
        }

        // Static asteroids — non-moving obstacles inside the arena.
        let cfg = LevelRoster.battleConfig(for: currentLevel)
        var asteroidRng = SeededGenerator(seed: seed &+ 1)
        let placements = BattleArena.generateStaticAsteroids(
            in: playBounds,
            count: cfg.staticAsteroids,
            walls: walls,
            rng: &asteroidRng)
        for placement in placements {
            let asteroid = Asteroid(position: placement.position,
                                    velocity: .zero,
                                    radius: placement.radius,
                                    seed: placement.seed)
            asteroids.append(asteroid)
            addChild(asteroid.node)
        }
    }

    private func spawnShipsForBattle(in bounds: CGRect) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let inset: CGFloat = min(bounds.width, bounds.height) * 0.42
        let slots = manager.slots
        let count = slots.count

        for (i, slot) in slots.enumerated() {
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2
            // Try a few angular nudges if the obvious spot collides with a wall.
            var bestPos = center + CGPoint.fromAngle(angle, length: inset)
            var bestClearance: CGFloat = -.infinity
            for jitter in stride(from: -0.4, through: 0.4, by: 0.1) {
                let a = angle + CGFloat(jitter)
                let p = center + CGPoint.fromAngle(a, length: inset)
                let c = clearanceFromWalls(p)
                if c >= 60 { bestPos = p; break }
                if c > bestClearance { bestClearance = c; bestPos = p }
            }

            let heading = atan2(center.y - bestPos.y, center.x - bestPos.x)
                + battleRNG.cgFloat(in: -0.3...0.3)
            let ship = Ship(playerIndex: slot.index,
                            color: slot.color,
                            position: bestPos,
                            heading: heading)
            ship.hp = Ship.maxBattleHP
            ships.append(ship)
            addChild(ship.node)
        }
    }

    private func clearanceFromWalls(_ p: CGPoint) -> CGFloat {
        var best: CGFloat = .infinity
        for w in walls where w.alive {
            let d = sqrt(w.node.position.distanceSquared(to: p)) - w.radius
            if d < best { best = d }
        }
        return best
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

            if input.minelayerActionPressedThisFrame {
                handleMinelayerAction(ship: ship)
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

    private func handleMinelayerAction(ship: Ship) {
        // Torpedo workflow takes priority while one is armed (or while its
        // lock window is still open from a prior press).
        if ship.armedTorpedo {
            handleTorpedoAction(ship: ship)
            return
        }
        if ship.minelayerArmed && ship.laidMine == nil {
            // Place: drop a mine at the ship's current position with a 60 s timer.
            let mine = Mine(position: ship.position, lifetimeOverride: 60)
            mines.append(mine)
            addChild(mine.node)
            ship.minelayerArmed = false
            ship.laidMine = mine
        } else if let live = ship.laidMine, live.alive {
            // Detonate: mark the mine as exploded; reapDead handles the blast.
            live.alive = false
            live.exploded = true
        }
        // else: no armed mine, no live placed mine — no-op.
    }

    private func handleTorpedoAction(ship: Ship) {
        if ship.torpedoLockSecondsRemaining > 0 {
            // Second press within the lock window: launch.
            launchTorpedo(from: ship, target: ship.torpedoLockTarget)
            ship.armedTorpedo = false
            ship.torpedoLockTarget = nil
            ship.torpedoLockSecondsRemaining = 0
            removeLockCircle(forShip: ship)
            return
        }
        // First press: scan for a target inside the forward cone.
        let target = scanForLockTarget(from: ship)
        ship.torpedoLockTarget = target
        ship.torpedoLockSecondsRemaining = Torpedo.lockWindow
        if target == nil {
            ship.flashTorpedoMarker()
            audio.playDenial()
        }
    }

    private func scanForLockTarget(from ship: Ship) -> Entity? {
        let pos = ship.position
        let heading = ship.heading
        var best: Entity?
        var bestD2: CGFloat = .infinity

        func consider(_ e: Entity) {
            guard e.alive else { return }
            let dx = e.position.x - pos.x
            let dy = e.position.y - pos.y
            let d2 = dx * dx + dy * dy
            if d2 > Torpedo.scanRange * Torpedo.scanRange { return }
            var diff = atan2(dy, dx) - heading
            while diff >  .pi { diff -= 2 * .pi }
            while diff < -.pi { diff += 2 * .pi }
            if abs(diff) > Torpedo.scanHalfAngle { return }
            if d2 < bestD2 { bestD2 = d2; best = e }
        }
        asteroids.forEach(consider)
        ufos.forEach(consider)
        alienMonsters.forEach(consider)
        snakes.forEach(consider)
        mines.forEach(consider)
        rocks.forEach(consider)
        if mode == .battle {
            for other in ships where other !== ship { consider(other) }
        }
        return best
    }

    private func launchTorpedo(from ship: Ship, target: Entity?) {
        let nosePos = ship.position + CGPoint.fromAngle(ship.heading, length: Ship.noseOffset)
        let torpedo = Torpedo(owner: ship, position: nosePos, heading: ship.heading, target: target)
        torpedoes.append(torpedo)
        addChild(torpedo.node)
    }

    private func removeLockCircle(forShip ship: Ship) {
        let id = ObjectIdentifier(ship)
        lockCircles[id]?.removeFromParent()
        lockCircles.removeValue(forKey: id)
    }

    private func updateLockCircles() {
        for ship in ships {
            let id = ObjectIdentifier(ship)
            if let target = ship.torpedoLockTarget,
               ship.torpedoLockSecondsRemaining > 0,
               target.alive {
                let circle: SKShapeNode
                if let existing = lockCircles[id] {
                    circle = existing
                } else {
                    circle = Shapes.lockCircle(radius: target.radius + 4)
                    addChild(circle)
                    lockCircles[id] = circle
                }
                circle.position = target.position
            } else {
                removeLockCircle(forShip: ship)
            }
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
        case .powerUp(let kind, _, let lifetime):
            let pu = PowerUp(kind: kind, position: s.position, velocity: s.velocity)
            pu.lifetime = lifetime
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
                    let d = ship.position.distance(to: dead.position)
                    if d <= Mine.innerKillRadius {
                        // Direct hit: 5 damage, bypasses shields fully on
                        // survival's 1-HP ships. BATTLE ships (10 HP) can
                        // survive a graze if they had shields.
                        Collision.hitShip(ship, damage: 5)
                    } else if d < Mine.explosionRadius {
                        // Outer blast: 1 damage (shield-absorbed first).
                        Collision.hitShip(ship, damage: 1)
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
                if shipDeathTick[ship.playerIndex] == nil {
                    shipDeathTick[ship.playerIndex] = deathTickCounter
                }
                Explosion.burst(at: ship.position,
                                radius: ship.radius * 1.4,
                                color: ship.color,
                                parent: self)
                audio.playExplosion()
                audio.setThrust(playerIndex: ship.playerIndex, on: false)
                if mode == .battle {
                    // Leave the wreck behind as faint debris for the rest of
                    // the round so the arena doesn't go empty.
                    ship.node.alpha = 0.4
                } else {
                    ship.node.removeFromParent()
                }
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
        torpedoes.removeAll { dead in
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
        guard mode != .battle, levelState == .spawning, !transitioning else { return }
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
        for b in bullets   { b.alive = false }
        for t in torpedoes { t.alive = false }
        for m in mines     { m.alive = false }   // mine.exploded stays false → no blast
        for r in rocks     { r.alive = false }
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
        if mode == .survival {
            // Co-op: ends only when every player is dead. With zero ships
            // (0-player demo run) the game runs forever — no spurious end.
            if !ships.isEmpty && alive.isEmpty { finish(winner: nil) }
        } else {
            // BATTLE: last-ship-standing.
            if initialShipCount == 1 {
                if alive.isEmpty { finish(winner: nil) }
            } else {
                if alive.count <= 1 { finish(winner: alive.first) }
            }
        }
    }

    // MARK: - HUD

    private static let hpBarWidth: CGFloat = 80
    private static let hpBarHeight: CGFloat = 6

    private func buildHUD() {
        scoreLabels.removeAll()
        hpBarOutlines.removeAll()
        hpBarFills.removeAll()
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

            if mode == .battle {
                let outline = SKShapeNode(rectOf: CGSize(width: Self.hpBarWidth, height: Self.hpBarHeight))
                outline.strokeColor = SKColor(white: 0.6, alpha: 1)
                outline.fillColor = .clear
                outline.lineWidth = 1
                hudLayer.addChild(outline)
                hpBarOutlines.append(outline)

                let fill = SKShapeNode()
                fill.strokeColor = .clear
                fill.fillColor = SKColor(red: 0.40, green: 0.85, blue: 0.40, alpha: 1)
                hudLayer.addChild(fill)
                hpBarFills.append(fill)
            }
        }
        repositionHUD()
    }

    private func repositionHUD() {
        let count = scoreLabels.count
        guard count > 0 else { return }
        let segmentWidth = size.width / CGFloat(count)
        let y = size.height - safeInsetTop - Self.hudHeight / 2
        for (i, label) in scoreLabels.enumerated() {
            let cx = segmentWidth * (CGFloat(i) + 0.5)
            label.position = CGPoint(x: cx, y: y)
            if mode == .battle, i < hpBarOutlines.count {
                hpBarOutlines[i].position = CGPoint(x: cx, y: y - 14)
            }
        }
    }

    private func updateHUD() {
        for (i, label) in scoreLabels.enumerated() {
            guard i < ships.count else { continue }
            let name = UserDefaults.standard.string(forKey: "player_name_\(i)") ?? "P\(i + 1)"
            if mode == .battle {
                if ships[i].alive {
                    label.text = name
                    label.fontColor = ships[i].color
                } else {
                    label.text = "✕ \(name)"
                    label.fontColor = SKColor(white: 0.5, alpha: 1)
                }
                updateHpBar(forShipIndex: i)
            } else {
                label.text = "\(name)  \(ships[i].score)"
            }
        }
    }

    private func updateHpBar(forShipIndex i: Int) {
        guard i < hpBarOutlines.count, i < hpBarFills.count, i < ships.count else { return }
        let outline = hpBarOutlines[i]
        let fill = hpBarFills[i]
        let ship = ships[i]
        let hp = max(0, ship.hp)
        let frac = CGFloat(hp) / CGFloat(Ship.maxBattleHP)

        let barColor: SKColor
        if frac > 0.5 {
            barColor = SKColor(red: 0.40, green: 0.85, blue: 0.40, alpha: 1)   // green
        } else if frac > 0.25 {
            barColor = SKColor(red: 1.00, green: 0.70, blue: 0.20, alpha: 1)   // orange
        } else {
            barColor = SKColor(red: 0.95, green: 0.30, blue: 0.30, alpha: 1)   // red
        }

        let fillWidth = max(0, Self.hpBarWidth * frac)
        if fillWidth <= 0 {
            fill.path = nil
        } else {
            let rect = CGRect(
                x: outline.position.x - Self.hpBarWidth / 2,
                y: outline.position.y - Self.hpBarHeight / 2,
                width: fillWidth,
                height: Self.hpBarHeight
            )
            fill.path = CGPath(rect: rect, transform: nil)
        }
        fill.fillColor = barColor
    }

    private func finish(winner: Ship?) {
        guard !transitioning else { return }
        transitioning = true
        audio.stopAllThrust()

        let result: GameOverScene.Result
        if mode == .battle {
            if let w = winner {
                let name = UserDefaults.standard.string(forKey: "player_name_\(w.playerIndex)")
                    ?? "P\(w.playerIndex + 1)"
                result = .battleWinner(color: w.color, name: name)
            } else {
                result = .battleDraw
            }
        } else {
            // Survival co-op: sum scores, record one entry under the
            // last-to-die player. On simultaneous deaths (max tick tied),
            // pick the lowest player index — deterministic.
            let totalScore = ships.reduce(0) { $0 + $1.score }
            let maxTick = shipDeathTick.values.max() ?? 0
            let candidates = shipDeathTick.filter { $0.value == maxTick }.keys.sorted()
            let lastIdx = candidates.first ?? 0
            let lastShip = ships.first(where: { $0.playerIndex == lastIdx })
            let lastName = UserDefaults.standard.string(forKey: "player_name_\(lastIdx)")
                ?? "P\(lastIdx + 1)"
            let lastColor = lastShip?.color ?? .white

            if totalScore > 0 {
                HighScore.record(name: lastName, score: totalScore, level: currentLevel)
            }
            result = .survivalEnd(lastPlayerName: lastName,
                                  lastPlayerColor: lastColor,
                                  totalScore: totalScore,
                                  playerCount: ships.count)
        }

        run(.sequence([
            .wait(forDuration: 1.5),
            .run { [weak self] in
                guard let self else { return }
                let next = GameOverScene(size: self.size, result: result)
                next.scaleMode = self.scaleMode
                self.view?.presentScene(next, transition: .fade(withDuration: 0.5))
            }
        ]))
    }
}
