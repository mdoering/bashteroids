# Game Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add player names, solo mode HUD, difficulty scaling, laser bullets, asteroid interior, power-ups (shield + dual-canon), space mine, alien monster, and L2/X-button controls to Bashteroids.

**Architecture:** All new entities (PowerUp, Mine, AlienMonster) follow the existing Ship/UFO/Asteroid pattern: a `final class` conforming to `Entity` with `node/velocity/radius/alive/update(dt:)`. New game-object arrays are added to `GameScene`. `SpawnKind` and `Spawner` are extended for each new type. No new abstractions beyond what each feature requires.

**Tech Stack:** Swift 5 / SpriteKit / AVFoundation / GameController framework. No unit test runner — each task is verified with `xcodebuild`.

**Build command (run after every task):**
```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```
Expected output: `** BUILD SUCCEEDED **`

---

## Task 1: Controls — L2 fire + X-button start

**Files:**
- Modify: `Bashteroids/Input/PlayerSlot.swift`
- Modify: `Bashteroids/Scenes/TitleScene.swift`

- [ ] **Step 1: Add L2 to fire handler in PlayerSlot**

In `PlayerSlot.swift`, replace `installFireHandler()` and `removeFireHandler()` with:

```swift
private func installFireHandler() {
    guard let gp = controller?.extendedGamepad else { return }
    let handler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
        if pressed { self?.firePressedEdge = true }
    }
    gp.buttonX.pressedChangedHandler = handler
    gp.rightShoulder.pressedChangedHandler = handler
    gp.leftTrigger.pressedChangedHandler = handler
}

private func removeFireHandler() {
    guard let gp = controller?.extendedGamepad else { return }
    gp.buttonX.pressedChangedHandler = nil
    gp.rightShoulder.pressedChangedHandler = nil
    gp.leftTrigger.pressedChangedHandler = nil
}
```

- [ ] **Step 2: Add X-button start polling to TitleScene**

In `TitleScene.swift`, add the new property alongside `menuWasPressed`:

```swift
private var xWasPressed: [ObjectIdentifier: Bool] = [:]
```

In `update(_:)`, add a second controller loop after the existing `menuWasPressed` loop:

```swift
for c in manager.connectedControllers {
    let pressed = c.extendedGamepad?.buttonX.isPressed ?? false
    let id = ObjectIdentifier(c)
    let was = xWasPressed[id] ?? false
    if pressed && !was { tryStart(); break }
    xWasPressed[id] = pressed
}
```

- [ ] **Step 3: Build**

```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

- [ ] **Step 4: Commit**

```sh
git add Bashteroids/Input/PlayerSlot.swift Bashteroids/Scenes/TitleScene.swift
git commit -m "feat: L2 fire button, X-button start game

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Visual changes — laser bullets + asteroid inner circle

**Files:**
- Modify: `Bashteroids/Render/Shapes.swift`
- Modify: `Bashteroids/Entities/Bullet.swift`
- Modify: `Bashteroids/Entities/Ship.swift`
- Modify: `Bashteroids/Entities/UFO.swift`

- [ ] **Step 1: Update `Shapes.bullet` to draw a 6 pt laser line**

Replace the entire `bullet` static function in `Shapes.swift`:

```swift
static func bullet(color: SKColor = .white, heading: CGFloat = 0) -> SKShapeNode {
    let half: CGFloat = 3
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -cos(heading) * half, y: -sin(heading) * half))
    path.addLine(to: CGPoint(x:  cos(heading) * half, y:  sin(heading) * half))
    let node = SKShapeNode(path: path)
    node.strokeColor = color
    node.fillColor = .clear
    node.lineWidth = 1.5
    node.lineCap = .round
    node.isAntialiased = true
    return node
}
```

- [ ] **Step 2: Add inner circle to `Shapes.asteroid`**

At the end of the `asteroid` static function in `Shapes.swift`, just before `return node`, add:

```swift
let inner = SKShapeNode(circleOfRadius: radius * 0.38)
inner.strokeColor = SKColor(white: 0.35, alpha: 1)
inner.fillColor = .clear
inner.lineWidth = 1
inner.isAntialiased = true
node.addChild(inner)
```

- [ ] **Step 3: Update `Bullet` to store color + heading and use new Shapes call**

Replace all of `Bullet.swift`:

```swift
import SpriteKit

final class Bullet: Entity {
    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat = 2
    var alive: Bool = true

    weak var owner: AnyObject?

    private let maxDistance: CGFloat?
    private var distanceTravelled: CGFloat = 0

    init(position: CGPoint,
         velocity: CGPoint,
         owner: AnyObject?,
         color: SKColor = .white,
         maxDistance: CGFloat? = nil) {
        self.velocity = velocity
        self.owner = owner
        self.maxDistance = maxDistance
        let heading = atan2(velocity.y, velocity.x)
        let n = Shapes.bullet(color: color, heading: heading)
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        guard let max = maxDistance else { return }
        distanceTravelled += velocity.length * CGFloat(dt)
        if distanceTravelled >= max { alive = false }
    }
}
```

- [ ] **Step 4: Update `Ship.fire()` to pass ship color**

In `Ship.swift`, replace the `fire()` method:

```swift
func fire() -> Bullet? {
    guard canFire else { return nil }
    reloadRemaining = Self.reloadInterval

    let nose = position + CGPoint.fromAngle(heading, length: Self.noseOffset)
    let bulletVel = velocity + CGPoint.fromAngle(heading, length: Self.bulletSpeed)
    return Bullet(position: nose, velocity: bulletVel, owner: self, color: color)
}
```

- [ ] **Step 5: Update `UFO.fire()` to pass white color**

In `UFO.swift`, replace the `fire(at:)` method:

```swift
func fire(at target: CGPoint) -> Bullet {
    let aim = (target - position).normalized()
    let bulletVel = aim * Self.bulletSpeed
    let muzzle = position + aim * (radius + 4)
    shootCooldown = TimeInterval(rng.cgFloat(in: Self.shootIntervalMin...Self.shootIntervalMax))
    return Bullet(position: muzzle, velocity: bulletVel, owner: self, color: .white)
}
```

- [ ] **Step 6: Build**

```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

- [ ] **Step 7: Commit**

```sh
git add Bashteroids/Render/Shapes.swift Bashteroids/Entities/Bullet.swift \
        Bashteroids/Entities/Ship.swift Bashteroids/Entities/UFO.swift
git commit -m "feat: laser bullet visuals, asteroid inner circle, bullet maxDistance

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Solo mode HUD fix

**Files:**
- Modify: `Bashteroids/Scenes/GameScene.swift`

- [ ] **Step 1: Update `buildHUD()` to only show active players**

Replace `buildHUD()` in `GameScene.swift`:

```swift
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
```

- [ ] **Step 2: Build**

```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```sh
git add Bashteroids/Scenes/GameScene.swift
git commit -m "fix: solo mode HUD shows only active player labels

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Difficulty scaling — asteroid speed + size ramp

**Files:**
- Modify: `Bashteroids/Systems/Spawner.swift`

- [ ] **Step 1: Replace the hardcoded speed/radius constants in `scheduleNext()`**

In `Spawner.swift`, find the asteroid branch inside `scheduleNext()`. It currently reads:

```swift
let radius = rng.cgFloat(in: 18...32)
let speed = rng.cgFloat(in: 60...120)
kind = .asteroid(radius: radius, speed: speed, seed: rng.next())
```

Replace those three lines with:

```swift
let minSpeed = min(110, 60 + CGFloat(elapsed) / 180 * 50)
let maxSpeed = min(200, 120 + CGFloat(elapsed) / 180 * 80)
let speed = rng.cgFloat(in: minSpeed...maxSpeed)
let maxRadius = elapsed > 120 ? max(18, 32 - CGFloat(elapsed - 120) / 60 * 7) : 32
let radius = rng.cgFloat(in: 18...maxRadius)
kind = .asteroid(radius: radius, speed: speed, seed: rng.next())
```

- [ ] **Step 2: Build**

```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

- [ ] **Step 3: Commit**

```sh
git add Bashteroids/Systems/Spawner.swift
git commit -m "feat: asteroid speed and size scale with elapsed time

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Power-ups — shield + dual-canon

**Files:**
- Create: `Bashteroids/Entities/PowerUp.swift`
- Modify: `Bashteroids/Render/Shapes.swift`
- Modify: `Bashteroids/Entities/Ship.swift`
- Modify: `Bashteroids/Systems/Collision.swift`
- Modify: `Bashteroids/Systems/Spawner.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift`

- [ ] **Step 1: Create `PowerUp.swift`**

```swift
import SpriteKit

enum PowerUpKind { case shield, dualCanon }

final class PowerUp: Entity {
    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat = 14
    var alive: Bool = true
    let kind: PowerUpKind

    init(kind: PowerUpKind, position: CGPoint, velocity: CGPoint) {
        self.kind = kind
        self.velocity = velocity
        let n = Shapes.powerUp(kind: kind)
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {}
}
```

- [ ] **Step 2: Add power-up shapes to `Shapes.swift`**

Add after the `bullet` function:

```swift
static func powerUp(kind: PowerUpKind) -> SKShapeNode {
    switch kind {
    case .shield:    return shieldPowerUp()
    case .dualCanon: return dualCanonPowerUp()
    }
}

private static func shieldPowerUp() -> SKShapeNode {
    let path = CGMutablePath()
    let r: CGFloat = 14
    for i in 0..<6 {
        let a = CGFloat(i) / 6 * .pi * 2
        let p = CGPoint(x: r * cos(a), y: r * sin(a))
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    let node = SKShapeNode(path: path)
    node.strokeColor = SKColor(red: 0, green: 1, blue: 1, alpha: 1)
    node.fillColor = .clear
    node.lineWidth = 1.5
    node.isAntialiased = true
    return node
}

private static func dualCanonPowerUp() -> SKShapeNode {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: -8, y:  3)); path.addLine(to: CGPoint(x: 8, y:  3))
    path.move(to: CGPoint(x: -8, y: -3)); path.addLine(to: CGPoint(x: 8, y: -3))
    let node = SKShapeNode(path: path)
    node.strokeColor = .yellow
    node.fillColor = .clear
    node.lineWidth = 1.5
    node.isAntialiased = true
    return node
}
```

- [ ] **Step 3: Add shield + dual-canon properties to `Ship.swift`**

Add these properties after `var score: Int = 0`:

```swift
var hasShield: Bool = false {
    didSet {
        if hasShield {
            let ring = SKShapeNode(circleOfRadius: Self.collisionRadius + 6)
            ring.name = "shieldRing"
            ring.strokeColor = .white
            ring.fillColor = .clear
            ring.lineWidth = 1
            ring.alpha = 0.4
            node.addChild(ring)
        } else {
            node.childNode(withName: "shieldRing")?.removeFromParent()
        }
    }
}
var hasDualCanon: Bool = false
private var canonAlternate: Bool = false
```

Add a computed property for effective reload interval after `static let reloadInterval`:

```swift
var effectiveReloadInterval: TimeInterval {
    hasDualCanon ? Self.reloadInterval / 1.5 : Self.reloadInterval
}
```

Replace `fire()`:

```swift
func fire() -> Bullet? {
    guard canFire else { return nil }
    reloadRemaining = effectiveReloadInterval

    if hasDualCanon {
        canonAlternate.toggle()
        let side: CGFloat = canonAlternate ? 1 : -1
        let offset = CGPoint.fromAngle(heading + side * .pi / 2, length: 4)
        let muzzle = position + CGPoint.fromAngle(heading, length: Self.noseOffset) + offset
        let bulletVel = velocity + CGPoint.fromAngle(heading, length: Self.bulletSpeed)
        return Bullet(position: muzzle, velocity: bulletVel, owner: self, color: color)
    } else {
        let nose = position + CGPoint.fromAngle(heading, length: Self.noseOffset)
        let bulletVel = velocity + CGPoint.fromAngle(heading, length: Self.bulletSpeed)
        return Bullet(position: nose, velocity: bulletVel, owner: self, color: color)
    }
}
```

- [ ] **Step 4: Update `Collision.swift` — shield absorption + power-up pickup**

Replace all of `Collision.swift`:

```swift
import SpriteKit

enum Collision {
    static func resolve(ships: [Ship],
                        asteroids: [Asteroid],
                        ufos: [UFO],
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
        static let asteroid    = 1
        static let ufo         = 5
        static let ship        = 20
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
```

- [ ] **Step 5: Add power-up roll + spawn to `Spawner.swift`**

Add these new enum cases to `SpawnKind`:

```swift
enum SpawnKind {
    case asteroid(radius: CGFloat, seed: UInt64)
    case ufo(baseHeading: CGFloat, seed: UInt64)
    case powerUp(kind: PowerUpKind, speed: CGFloat)
}
```

Add `case powerUp(kind: PowerUpKind)` to `PendingKind`.

Add the roll function after `rollUFO()`:

```swift
private func rollPowerUp() -> Bool {
    guard elapsed > 30 else { return false }
    return Double(rng.cgFloat(in: 0...1)) < 0.15
}
```

In `scheduleNext()`, prepend the power-up branch before the existing `if rollUFO()`:

```swift
if rollPowerUp() {
    let kind: PowerUpKind = rng.cgFloat(in: 0...1) < 0.5 ? .shield : .dualCanon
    kind_ = .powerUp(kind: kind)
    glowColor = .white
} else if rollUFO() {
```

> Note: rename the local variable `kind` to `kind_` throughout `scheduleNext()` to avoid conflict with the `PowerUpKind` enum (or use a different local name — your choice; the important thing is to avoid shadowing).

In `makeSpawn(from:)`, add a new case:

```swift
case .powerUp(let kind):
    let angle = inwardAngle(side: p.side) + rng.cgFloat(in: -0.4...0.4)
    let speed = rng.cgFloat(in: 50...90)
    let velocity = CGPoint.fromAngle(angle, length: speed)
    return Spawn(kind: .powerUp(kind: kind, speed: speed),
                 position: position,
                 velocity: velocity,
                 side: p.side)
```

- [ ] **Step 6: Add power-up array and integration to `GameScene.swift`**

Add property:

```swift
private var powerUps: [PowerUp] = []
```

In `spawn(_:)`, add a new case:

```swift
case .powerUp(let kind, _):
    let pu = PowerUp(kind: kind, position: s.position, velocity: s.velocity)
    powerUps.append(pu)
    addChild(pu.node)
```

In `update(_:)`, add after the existing `for b in bullets` loop:

```swift
for pu in powerUps { pu.update(dt: dt) }
Movement.stepBounded(powerUps, dt: dt, bounds: bounds)
```

Update the `Collision.resolve` call:

```swift
Collision.resolve(ships: ships, asteroids: asteroids, ufos: ufos,
                  bullets: bullets, powerUps: powerUps)
```

In `reapDead()`, add:

```swift
powerUps.removeAll { dead in
    if !dead.alive { dead.node.removeFromParent(); return true }
    return false
}
```

- [ ] **Step 7: Build**

```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

- [ ] **Step 8: Commit**

```sh
git add Bashteroids/Entities/PowerUp.swift Bashteroids/Render/Shapes.swift \
        Bashteroids/Entities/Ship.swift Bashteroids/Systems/Collision.swift \
        Bashteroids/Systems/Spawner.swift Bashteroids/Scenes/GameScene.swift
git commit -m "feat: shield and dual-canon power-ups

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Space mine

**Files:**
- Create: `Bashteroids/Entities/Mine.swift`
- Modify: `Bashteroids/Render/Shapes.swift`
- Modify: `Bashteroids/Systems/Spawner.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift`

- [ ] **Step 1: Create `Mine.swift`**

```swift
import SpriteKit

final class Mine: Entity {
    static let lifetime:        TimeInterval = 6.0
    static let explosionRadius: CGFloat      = 120
    static let collisionRadius: CGFloat      = 14

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat   = collisionRadius
    var alive:  Bool      = true
    var exploded: Bool    = false

    private var age:         TimeInterval = 0
    private var flashPhase:  TimeInterval = 0

    init(position: CGPoint) {
        let n = Shapes.mine()
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        age += dt
        if age >= Self.lifetime {
            alive    = false
            exploded = true
            return
        }
        let t      = CGFloat(age / Self.lifetime)        // 0 → 1
        let period = Double(1.5 - t * 1.3)               // 1.5s → 0.2s
        flashPhase += dt
        if flashPhase >= period { flashPhase -= period }
        node.alpha = flashPhase < period / 2 ? 1.0 : 0.15
    }
}
```

- [ ] **Step 2: Add `Shapes.mine()` to `Shapes.swift`**

Add after `dualCanonPowerUp()`:

```swift
static func mine() -> SKShapeNode {
    let r: CGFloat      = Mine.collisionRadius
    let spikeLen: CGFloat = 6
    let path = CGMutablePath()
    for i in 0..<6 {
        let a = CGFloat(i) / 6 * .pi * 2
        path.move(to:    CGPoint(x:  r            * cos(a), y:  r            * sin(a)))
        path.addLine(to: CGPoint(x: (r + spikeLen)* cos(a), y: (r + spikeLen)* sin(a)))
    }
    let container = SKShapeNode(path: path)
    container.strokeColor = .white
    container.fillColor   = .clear
    container.lineWidth   = 1.5
    container.isAntialiased = true

    let circle = SKShapeNode(circleOfRadius: r)
    circle.strokeColor = .white
    circle.fillColor   = .clear
    circle.lineWidth   = 1.5
    circle.isAntialiased = true
    container.addChild(circle)
    return container
}
```

- [ ] **Step 3: Add mine roll + interior spawn to `Spawner.swift`**

Add `.mine` to `SpawnKind`:

```swift
case mine
```

Add `.mine` to `PendingKind`:

```swift
case mine
```

Add roll function after `rollPowerUp()`:

```swift
private func rollMine() -> Bool {
    guard elapsed > 60 else { return false }
    let chance = min(0.20, Double((CGFloat(elapsed) - 60) / 60 * 0.20))
    return Double(rng.cgFloat(in: 0...1)) < chance
}
```

In `scheduleNext()`, add mine branch after power-up branch and before UFO branch:

```swift
} else if rollMine() {
    kind_ = .mine
    // No glow for mines — make glow optional
```

> **Note:** `Pending.glow` must become `SKShapeNode?` (optional). Change its declaration:
> ```swift
> private struct Pending {
>     let side: ScreenSide
>     let glow: SKShapeNode?   // nil for mines
>     let spawnAt: TimeInterval
>     let kind: PendingKind
> }
> ```
> In the reap loop in `update(dt:)`, change `p.glow.run(...)` to `p.glow?.run(...)`.
> For the mine branch in `scheduleNext`, do **not** create or add a glow node; pass `glow: nil`.

Add interior spawn helper after `entryPosition(side:)`:

```swift
private func interiorPosition() -> CGPoint {
    let margin: CGFloat = 80
    let x = rng.cgFloat(in: bounds.minX + margin ... bounds.maxX - margin)
    let y = rng.cgFloat(in: bounds.minY + margin ... bounds.maxY - margin)
    return CGPoint(x: x, y: y)
}
```

In `makeSpawn(from:)`, add:

```swift
case .mine:
    return Spawn(kind: .mine,
                 position: interiorPosition(),
                 velocity: .zero,
                 side: p.side)
```

- [ ] **Step 4: Integrate mines into `GameScene.swift`**

Add property:

```swift
private var mines: [Mine] = []
```

In `spawn(_:)`, add:

```swift
case .mine:
    let mine = Mine(position: s.position)
    mines.append(mine)
    addChild(mine.node)
```

In `update(_:)`, add after the bullets loop:

```swift
for m in mines { m.update(dt: dt) }
```

(Mines have zero velocity — no movement system call needed.)

In `reapDead()`, add:

```swift
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
        nearestShip(to: dead.position)?.score += 5
    }
    dead.node.removeFromParent()
    return true
}
```

- [ ] **Step 5: Build**

```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

- [ ] **Step 6: Commit**

```sh
git add Bashteroids/Entities/Mine.swift Bashteroids/Render/Shapes.swift \
        Bashteroids/Systems/Spawner.swift Bashteroids/Scenes/GameScene.swift
git commit -m "feat: space mine with flashing and radius explosion

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Alien monster

**Files:**
- Create: `Bashteroids/Entities/AlienMonster.swift`
- Modify: `Bashteroids/Render/Shapes.swift`
- Modify: `Bashteroids/Systems/Collision.swift`
- Modify: `Bashteroids/Systems/Spawner.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift`

- [ ] **Step 1: Create `AlienMonster.swift`**

```swift
import SpriteKit

final class AlienMonster: Entity {
    static let speed:            CGFloat      = 140
    static let driftAmplitude:   CGFloat      = 0.6
    static let driftRate:        CGFloat      = 0.7
    static let collisionRadius:  CGFloat      = 14
    static let bulletSpeed:      CGFloat      = 200
    static let shootIntervalMin: CGFloat      = 2.0
    static let shootIntervalMax: CGFloat      = 3.5
    static let shootRange:       CGFloat      = 200
    static let laserMaxDistance: CGFloat      = 140

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat   = collisionRadius
    var alive:  Bool      = true

    private let baseHeading: CGFloat
    private var driftPhase:  CGFloat
    private var shootCooldown: TimeInterval
    private var rng: SeededGenerator

    init(position: CGPoint, baseHeading: CGFloat, seed: UInt64) {
        self.baseHeading   = baseHeading
        self.rng           = SeededGenerator(seed: seed)
        self.driftPhase    = rng.cgFloat(in: 0 ... .pi * 2)
        self.shootCooldown = TimeInterval(rng.cgFloat(in: Self.shootIntervalMin ...
                                                           Self.shootIntervalMax))
        let n = Shapes.alienMonster()
        n.position = position
        self.node = n
        velocity = CGPoint.fromAngle(currentHeading, length: Self.speed)
    }

    private var currentHeading: CGFloat {
        baseHeading + sin(driftPhase) * Self.driftAmplitude
    }

    func update(dt: TimeInterval) {
        driftPhase    += Self.driftRate * CGFloat(dt)
        velocity       = CGPoint.fromAngle(currentHeading, length: Self.speed)
        shootCooldown  = max(0, shootCooldown - dt)
    }

    var fireReady: Bool { alive && shootCooldown <= 0 }

    func fire(at target: CGPoint) -> Bullet {
        let aim      = (target - position).normalized()
        let bulletVel = aim * Self.bulletSpeed
        let muzzle   = position + aim * (radius + 4)
        shootCooldown = TimeInterval(rng.cgFloat(in: Self.shootIntervalMin ...
                                                      Self.shootIntervalMax))
        return Bullet(position: muzzle, velocity: bulletVel, owner: self,
                      color: .white, maxDistance: Self.laserMaxDistance)
    }
}
```

- [ ] **Step 2: Add `Shapes.alienMonster()` to `Shapes.swift`**

Add after `mine()`:

```swift
static func alienMonster() -> SKShapeNode {
    let path = CGMutablePath()

    // Lower hull
    path.move(to:    CGPoint(x: -16, y:  0))
    path.addLine(to: CGPoint(x:  -8, y: -6))
    path.addLine(to: CGPoint(x:   8, y: -6))
    path.addLine(to: CGPoint(x:  16, y:  0))
    path.addLine(to: CGPoint(x: -16, y:  0))

    // Upper dome
    path.move(to:    CGPoint(x: -10, y: 0))
    path.addLine(to: CGPoint(x:  -6, y: 6))
    path.addLine(to: CGPoint(x:   6, y: 6))
    path.addLine(to: CGPoint(x:  10, y: 0))

    // Downward spikes
    for xPos: CGFloat in [-10, -4, 4, 10] {
        path.move(to:    CGPoint(x: xPos, y: -6))
        path.addLine(to: CGPoint(x: xPos, y: -13))
    }

    let node = SKShapeNode(path: path)
    node.strokeColor = SKColor(red: 0.8, green: 0.3, blue: 1.0, alpha: 1)
    node.fillColor   = .clear
    node.lineWidth   = 1.5
    node.isAntialiased = true
    return node
}
```

- [ ] **Step 3: Update `Collision.swift` to handle alien monsters**

Change the function signature to:

```swift
static func resolve(ships: [Ship],
                    asteroids: [Asteroid],
                    ufos: [UFO],
                    alienMonsters: [AlienMonster],
                    bullets: [Bullet],
                    powerUps: [PowerUp]) {
```

In the ships-collision section, add an alien-monster check after the UFO check:

```swift
for alien in alienMonsters where alien.alive {
    if overlap(ship, alien) { hitShip(ship); break }
}
if !ship.alive { continue }
```

In the bullets section, add an alien-monster check after the UFO check:

```swift
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
```

- [ ] **Step 4: Add alien roll + spawn to `Spawner.swift`**

Add `.alienMonster(baseHeading: CGFloat, seed: UInt64)` to `SpawnKind`.

Add `.alien(seed: UInt64)` to `PendingKind`.

Add roll function after `rollMine()`:

```swift
private func rollAlien() -> Bool {
    guard elapsed > 120 else { return false }
    let chance = min(0.25, Double((CGFloat(elapsed) - 120) / 60 * 0.25))
    return Double(rng.cgFloat(in: 0...1)) < chance
}
```

In `scheduleNext()`, add after the mine branch and before the UFO branch:

```swift
} else if rollAlien() {
    kind_ = .alien(seed: rng.next())
    glowColor = SKColor(red: 0.8, green: 0.3, blue: 1.0, alpha: 1)
```

In `makeSpawn(from:)`, add:

```swift
case .alien(let seed):
    let heading = inwardAngle(side: p.side) + rng.cgFloat(in: -0.4...0.4)
    return Spawn(kind: .alienMonster(baseHeading: heading, seed: seed),
                 position: position,
                 velocity: .zero,
                 side: p.side)
```

- [ ] **Step 5: Integrate alien monsters into `GameScene.swift`**

Add property:

```swift
private var alienMonsters: [AlienMonster] = []
```

In `spawn(_:)`, add:

```swift
case .alienMonster(let baseHeading, let seed):
    let alien = AlienMonster(position: s.position, baseHeading: baseHeading, seed: seed)
    alienMonsters.append(alien)
    addChild(alien.node)
```

In `update(_:)`, add:

```swift
for a in alienMonsters { a.update(dt: dt) }
Movement.stepWrapping(alienMonsters, dt: dt, bounds: bounds)
fireAlienMonstersIfReady()
```

Add helper after `fireUFOsIfReady()`:

```swift
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
```

Update `Collision.resolve` call:

```swift
Collision.resolve(ships: ships, asteroids: asteroids, ufos: ufos,
                  alienMonsters: alienMonsters,
                  bullets: bullets, powerUps: powerUps)
```

In `reapDead()`, add:

```swift
alienMonsters.removeAll { dead in
    if !dead.alive {
        Explosion.burst(at: dead.position, radius: dead.radius * 1.2, parent: self)
        audio.playExplosion()
        dead.node.removeFromParent()
        return true
    }
    return false
}
```

In mine explosion loop in `reapDead()`, also kill alien monsters within radius (add after the UFO loop):

```swift
for alien in alienMonsters where alien.alive {
    if alien.position.distance(to: dead.position) < Mine.explosionRadius {
        alien.alive = false
    }
}
```

- [ ] **Step 6: Build**

```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

- [ ] **Step 7: Commit**

```sh
git add Bashteroids/Entities/AlienMonster.swift Bashteroids/Render/Shapes.swift \
        Bashteroids/Systems/Collision.swift Bashteroids/Systems/Spawner.swift \
        Bashteroids/Scenes/GameScene.swift
git commit -m "feat: alien monster with short-range lasers

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Player names

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift`

- [ ] **Step 1: Add name-entry state to `TitleScene.swift`**

Add properties after `private var transitioning = false`:

```swift
private var activeNameSlot: Int? = nil
private var nameBuffer: String = ""
private var prevSlotCount: Int = 0
private var slotAWasPressed: [Int: Bool] = [:]
```

- [ ] **Step 2: Enter name mode on new join**

In `didMove(to:)`, replace the `manager.onSlotsChanged` closure body:

```swift
manager.onSlotsChanged = { [weak self] in
    guard let self else { return }
    let newCount = self.manager.slots.count
    if newCount > self.prevSlotCount {
        let idx = newCount - 1
        self.activeNameSlot = idx
        self.nameBuffer = UserDefaults.standard.string(
            forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
        self.manager.setJoinEnabled(false)
    }
    self.prevSlotCount = newCount
    self.renderSlots()
}
```

- [ ] **Step 3: Handle keyboard input for name entry in `pressesBegan`**

Replace the entire `pressesBegan(_:with:)` method:

```swift
override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    for press in presses {
        guard let key = press.key else { continue }

        if activeNameSlot != nil {
            switch key.keyCode {
            case .keyboardReturnOrEnter:
                confirmName()
            case .keyboardDeleteOrBackspace:
                if !nameBuffer.isEmpty { nameBuffer.removeLast(); renderSlots() }
            default:
                if let chars = key.characters,
                   chars.count == 1,
                   let scalar = chars.unicodeScalars.first,
                   CharacterSet.alphanumerics.union(.init(charactersIn: " ")).contains(scalar),
                   nameBuffer.count < 8 {
                    nameBuffer += chars.uppercased()
                    renderSlots()
                }
            }
            return
        }

        switch key.keyCode {
        case .keyboardSpacebar, .keyboardReturnOrEnter:
            tryStart()
            return
        case .keyboardEscape:
            MacFullScreen.exitIfActive()
            return
        default:
            break
        }
    }
    super.pressesBegan(presses, with: event)
}
```

- [ ] **Step 4: Add `confirmName()` helper**

Add after `tryStart()`:

```swift
private func confirmName() {
    guard let idx = activeNameSlot else { return }
    let trimmed = nameBuffer.trimmingCharacters(in: .whitespaces)
    let name = trimmed.isEmpty ? "P\(idx + 1)" : trimmed
    UserDefaults.standard.set(name, forKey: "player_name_\(idx)")
    activeNameSlot = nil
    nameBuffer = ""
    let atMax = manager.slots.count >= ControllerManager.maxPlayers
    manager.setJoinEnabled(!atMax)
    renderSlots()
}
```

- [ ] **Step 5: Poll A button for re-entry in `update(_:)`**

In `update(_:)`, add before the existing controller loop:

```swift
if activeNameSlot == nil {
    for (i, slot) in manager.slots.enumerated() {
        let pressed = slot.controller?.extendedGamepad?.buttonA.isPressed ?? false
        let was = slotAWasPressed[i] ?? false
        if pressed && !was {
            activeNameSlot = i
            nameBuffer = UserDefaults.standard.string(
                forKey: "player_name_\(i)") ?? "P\(i + 1)"
            manager.setJoinEnabled(false)
            renderSlots()
            break
        }
        slotAWasPressed[i] = pressed
    }
} else {
    for (i, slot) in manager.slots.enumerated() {
        slotAWasPressed[i] = slot.controller?.extendedGamepad?.buttonA.isPressed ?? false
    }
}
```

- [ ] **Step 6: Show name label below each slot tile in `renderSlots()`**

At the end of the `for i in 0..<count` loop in `renderSlots()`, after adding the existing tile and ship/label nodes, append:

```swift
let storedName = UserDefaults.standard.string(forKey: "player_name_\(i)") ?? "P\(i + 1)"
let displayText: String
if activeNameSlot == i {
    displayText = nameBuffer + "_"
} else if claimed {
    displayText = storedName
} else {
    displayText = ""
}
if !displayText.isEmpty {
    let nameLabel = SKLabelNode(text: displayText)
    nameLabel.fontName = "AvenirNext-Regular"
    nameLabel.fontSize = 14
    nameLabel.fontColor = color
    nameLabel.position = CGPoint(x: x, y: y - 69)
    slotsLayer.addChild(nameLabel)
}
```

- [ ] **Step 7: Use stored names in `GameScene` HUD**

Replace `buildHUD()` in `GameScene.swift`:

```swift
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
```

Replace `updateHUD()`:

```swift
private func updateHUD() {
    for (i, label) in scoreLabels.enumerated() {
        guard i < ships.count else { continue }
        let name = UserDefaults.standard.string(forKey: "player_name_\(i)") ?? "P\(i + 1)"
        label.text = "\(name)  \(ships[i].score)"
    }
}
```

- [ ] **Step 8: Build**

```sh
xcodebuild -project Bashteroids.xcodeproj \
  -scheme Bashteroids \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

- [ ] **Step 9: Commit**

```sh
git add Bashteroids/Scenes/TitleScene.swift Bashteroids/Scenes/GameScene.swift
git commit -m "feat: player name entry with keyboard, persisted per slot

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
