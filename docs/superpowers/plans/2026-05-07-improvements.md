# Improvements Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land four small gameplay tweaks driven by `improvements.md`: top-10 highscores, mine damage zoning, minelayer powerup, and BATTLE powerup TTL.

**Architecture:** Seven independent tasks. The first three are small, isolated changes. Tasks 4–6 add the minelayer powerup, split into foundation (kind enum + visuals + Mine lifetime override), state + input plumbing, and behavior wiring. Task 7 updates README docs.

**Tech Stack:** Swift 5 + SpriteKit, single Xcode target, three destinations (iOS / Mac Catalyst / tvOS).

**Spec:** `docs/superpowers/specs/2026-05-07-improvements-design.md`

---

## File Structure

**Modified files:**
- `Bashteroids/Utils/HighScore.swift` — `maxEntries` 3 → 10.
- `Bashteroids/Entities/Mine.swift` — add `innerKillRadius`, bump `explosionRadius` 120 → 140, add `lifetimeOverride` init parameter, clamp flash period.
- `Bashteroids/Entities/Ship.swift` — add `minelayerArmed`, `laidMine`, `minelayerMarker`; init wiring; `makeMinelayerMarker()` helper.
- `Bashteroids/Entities/PowerUp.swift` — add `.minelayer` to `PowerUpKind`; add `lifetime: TimeInterval?` field; flesh out `update(dt:)`.
- `Bashteroids/Render/Shapes.swift` — add `minelayerPowerUp()`; route `.minelayer` in `powerUp(kind:)`.
- `Bashteroids/Systems/Collision.swift` — add `.minelayer` pickup arm; mine zoning in the explosion branch (the explosion logic actually lives in `GameScene.reapDead` today; the zoning change goes there).
- `Bashteroids/Systems/Spawner.swift` — add `lifetime` field to `SpawnKind.powerUp`; update all spawn-site call sites; add `.minelayer` to survival kinds; add `.minelayer` to BATTLE kinds.
- `Bashteroids/Input/PlayerSlot.swift` — add `minelayerActionPressedThisFrame: Bool` to `PlayerInput`; wire `buttonY` edge handler in `installFireHandler` / `removeFireHandler`; consume in `snapshot()`.
- `Bashteroids/Input/KeyboardInputState.swift` — add `minelayerEdge` + `mPressed()` setter.
- `Bashteroids/Scenes/GameScene.swift` — mine zoning rewrite in `reapDead`; `handleKeyDown` routes `keyM` to `manager.keyboardInput.mPressed()`; new `handleMinelayerAction(ship:)` helper called from `applyInputs`; `.powerUp` spawn case reads `lifetime`.
- `Bashteroids/Scenes/GameScene+Debug.swift` — add `Shift+4` minelayer shortcut.
- `README.md` — add Minelayer row to Power-ups table; update Mine row in Entities table; mention top-10 highscores.

**No new files. No deletions.**

---

## Task 1: Top-10 highscores

A 1-line change in `HighScore.swift`. The TitleScene already iterates `HighScore.top.enumerated()` and renders however many entries exist; bumping the cap is sufficient.

**Files:**
- Modify: `Bashteroids/Utils/HighScore.swift`

- [ ] **Step 1: Bump `maxEntries`**

In `Bashteroids/Utils/HighScore.swift`, change:

```swift
    static let maxEntries = 3
```

to:

```swift
    static let maxEntries = 10
```

- [ ] **Step 2: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three end with `** BUILD SUCCEEDED **`. Zero new warnings (the pre-existing `appintentsmetadataprocessor` warning is OK to ignore).

- [ ] **Step 3: Commit**

```bash
git add Bashteroids/Utils/HighScore.swift
git commit -m "feat: top-10 highscores (was top-3)

The TitleScene already iterates HighScore.top, so just raising
the cap is enough. Existing data is preserved; the next 7 saved
scores fill the new slots."
```

---

## Task 2: Mine damage zoning

Adds a two-zone explosion to mines. Inner kill zone (≤ 60 px) bypasses shields; outer zone (60–140 px, was a single 120 px zone) consumes a shield or kills if no shield. Bumps the outer radius 120 → 140 and the visual blast follows.

**Files:**
- Modify: `Bashteroids/Entities/Mine.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift` (`reapDead` mine-explosion branch)

- [ ] **Step 1: Add `innerKillRadius` and bump `explosionRadius` in `Mine.swift`**

In `Bashteroids/Entities/Mine.swift`, the existing constants block:

```swift
    static let lifetime:        TimeInterval = 6.0
    static let explosionRadius: CGFloat      = 120
    static let collisionRadius: CGFloat      = 14
```

becomes:

```swift
    static let lifetime:        TimeInterval = 6.0
    static let innerKillRadius: CGFloat      = 60
    static let explosionRadius: CGFloat      = 140
    static let collisionRadius: CGFloat      = 14
```

- [ ] **Step 2: Rewrite the ship-damage section of `reapDead`**

In `Bashteroids/Scenes/GameScene.swift`, find the existing mine-exploded ship loop in `reapDead()`. The current block:

```swift
                for ship in ships where ship.alive {
                    if ship.position.distance(to: dead.position) < Mine.explosionRadius {
                        if ship.shieldCount > 0 {
                            ship.shieldCount -= 1
                        } else {
                            ship.alive = false
                        }
                    }
                }
```

Replace with:

```swift
                for ship in ships where ship.alive {
                    let d = ship.position.distance(to: dead.position)
                    if d <= Mine.innerKillRadius {
                        // Direct hit: shields don't save you.
                        ship.alive = false
                    } else if d < Mine.explosionRadius {
                        // Outer blast: consume a shield, otherwise die.
                        if ship.shieldCount > 0 {
                            ship.shieldCount -= 1
                        } else {
                            ship.alive = false
                        }
                    }
                }
```

The UFO and alien-monster loops below stay unchanged — they continue to die at any distance ≤ `Mine.explosionRadius` (now 140). The visible `Explosion.burst(...)` call also already uses `Mine.explosionRadius`, so the visual matches.

- [ ] **Step 3: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero new warnings.

- [ ] **Step 4: Commit**

```bash
git add Bashteroids/Entities/Mine.swift Bashteroids/Scenes/GameScene.swift
git commit -m "feat: two-zone mine damage with bumped 140 px outer radius

Direct hits (≤ 60 px from the mine) now kill outright regardless
of shield count. The outer blast (60–140 px, up from a flat 120
px) keeps the existing shield-consume-or-die behavior. UFOs and
aliens still die at any distance inside the outer radius. The
visual blast already keys off Mine.explosionRadius, so its size
follows automatically."
```

---

## Task 3: BATTLE powerup TTL

Adds an optional `lifetime` to `PowerUp` and a 30 s default for BATTLE drops. The last 5 s of life fade the alpha 1.0 → 0.0 linearly.

**Files:**
- Modify: `Bashteroids/Entities/PowerUp.swift`
- Modify: `Bashteroids/Systems/Spawner.swift` (`SpawnKind.powerUp` gains a `lifetime` field; all callers updated)
- Modify: `Bashteroids/Scenes/GameScene.swift` (`spawn(_:)` `.powerUp` case reads `lifetime`)
- Modify: `Bashteroids/Scenes/GameScene+Debug.swift` (`.powerUp` constructor passes `lifetime: nil`)

- [ ] **Step 1: Add `lifetime` field and update body of `PowerUp.update(dt:)`**

In `Bashteroids/Entities/PowerUp.swift`, the existing class:

```swift
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

becomes:

```swift
final class PowerUp: Entity {
    static let fadeWindow: TimeInterval = 5

    let node: SKNode
    var velocity: CGPoint
    let radius: CGFloat = 14
    var alive: Bool = true
    let kind: PowerUpKind
    var lifetime: TimeInterval?
    private var age: TimeInterval = 0

    init(kind: PowerUpKind, position: CGPoint, velocity: CGPoint) {
        self.kind = kind
        self.velocity = velocity
        let n = Shapes.powerUp(kind: kind)
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        guard let life = lifetime else { return }
        age += dt
        let remaining = life - age
        if remaining <= 0 {
            alive = false
            return
        }
        if remaining < Self.fadeWindow {
            node.alpha = max(0, CGFloat(remaining / Self.fadeWindow))
        }
    }
}
```

- [ ] **Step 2: Add `lifetime` to `SpawnKind.powerUp` in `Spawner.swift`**

In `Bashteroids/Systems/Spawner.swift`, the existing enum case:

```swift
enum SpawnKind {
    case asteroid(radius: CGFloat, seed: UInt64)
    case ufo(baseHeading: CGFloat, seed: UInt64)
    case alienMonster(baseHeading: CGFloat, seed: UInt64)
    case powerUp(kind: PowerUpKind, speed: CGFloat)
    case mine
    case rock(radius: CGFloat, seed: UInt64)
    case snake(baseHeading: CGFloat, seed: UInt64)
}
```

becomes:

```swift
enum SpawnKind {
    case asteroid(radius: CGFloat, seed: UInt64)
    case ufo(baseHeading: CGFloat, seed: UInt64)
    case alienMonster(baseHeading: CGFloat, seed: UInt64)
    case powerUp(kind: PowerUpKind, speed: CGFloat, lifetime: TimeInterval?)
    case mine
    case rock(radius: CGFloat, seed: UInt64)
    case snake(baseHeading: CGFloat, seed: UInt64)
}
```

- [ ] **Step 3: Update `Spawner.makeSpawn(...)` powerUp case to pass `lifetime: nil`**

In the same file, `makeSpawn(...)` constructs `Spawn(kind: .powerUp(kind:speed:), ...)`. Find:

```swift
        case .powerUp(let kind):
            let angle = inwardAngle + rng.cgFloat(in: -0.4...0.4)
            let speed = rng.cgFloat(in: 50...90)
            let velocity = CGPoint.fromAngle(angle, length: speed)
            return Spawn(kind: .powerUp(kind: kind, speed: speed),
                         position: position,
                         velocity: velocity,
                         side: p.side)
```

becomes:

```swift
        case .powerUp(let kind):
            let angle = inwardAngle + rng.cgFloat(in: -0.4...0.4)
            let speed = rng.cgFloat(in: 50...90)
            let velocity = CGPoint.fromAngle(angle, length: speed)
            return Spawn(kind: .powerUp(kind: kind, speed: speed, lifetime: nil),
                         position: position,
                         velocity: velocity,
                         side: p.side)
```

- [ ] **Step 4: Update `Spawner.updateBattlePowerUps(...)` to pass `lifetime: 30`**

Same file, find the `return Spawn(...)` at the end of `updateBattlePowerUps`:

```swift
        return Spawn(kind: .powerUp(kind: chosen, speed: 0),
                     position: position,
                     velocity: .zero,
                     side: .top)
```

becomes:

```swift
        return Spawn(kind: .powerUp(kind: chosen, speed: 0, lifetime: 30),
                     position: position,
                     velocity: .zero,
                     side: .top)
```

- [ ] **Step 5: Update `GameScene.spawn(_:)` to read `lifetime`**

In `Bashteroids/Scenes/GameScene.swift`, find the `.powerUp` case in `spawn(_:)`:

```swift
        case .powerUp(let kind, _):
            let pu = PowerUp(kind: kind, position: s.position, velocity: s.velocity)
            powerUps.append(pu)
            addChild(pu.node)
```

becomes:

```swift
        case .powerUp(let kind, _, let lifetime):
            let pu = PowerUp(kind: kind, position: s.position, velocity: s.velocity)
            pu.lifetime = lifetime
            powerUps.append(pu)
            addChild(pu.node)
```

- [ ] **Step 6: Update `GameScene+Debug.swift` to construct with `lifetime: nil`**

In `Bashteroids/Scenes/GameScene+Debug.swift`, find:

```swift
    private func debugSpawnPowerUp(_ kind: PowerUpKind) {
        let entry = randomEdgeEntry()
        let velocity = CGPoint.fromAngle(entry.inwardAngle, length: 70)
        spawn(Spawn(kind: .powerUp(kind: kind, speed: 70),
                    position: entry.position, velocity: velocity, side: entry.side))
    }
```

becomes:

```swift
    private func debugSpawnPowerUp(_ kind: PowerUpKind) {
        let entry = randomEdgeEntry()
        let velocity = CGPoint.fromAngle(entry.inwardAngle, length: 70)
        spawn(Spawn(kind: .powerUp(kind: kind, speed: 70, lifetime: nil),
                    position: entry.position, velocity: velocity, side: entry.side))
    }
```

- [ ] **Step 7: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero new warnings. The most likely failure is missing a call site — `grep -rn "\.powerUp(kind:" Bashteroids/` should match the four sites edited above (Spawner.makeSpawn, Spawner.updateBattlePowerUps, GameScene.spawn, GameScene+Debug.debugSpawnPowerUp). If a fifth match exists, update it the same way.

- [ ] **Step 8: Commit**

```bash
git add Bashteroids/Entities/PowerUp.swift \
        Bashteroids/Systems/Spawner.swift \
        Bashteroids/Scenes/GameScene.swift \
        Bashteroids/Scenes/GameScene+Debug.swift
git commit -m "feat(battle): 30s TTL with 5s alpha fade on uncollected powerups

PowerUp gains an optional lifetime; survival passes nil (current
behavior preserved), BATTLE passes 30. The last 5 s of life
linearly fades node.alpha 1 → 0. SpawnKind.powerUp gains the
lifetime field, all callers updated."
```

---

## Task 4: Minelayer foundation

Adds the `.minelayer` `PowerUpKind`, the powerup icon, and the `Mine.lifetimeOverride` initializer parameter. No callers yet (next tasks wire it up). This task is intentionally small and safe — every change is localized.

**Files:**
- Modify: `Bashteroids/Entities/PowerUp.swift`
- Modify: `Bashteroids/Entities/Mine.swift`
- Modify: `Bashteroids/Render/Shapes.swift`

- [ ] **Step 1: Add `.minelayer` to `PowerUpKind`**

In `Bashteroids/Entities/PowerUp.swift`:

```swift
enum PowerUpKind { case shield, dualCanon, boost }
```

becomes:

```swift
enum PowerUpKind { case shield, dualCanon, boost, minelayer }
```

This will trigger non-exhaustive `switch` errors at all call sites (`Shapes.powerUp(kind:)`, `Spawner` weight tables, `Collision` pickup arm). Those are addressed in subsequent tasks; for this task only add `Shapes.powerUp(kind:)` to keep the build green.

- [ ] **Step 2: Add `Shapes.minelayerPowerUp()` and route `.minelayer` in `powerUp(kind:)`**

In `Bashteroids/Render/Shapes.swift`, find:

```swift
    static func powerUp(kind: PowerUpKind) -> SKShapeNode {
        switch kind {
        case .shield:    return shieldPowerUp()
        case .dualCanon: return dualCanonPowerUp()
        case .boost:     return boostPowerUp()
        }
    }
```

becomes:

```swift
    static func powerUp(kind: PowerUpKind) -> SKShapeNode {
        switch kind {
        case .shield:    return shieldPowerUp()
        case .dualCanon: return dualCanonPowerUp()
        case .boost:     return boostPowerUp()
        case .minelayer: return minelayerPowerUp()
        }
    }
```

Add the helper near the other powerup helpers:

```swift
    private static func minelayerPowerUp() -> SKShapeNode {
        // Spiked-circle silhouette evoking a mine. Six radial spikes.
        let r: CGFloat       = 6
        let spikeLen: CGFloat = 6
        let path = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * .pi * 2
            path.move(to:    CGPoint(x:  r             * cos(a), y:  r             * sin(a)))
            path.addLine(to: CGPoint(x: (r + spikeLen) * cos(a), y: (r + spikeLen) * sin(a)))
        }
        let container = SKShapeNode(path: path)
        container.strokeColor = SKColor(white: 0.7, alpha: 1)
        container.fillColor   = .clear
        container.lineWidth   = 1.5
        container.isAntialiased = true

        let circle = SKShapeNode(circleOfRadius: r)
        circle.strokeColor = SKColor(white: 0.7, alpha: 1)
        circle.fillColor   = .clear
        circle.lineWidth   = 1.5
        circle.isAntialiased = true
        container.addChild(circle)
        return container
    }
```

- [ ] **Step 3: Add `lifetimeOverride` init parameter to `Mine.swift`**

In `Bashteroids/Entities/Mine.swift`, replace the existing class body. The full updated file:

```swift
import SpriteKit

final class Mine: Entity {
    static let lifetime:        TimeInterval = 6.0
    static let innerKillRadius: CGFloat      = 60
    static let explosionRadius: CGFloat      = 140
    static let collisionRadius: CGFloat      = 14

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat   = collisionRadius
    var alive:  Bool      = true
    var exploded: Bool    = false

    private let effectiveLifetime: TimeInterval
    private var age:        TimeInterval = 0
    private var flashPhase: TimeInterval = 0

    init(position: CGPoint, lifetimeOverride: TimeInterval? = nil) {
        self.effectiveLifetime = lifetimeOverride ?? Self.lifetime
        let n = Shapes.mine()
        n.position = position
        self.node = n
    }

    func update(dt: TimeInterval) {
        age += dt
        if age >= effectiveLifetime {
            alive    = false
            exploded = true
            return
        }
        let t      = CGFloat(age / effectiveLifetime)
        let period = max(0.2, Double(1.5 - t * 1.3))
        flashPhase += dt
        flashPhase = flashPhase.truncatingRemainder(dividingBy: period)
        node.alpha = flashPhase < period / 2 ? 1.0 : 0.15
    }
}
```

(`innerKillRadius` and the bumped `explosionRadius` are already in the file from Task 2 — verify they're not double-added.)

The default `lifetimeOverride: TimeInterval? = nil` keeps the existing call site `Mine(position: ...)` (in `GameScene.spawn`) working unchanged.

The `max(0.2, ...)` clamp on the flash period prevents the value from going negative on a 60 s mine (the formula would otherwise reach -0.6 at t=1.6, but t never exceeds 1 here; even at t=1 the period is 0.2 — so the clamp is mostly defensive).

- [ ] **Step 4: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero new warnings. The new `.minelayer` case is non-exhaustive in `Spawner` weight arrays (literal arrays only — these are a runtime concern, not a switch) and `Collision` pickup. The `Spawner` weight arrays are `[PowerUpKind]` literals which Swift won't flag for exhaustiveness; they just won't include `.minelayer` until Task 6. The `Collision` pickup arm uses a `switch` on `pu.kind` — Swift WILL flag that as non-exhaustive. Address that in Task 6 by adding the `.minelayer` arm.

If the Collision switch fails to compile, **Task 6 must follow immediately** — don't try to land Task 4 alone if it fails.

Actually wait: this is a problem. Let me re-plan.

In fact the `.minelayer` enum case will break the `Collision.swift` switch for the powerup pickup. To keep the build green at the end of Task 4, Task 4 must include a no-op `.minelayer` arm in the `Collision` switch. Then Task 6 replaces that no-op with the real pickup behavior.

- [ ] **Step 5 (corrective): Add a placeholder `.minelayer` arm to `Collision.swift`**

In `Bashteroids/Systems/Collision.swift`, find the powerup pickup switch:

```swift
                    switch pu.kind {
                    case .shield:    ship.shieldCount = min(ship.shieldCount + 1, Ship.maxShieldStack)
                    case .dualCanon: ship.canonLevel  = min(ship.canonLevel + 1, Ship.maxCanonLevel)
                    case .boost:     ship.boostLevel  = min(ship.boostLevel + 1, Ship.maxBoostLevel)
                    }
```

becomes:

```swift
                    switch pu.kind {
                    case .shield:    ship.shieldCount = min(ship.shieldCount + 1, Ship.maxShieldStack)
                    case .dualCanon: ship.canonLevel  = min(ship.canonLevel + 1, Ship.maxCanonLevel)
                    case .boost:     ship.boostLevel  = min(ship.boostLevel + 1, Ship.maxBoostLevel)
                    case .minelayer: break // Wired in Task 6.
                    }
```

The `break` no-op makes the build green now without doing the real work. Task 6 replaces this with the actual arm.

- [ ] **Step 6: Re-build all three destinations**

(Same xcodebuild invocations as Step 4.) Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add Bashteroids/Entities/PowerUp.swift \
        Bashteroids/Entities/Mine.swift \
        Bashteroids/Render/Shapes.swift \
        Bashteroids/Systems/Collision.swift
git commit -m "feat(minelayer): foundation — kind, icon, mine lifetime override

Adds PowerUpKind.minelayer with a spiked-circle icon, and an
optional lifetimeOverride to Mine init so player-laid mines can
run a 60 s timer instead of the spawner default 6 s. The flash
period is clamped to 0.2 s to keep long-lived mines visible.
A placeholder .minelayer arm in Collision pickup keeps the
build green; Task 6 wires the real behavior."
```

---

## Task 5: Minelayer ship state + input plumbing

Adds `Ship.minelayerArmed`, `Ship.laidMine`, the ship marker, plus the input wiring (`buttonY` on controller, `M` on keyboard, edge-triggered through `PlayerInput`).

**Files:**
- Modify: `Bashteroids/Entities/Ship.swift`
- Modify: `Bashteroids/Input/PlayerSlot.swift`
- Modify: `Bashteroids/Input/KeyboardInputState.swift`
- Modify: `Bashteroids/Input/KeyboardManager.swift`

- [ ] **Step 1: Add ship state fields and the marker to `Ship.swift`**

In `Bashteroids/Entities/Ship.swift`, add to the ivar block alongside the other powerup state (after `var boostLevel: Int = 0 { didSet { … } }`):

```swift
    var minelayerArmed: Bool = false {
        didSet {
            guard minelayerArmed != oldValue else { return }
            minelayerMarker.alpha = minelayerArmed ? 1 : 0
        }
    }
    weak var laidMine: Mine?

    private let minelayerMarker: SKShapeNode
```

In `init(playerIndex:color:position:heading:)`, after the existing marker construction (search for `boost.alpha = 0`), add:

```swift
        let mineMarker = Ship.makeMinelayerMarker()
        mineMarker.alpha = 0
        n.addChild(mineMarker)
        self.minelayerMarker = mineMarker
```

Add the static helper near the other `make*Marker()` helpers:

```swift
    private static func makeMinelayerMarker() -> SKShapeNode {
        // Tiny mine silhouette near the rear of the ship.
        let r: CGFloat       = 2.5
        let spikeLen: CGFloat = 2.5
        let path = CGMutablePath()
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * .pi * 2
            path.move(to:    CGPoint(x: -8 + r             * cos(a), y: r             * sin(a)))
            path.addLine(to: CGPoint(x: -8 + (r + spikeLen) * cos(a), y: (r + spikeLen) * sin(a)))
        }
        let n = SKShapeNode(path: path)
        n.strokeColor = SKColor(white: 0.7, alpha: 1)
        n.fillColor   = .clear
        n.lineWidth   = 1
        n.isAntialiased = true

        let circle = SKShapeNode(circleOfRadius: r)
        circle.position = CGPoint(x: -8, y: 0)
        circle.strokeColor = SKColor(white: 0.7, alpha: 1)
        circle.fillColor   = .clear
        circle.lineWidth   = 1
        circle.isAntialiased = true
        n.addChild(circle)
        return n
    }
```

- [ ] **Step 2: Add `minelayerActionPressedThisFrame` to `PlayerInput`**

In `Bashteroids/Input/PlayerSlot.swift`, the existing `PlayerInput`:

```swift
struct PlayerInput {
    var turn: CGFloat = 0
    var thrust: Bool = false
    var brake: Bool = false
    var firePressedThisFrame: Bool = false
}
```

becomes:

```swift
struct PlayerInput {
    var turn: CGFloat = 0
    var thrust: Bool = false
    var brake: Bool = false
    var firePressedThisFrame: Bool = false
    var minelayerActionPressedThisFrame: Bool = false
}
```

- [ ] **Step 3: Add edge tracking to `PlayerSlot` and wire `buttonY`**

In the same file, add a private edge flag near `private var firePressedEdge: Bool = false`:

```swift
    private var minelayerEdge: Bool = false
```

Update `installFireHandler()` (extendedGamepad branch only — the microGamepad doesn't have `buttonY`):

```swift
    private func installFireHandler() {
        let handler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.firePressedEdge = true }
        }
        if let gp = controller?.extendedGamepad {
            gp.buttonX.pressedChangedHandler = handler
            gp.rightShoulder.pressedChangedHandler = handler
            gp.leftTrigger.pressedChangedHandler = handler

            gp.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.minelayerEdge = true }
            }
            return
        }
        if let mg = controller?.microGamepad {
            mg.buttonA.pressedChangedHandler = handler
        }
    }
```

Update `removeFireHandler()`:

```swift
    private func removeFireHandler() {
        if let gp = controller?.extendedGamepad {
            gp.buttonX.pressedChangedHandler = nil
            gp.rightShoulder.pressedChangedHandler = nil
            gp.leftTrigger.pressedChangedHandler = nil
            gp.buttonY.pressedChangedHandler = nil
            return
        }
        if let mg = controller?.microGamepad {
            mg.buttonA.pressedChangedHandler = nil
        }
    }
```

Update `snapshot()` to consume the edge. Find:

```swift
    func snapshot() -> PlayerInput {
        if let kb = keyboard { return kb.snapshot() }

        let edge = firePressedEdge
        firePressedEdge = false
        ...
```

Become:

```swift
    func snapshot() -> PlayerInput {
        if let kb = keyboard { return kb.snapshot() }

        let edge = firePressedEdge
        firePressedEdge = false
        let mineEdge = minelayerEdge
        minelayerEdge = false
        ...
```

Then, in the `extendedGamepad` branch of `snapshot()`, find the `return PlayerInput(...)` and add the field:

```swift
            return PlayerInput(turn: turn, thrust: thrust, brake: brake, firePressedThisFrame: edge)
```

becomes:

```swift
            return PlayerInput(turn: turn,
                               thrust: thrust,
                               brake: brake,
                               firePressedThisFrame: edge,
                               minelayerActionPressedThisFrame: mineEdge)
```

In the `microGamepad` branch (Siri Remote):

```swift
            return PlayerInput(turn: turn, thrust: thrust, brake: brake, firePressedThisFrame: edge)
```

becomes:

```swift
            return PlayerInput(turn: turn,
                               thrust: thrust,
                               brake: brake,
                               firePressedThisFrame: edge,
                               minelayerActionPressedThisFrame: false)
```

(Siri Remote has no spare button for the minelayer — explicitly false.)

In the no-controller fallback at the end of `snapshot()`, similarly:

```swift
        return PlayerInput(turn: 0, thrust: false, brake: false, firePressedThisFrame: edge)
```

becomes:

```swift
        return PlayerInput(turn: 0,
                           thrust: false,
                           brake: false,
                           firePressedThisFrame: edge,
                           minelayerActionPressedThisFrame: mineEdge)
```

- [ ] **Step 4: Add minelayer edge to `KeyboardInputState`**

In `Bashteroids/Input/KeyboardInputState.swift`, add a private edge field and a `mPressed()` setter, then return the field in `snapshot()`. The existing class:

```swift
final class KeyboardInputState {
    private var spaceEdge = false

    func spaceDown() { spaceEdge = true }

    func snapshot() -> PlayerInput {
        let kb = GCKeyboard.coalesced?.keyboardInput
        let leftHeld  = kb?.button(forKeyCode: .leftArrow)?.isPressed  ?? false
        let rightHeld = kb?.button(forKeyCode: .rightArrow)?.isPressed ?? false
        let upHeld    = kb?.button(forKeyCode: .upArrow)?.isPressed    ?? false
        let downHeld  = kb?.button(forKeyCode: .downArrow)?.isPressed  ?? false

        let fire = spaceEdge; spaceEdge = false
        let turn: CGFloat = rightHeld ? 1 : (leftHeld ? -1 : 0)
        return PlayerInput(turn: turn, thrust: upHeld, brake: downHeld, firePressedThisFrame: fire)
    }

    func releaseAll() {
        spaceEdge = false
    }
}
```

becomes:

```swift
final class KeyboardInputState {
    private var spaceEdge = false
    private var mEdge = false

    func spaceDown() { spaceEdge = true }
    func mPressed()  { mEdge = true }

    func snapshot() -> PlayerInput {
        let kb = GCKeyboard.coalesced?.keyboardInput
        let leftHeld  = kb?.button(forKeyCode: .leftArrow)?.isPressed  ?? false
        let rightHeld = kb?.button(forKeyCode: .rightArrow)?.isPressed ?? false
        let upHeld    = kb?.button(forKeyCode: .upArrow)?.isPressed    ?? false
        let downHeld  = kb?.button(forKeyCode: .downArrow)?.isPressed  ?? false

        let fire = spaceEdge; spaceEdge = false
        let mine = mEdge;     mEdge     = false
        let turn: CGFloat = rightHeld ? 1 : (leftHeld ? -1 : 0)
        return PlayerInput(turn: turn,
                           thrust: upHeld,
                           brake: downHeld,
                           firePressedThisFrame: fire,
                           minelayerActionPressedThisFrame: mine)
    }

    func releaseAll() {
        spaceEdge = false
        mEdge     = false
    }
}
```

- [ ] **Step 5: Wire `keyM` in `GameScene.handleKeyDown(_:)` to call `mPressed()`**

The `KeyboardManager` already forwards every keydown to whatever scene installed `onKeyDown`. The `GameScene` keydown handler (in `Bashteroids/Scenes/GameScene.swift`) currently:

```swift
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
```

becomes:

```swift
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
```

- [ ] **Step 6: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`. The minelayer state and input edges flow but are not yet consumed (that's Task 6).

- [ ] **Step 7: Commit**

```bash
git add Bashteroids/Entities/Ship.swift \
        Bashteroids/Input/PlayerSlot.swift \
        Bashteroids/Input/KeyboardInputState.swift \
        Bashteroids/Scenes/GameScene.swift
git commit -m "feat(minelayer): ship state + input plumbing

Adds Ship.minelayerArmed, Ship.laidMine (weak), and a minelayer
marker. PlayerInput grows minelayerActionPressedThisFrame, fed by
buttonY on extendedGamepad and the M key on the keyboard. Siri
Remote (microGamepad) reports false — no spare button. Action
consumption lands in the next commit."
```

---

## Task 6: Minelayer behavior wiring

Spawner roulette gains `.minelayer`; Collision pickup arm replaces its placeholder; GameScene consumes the input edge per ship and invokes the place / detonate logic; debug shortcut added.

**Files:**
- Modify: `Bashteroids/Systems/Spawner.swift`
- Modify: `Bashteroids/Systems/Collision.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift`
- Modify: `Bashteroids/Scenes/GameScene+Debug.swift`

- [ ] **Step 1: Add `.minelayer` to the survival roulette in `Spawner`**

In `Bashteroids/Systems/Spawner.swift`, find:

```swift
            let kinds: [PowerUpKind] = [.shield, .dualCanon, .boost]
```

becomes:

```swift
            let kinds: [PowerUpKind] = [.shield, .dualCanon, .boost, .minelayer]
```

- [ ] **Step 2: Add `.minelayer` to the BATTLE roulette**

Same file, in `updateBattlePowerUps`, find:

```swift
        let kinds: [(PowerUpKind, Int)] = [(.shield, 3), (.dualCanon, 1), (.boost, 1)]
```

becomes:

```swift
        let kinds: [(PowerUpKind, Int)] = [
            (.shield, 3),
            (.dualCanon, 1),
            (.boost, 1),
            (.minelayer, 1),
        ]
```

The CGFloat-threshold loop already handles arbitrary weights; no change needed there.

- [ ] **Step 3: Replace the placeholder `.minelayer` arm in `Collision.swift`**

In `Bashteroids/Systems/Collision.swift`, find the placeholder added in Task 4 Step 5:

```swift
                    case .minelayer: break // Wired in Task 6.
```

Replace with:

```swift
                    case .minelayer:
                        if !ship.minelayerArmed && ship.laidMine == nil {
                            ship.minelayerArmed = true
                        }
                        // else: already has one armed/placed — pickup is consumed but no-op.
```

- [ ] **Step 4: Add `handleMinelayerAction(ship:)` to GameScene and consume the input edge**

In `Bashteroids/Scenes/GameScene.swift`, find `applyInputs()`. Inside the per-slot loop, find the existing `if input.firePressedThisFrame { … }` block. Immediately after that block (still inside the per-slot loop body), add:

```swift
            if input.minelayerActionPressedThisFrame {
                handleMinelayerAction(ship: ship)
            }
```

Then add the helper near the other private gameplay helpers (e.g., near `nearestShip(to:)`):

```swift
    private func handleMinelayerAction(ship: Ship) {
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
```

- [ ] **Step 5: Add `Shift+4` minelayer shortcut to `GameScene+Debug.swift`**

In `Bashteroids/Scenes/GameScene+Debug.swift`, find the existing shift-key block:

```swift
        if shift {
            switch code {
            case .one:   debugSpawnPowerUp(.shield)
            case .two:   debugSpawnPowerUp(.dualCanon)
            case .three: debugSpawnPowerUp(.boost)
            default: break
            }
```

becomes:

```swift
        if shift {
            switch code {
            case .one:   debugSpawnPowerUp(.shield)
            case .two:   debugSpawnPowerUp(.dualCanon)
            case .three: debugSpawnPowerUp(.boost)
            case .four:  debugSpawnPowerUp(.minelayer)
            default: break
            }
```

Also update the comment block at the top of the file:

```swift
// Shift+number drops a power-up that drifts inward from a random edge:
//   Shift+1 = shield, Shift+2 = dual-canon, Shift+3 = boost
```

becomes:

```swift
// Shift+number drops a power-up that drifts inward from a random edge:
//   Shift+1 = shield, Shift+2 = dual-canon, Shift+3 = boost, Shift+4 = minelayer
```

- [ ] **Step 6: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero new warnings.

- [ ] **Step 7: Commit**

```bash
git add Bashteroids/Systems/Spawner.swift \
        Bashteroids/Systems/Collision.swift \
        Bashteroids/Scenes/GameScene.swift \
        Bashteroids/Scenes/GameScene+Debug.swift
git commit -m "feat(minelayer): pickup, place, detonate

Roulette in both modes can now drop a minelayer powerup.
Pickup arms the ship (no stacking — second pickup is a no-op).
Pressing buttonY / M while armed places a mine at the ship's
current position with a 60s timer; pressing again detonates the
placed mine. The reapDead branch handles the blast normally,
applying the new Section-2 zoning (inner 60 px kills, outer
60–140 px consumes shield or kills). Adds Shift+4 debug
shortcut."
```

---

## Task 7: README updates

Documents the four improvements.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add Minelayer row to the Power-ups table**

After the existing `Boost` row, insert:

```markdown
| **Minelayer**  | Spiked-circle silhouette           | Arms the ship to place one mine. Press **Y** (controller) or **M** (keyboard) to drop it at the ship's current position; press again to detonate it from anywhere. The placed mine also self-detonates after 60 s. The placing player is in the blast like anyone else. One-shot — pickup is consumed by the place/detonate cycle. Not available on Siri Remote (no spare button). |
```

- [ ] **Step 2: Update the Mine row in the Entities table**

Find the existing Mine row (currently mentions a 120 px radius). Replace with:

```markdown
| **Mine**   | none      | 1 bullet (or auto) | Drops at a random interior point with no warning, flashes for 6 s, then explodes in a 140 px radius. Two zones: a **60 px inner kill zone** (shields don't save you) and a **60–140 px outer blast** (consumes a shield, kills if no shield). Player-laid mines (via the Minelayer powerup) follow the same zoning but auto-detonate after 60 s instead of 6 s, and can be remote-detonated by the placing player. Joins from level 4. | 5 (blast) |
```

- [ ] **Step 3: Update the Controls table to include the minelayer key**

Add a row to the Controls table after the existing Fire row:

```markdown
| Minelayer | Y button *(needs minelayer pickup)* | M *(needs minelayer pickup)* |
```

- [ ] **Step 4: Mention top-10 highscores in the Levels section's leaderboard sentence**

Find:

```markdown
Between levels the game shows a `LEVEL N` banner; ships flash for ≈1 s before play resumes, and ship-vs-ship collisions are disabled during the transition. The highest level reached is shown next to your name on the title-screen leaderboard.
```

becomes:

```markdown
Between levels the game shows a `LEVEL N` banner; ships flash for ≈1 s before play resumes, and ship-vs-ship collisions are disabled during the transition. The highest level reached is shown next to your name on the title-screen leaderboard, which keeps your top 10 runs.
```

- [ ] **Step 5: Update the cheat list**

Find:

```markdown
  - `Shift+1` shield · `Shift+2` dual-canon · `Shift+3` boost
```

becomes:

```markdown
  - `Shift+1` shield · `Shift+2` dual-canon · `Shift+3` boost · `Shift+4` minelayer
```

- [ ] **Step 6: Mention BATTLE TTL in the Modes section's Battle bullet**

Find the BATTLE bullet (added in the previous spec) and append a clause about TTL. Look for the existing text describing BATTLE powerup drip; replace the part that reads `powerups drip every 30-60s` to:

```markdown
powerups drip every 30-60s and vanish after 30s with a 5s fade if uncollected
```

(Adjust phrasing to match the surrounding sentence; the goal is to communicate "uncollected powerups don't sit around forever in BATTLE".)

- [ ] **Step 7: Final smoke build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero new warnings.

- [ ] **Step 8: Commit**

```bash
git add README.md
git commit -m "docs(readme): document improvements pack

Top-10 leaderboard, mine damage zoning (60/140 split),
minelayer powerup with Y/M trigger, and BATTLE powerup TTL."
```

---

## Manual verification (after all tasks land)

The headless build can't exercise gameplay. Run the Mac Catalyst app and confirm:

1. Title screen shows up to 10 highscore rows.
2. In-game pickup of `>>` boost works (existing behavior, sanity check).
3. Survival mode: dropping a mine via Shift+3 (debug) and flying near it confirms the zoning — flying through the center kills a shielded ship; clipping the edge consumes a shield.
4. Minelayer pickup: marker appears on the ship near the rear. Press Y/M → mine drops at ship position, marker disappears, place mine appears in arena. Press Y/M again → mine detonates immediately (does the explosion expand correctly? does it apply the new zoning?). Wait 60 s without re-pressing → mine auto-detonates.
5. BATTLE mode (2+ players): a powerup that goes uncollected fades out at the 25 s mark and disappears at 30 s.
