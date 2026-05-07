# Improvements Pack — Design

Date: 2026-05-07

## Goal

Four small gameplay tweaks driven by `improvements.md`:

1. **Highscores expanded from 3 to 10** entries.
2. **Mine damage zoning** — direct hit kills, outskirts consume a shield. Slight blast-radius bump.
3. **Minelayer powerup** — players can place and remote-detonate a single mine; auto-explodes after 60 s.
4. **BATTLE powerup TTL** — uncollected powerups vanish after 30 s with a 5 s fade.

All four are independent; they share one spec because each is too small for its own document but they touch overlapping files (`Mine.swift`, `Ship.swift`, `PowerUp.swift`, `Spawner.swift`, `GameScene.swift`).

## Non-goals

- Adding a real ship HP system. Mine zoning is implemented entirely with the existing shield-count model (Section 2).
- Per-mine ownership tracking for kill credit. Player-laid mines award kills to the nearest ship at detonation, same as spawner-placed mines.
- Friendly-fire exemption for player-laid mines. The placing player is in the blast like anyone else.
- BATTLE powerup TTL changes for survival mode. Survival keeps its current drift-and-stay behavior.

## Section 1 — Top-10 highscores

### Change

`Bashteroids/Utils/HighScore.swift`:
```swift
static let maxEntries = 10   // was 3
```

### Title-screen layout

`TitleScene` already iterates `HighScore.top.enumerated()`; with `maxEntries = 10` it naturally renders up to 10 rows.

Geometry sanity:
- Heading at `y = leaderboardTopY` (= screen top minus 80).
- Rows at `y = leaderboardTopY - 24 * (i + 1)` for `i` in 0..9.
- Last row sits at `leaderboardTopY - 240`.
- Title-screen mode/level selectors live at `y = size.height * 0.58`.
- On a typical 16:10 layout (e.g., 2360 × 1640 = iPad Pro 12.9", landscape: 2732 × 2048 → playable area ~size.height ≈ 1638 in points), `0.58 * 1638 ≈ 950` and `leaderboardTopY ≈ 1638 - 80 = 1558`, last row at 1318. Plenty of clearance.

Existing 14 pt font / 24 px row gap stays.

### Persistence

`HighScore.record` already trims to `maxEntries`. Existing data is unchanged — the next 7 saved scores fill in the new slots.

## Section 2 — Mine damage zoning

### Two-zone explosion

`Bashteroids/Entities/Mine.swift`:
```swift
static let innerKillRadius: CGFloat = 60
static let explosionRadius: CGFloat = 140   // was 120
```

### Damage rules in `GameScene.reapDead` (mine `exploded` branch)

For each ship within `explosionRadius`:
- If distance ≤ `innerKillRadius`: ship dies regardless of shield count.
- Else (60 < d ≤ 140): consume 1 shield if `shieldCount > 0`; otherwise ship dies.

For UFOs / aliens: still die at any distance ≤ `explosionRadius` (the radius bump from 120 → 140 applies to them too — minor but consistent).

For powerups within `explosionRadius`: consumed (current behavior unchanged; just a wider area now).

### Visuals

`Explosion.burst(...)` is called with `radius: Mine.explosionRadius` so the visible blast matches the new outer.

### Score awarding

Unchanged. `nearestShip(to: dead.position)?.score += 5` per blast.

### Documentation

README "Entities" Mine row gets the two-zone description.

## Section 3 — Minelayer powerup

### New PowerUpKind

`Bashteroids/Entities/PowerUp.swift`:
```swift
enum PowerUpKind { case shield, dualCanon, boost, minelayer }
```

### Ship state

`Bashteroids/Entities/Ship.swift`:
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

`laidMine` is `weak` so it auto-clears when the mine entity is reaped.

### Pickup handler

`Bashteroids/Systems/Collision.swift`:
```swift
case .minelayer:
    if !ship.minelayerArmed && ship.laidMine == nil {
        ship.minelayerArmed = true
    }
    // else: pickup is consumed but does nothing (no stacking)
```

### Visuals

- **Powerup icon (`Shapes.minelayerPowerUp()`):** small spiked-circle silhouette resembling a mine. Gray stroke `(0.7, 0.7, 0.7, 1)`, 6 spikes at 6 px length, central circle radius 6, lineWidth 1.5. Visually distinct from the existing four icons.
- **Ship marker (`Ship.makeMinelayerMarker()`):** tiny mine silhouette on the ship near the rear (offset around `(-8, 0)`), single SKShapeNode. Alpha 1 when armed, 0 otherwise.

### Input

| Input | Trigger |
| --- | --- |
| MFi controller `buttonY` | place / detonate |
| Keyboard `M` | place / detonate (in-game only) |
| Siri Remote | not supported (no spare button) |

`PlayerInput` (in `PlayerSlot.swift`) gains a `minelayerActionPressedThisFrame: Bool` field, edge-triggered like the existing `firePressedThisFrame`.

`PlayerSlot.installFireHandler`/`removeFireHandler` add a `buttonY.pressedChangedHandler` that sets a private edge flag, consumed by `snapshot()`.

`KeyboardInputState` adds `minelayerEdge` that's set by a new `keyM` case in the keyboard listener (mirroring how `spaceDown()` works for fire).

### Action handler

In `GameScene.applyInputs`, after the existing fire handling, per ship:
```swift
if input.minelayerActionPressedThisFrame {
    handleMinelayerAction(ship: ship)
}
```

```swift
private func handleMinelayerAction(ship: Ship) {
    if ship.minelayerArmed && ship.laidMine == nil {
        // Place
        let mine = Mine(position: ship.position, lifetimeOverride: 60)
        mines.append(mine)
        addChild(mine.node)
        ship.minelayerArmed = false
        ship.laidMine = mine
    } else if let live = ship.laidMine, live.alive {
        // Detonate
        live.alive = false
        live.exploded = true
        // ship.laidMine clears automatically (weak ref) once reapDead runs.
    }
}
```

### Mine lifetime override

`Bashteroids/Entities/Mine.swift`:
```swift
private let effectiveLifetime: TimeInterval

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
    let period = max(0.2, Double(1.5 - t * 1.3))   // clamp lower bound
    flashPhase += dt
    flashPhase = flashPhase.truncatingRemainder(dividingBy: period)
    node.alpha = flashPhase < period / 2 ? 1.0 : 0.15
}
```

The `max(0.2, ...)` clamp prevents the flash period from approaching zero on a 60 s mine (the original 1.5 - t * 1.3 would go negative).

The `Mine` initializer keeps a no-arg-override default for the spawner, which calls `Mine(position: ...)` unchanged.

### Spawner integration

`Bashteroids/Systems/Spawner.swift`:
- The survival powerup roulette gains `.minelayer`:
  ```swift
  let kinds: [PowerUpKind] = [.shield, .dualCanon, .boost, .minelayer]
  ```
- The BATTLE powerup roulette gains `.minelayer` with weight 1 (matching boost / dualCanon):
  ```swift
  let kinds: [(PowerUpKind, Int)] = [
      (.shield, 3),
      (.dualCanon, 1),
      (.boost, 1),
      (.minelayer, 1),
  ]
  ```
  Total weight 6; distribution = 50/16.7/16.7/16.7. Spec section 6 of the prior plan says BATTLE should weight shields more heavily; the 50% share preserves that intent.

### Self-damage

A player-laid mine detonating with the placing player inside the blast applies the same Section 2 zoning to that player. No friendly-fire exemption.

### Score awarding

Unchanged: nearest ship at detonation gets +5. Player-laid mines usually mean the placing player is nearby — natural credit without owner tracking.

### Debug

`Bashteroids/Scenes/GameScene+Debug.swift` — extend the powerup cheat list:
```
Shift+1 = shield, Shift+2 = dual-canon, Shift+3 = boost, Shift+4 = minelayer
```

## Section 4 — BATTLE powerup TTL

### `PowerUp` gains an optional lifetime

`Bashteroids/Entities/PowerUp.swift`:
```swift
var lifetime: TimeInterval?
private var age: TimeInterval = 0

func update(dt: TimeInterval) {
    guard let life = lifetime else { return }
    age += dt
    let remaining = life - age
    if remaining <= 0 {
        alive = false
        return
    }
    if remaining < 5 {
        node.alpha = max(0, remaining / 5)
    }
}
```

Survival mode does not set `lifetime`, so `update` is a no-op for survival powerups (current behavior preserved).

### Plumbing through the Spawn pipeline

`Bashteroids/Systems/Spawner.swift`:
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

Existing call sites for `.powerUp(kind:speed:)` (in `Spawner.makeSpawn`) become `.powerUp(kind: kind, speed: speed, lifetime: nil)`.

`Spawner.updateBattlePowerUps` constructs:
```swift
return Spawn(kind: .powerUp(kind: chosen, speed: 0, lifetime: 30),
             position: position,
             velocity: .zero,
             side: .top)
```

`GameScene.spawn(_:)`'s `.powerUp` case reads the new `lifetime`:
```swift
case .powerUp(let kind, _, let lifetime):
    let pu = PowerUp(kind: kind, position: s.position, velocity: s.velocity)
    pu.lifetime = lifetime
    powerUps.append(pu)
    addChild(pu.node)
```

### Visual decay

The `node.alpha = max(0, remaining / 5)` line gives a smooth linear fade from full to invisible over the last 5 s.

### Reap

`reapDead()` already removes any `powerUp` with `alive == false` — no change needed.

## Files modified / created

**Modified:**
- `Bashteroids/Utils/HighScore.swift` — `maxEntries` 3 → 10.
- `Bashteroids/Entities/Mine.swift` — `innerKillRadius`, `explosionRadius` 120 → 140, `lifetimeOverride` init param, period clamp.
- `Bashteroids/Entities/Ship.swift` — `minelayerArmed`, `laidMine`, `minelayerMarker` field; `makeMinelayerMarker()` helper; init wiring.
- `Bashteroids/Entities/PowerUp.swift` — `.minelayer` case, `lifetime` field, `update(dt:)` body.
- `Bashteroids/Render/Shapes.swift` — `minelayerPowerUp()` helper, dispatcher arm in `powerUp(kind:)`, `Ship.makeMinelayerMarker()` (or define it on Ship — see source).
- `Bashteroids/Systems/Collision.swift` — `.minelayer` pickup arm; mine zoning in the explosion branch.
- `Bashteroids/Systems/Spawner.swift` — `SpawnKind.powerUp` lifetime field; survival kinds `+ .minelayer`; BATTLE kinds `+ (.minelayer, 1)`.
- `Bashteroids/Input/PlayerSlot.swift` — `PlayerInput.minelayerActionPressedThisFrame`; `installFireHandler` / `removeFireHandler` extended with `buttonY`; snapshot consumes the edge.
- `Bashteroids/Input/KeyboardInputState.swift` — `minelayerEdge` flag and `mPressed()` setter.
- `Bashteroids/Input/KeyboardManager.swift` — `keyM` case forwards to `KeyboardInputState`.
- `Bashteroids/Scenes/GameScene.swift` — `handleMinelayerAction(ship:)`; per-frame consumption in `applyInputs`; mine zoning in the existing `reapDead` branch; `.powerUp` spawn case reads `lifetime`.
- `Bashteroids/Scenes/GameScene+Debug.swift` — `Shift+4` minelayer cheat.
- `README.md` — Power-ups table gets a Minelayer row; Entities table Mine row updated; brief mention of high-score top-10.

**No new files.**

**No deletions.**

## Risks and open questions

- **Mine zoning for non-ship entities.** The plan keeps UFOs / aliens dying at any distance ≤ outer radius. If at high levels the new 140 radius cleans up too many enemies, that's a balance tweak in playtest, not a code concern.
- **Player-laid mine kill credit.** Awarded to nearest ship at detonation. If the placing player throws a mine into an asteroid cluster and a teammate is closer than they are, the teammate gets credit. Acceptable simplification.
- **`buttonY` on Mac Catalyst gamepads.** All major MFi pads have it. PlayStation / Xbox / Switch Pro all expose it via the GameController framework.
- **`M` key collision with title-screen mode toggle.** Title scene handles `M` only when the user is on the title; the in-game scene's `KeyboardManager.onKeyDown` handler is a different scope (set in `GameScene.didMove`). No conflict.
- **30 s + 5 s fade in BATTLE.** Powerup spawns can stack visually if multiple drip without being collected. The 30 s vanishing prevents long-term clutter; the BATTLE drip cadence (30–60 s) means at most ~2 powerups on screen at peak. Acceptable density.

## Out of scope (revisited)

- Real ship HP system
- Per-mine owner tracking
- Survival-mode powerup TTL
- Friendly-fire exemptions
- New entity types (just a new powerup kind, not a new entity class)
