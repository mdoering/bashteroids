# BATTLE Mode v2 — Design

Date: 2026-05-07

## Goal

Four interrelated BATTLE-mode improvements from `improvements.md`:

1. **HP system + energy bar** — ships have 10 HP (was 1-hit-kill); a top-of-screen energy bar shows remaining HP per player with green/orange/red zones.
2. **Static asteroids** — non-moving asteroids inside the arena.
3. **More centered walls** — push wall placement away from the perimeter so the borders are clean ricochet space.
4. **Bouncing borders** — ships reflect off the arena's outer rectangle instead of screen-wrapping.

## 1. HP system (universal, capped)

Universal `Ship.hp: Int` field. Default 1 (survival behavior). BATTLE overrides to `Ship.maxBattleHP = 10` at spawn time.

`Collision.hitShip(_:, damage:)` becomes shield-aware multi-damage:

```swift
private static func hitShip(_ ship: Ship, damage: Int = 1) -> Bool {
    var remaining = damage
    while remaining > 0 && ship.shieldCount > 0 {
        ship.shieldCount -= 1
        remaining -= 1
    }
    if remaining > 0 {
        ship.hp -= remaining
        if ship.hp <= 0 {
            ship.alive = false
            return false
        }
    }
    return true
}
```

### Damage values

| Source | Damage | Where applied |
| --- | --- | --- |
| Bullet hit | 1 | existing bullet-vs-ship arm in `Collision.resolve` |
| Ship-vs-ship contact | 1 each | existing ship-vs-ship arm; both ships call `hitShip(_:damage: 1)` |
| Static asteroid contact | 1 | existing ship-vs-asteroid arm; asteroid also dies |
| Mine outer blast (60–140 px) | 1 | `reapDead` mine block (currently consumes 1 shield or kills; now `hitShip(damage: 1)`) |
| Mine inner kill (≤ 60 px) | 5 | `reapDead` mine block; bypasses the shield-first logic via `damage: 5` |
| Wall bounce | 0 | unchanged — pure reflection |
| Bullet vs wall | 0 to ship | unchanged — bullet dies on the wall |

The same code path serves survival and BATTLE — survival ships have 1 HP so any damage > 0 still kills outright (matching today).

## 2. Energy bar HUD

Each player's HUD region (existing per-segment label) gains a horizontal **energy bar** below the name label. In BATTLE mode only.

### Bar geometry

- Width: 80 px max
- Height: 6 px
- Stroke: 1 px white outline (always visible — empty bar still readable)
- Fill: rect proportional to `hp / maxHP`, colored by hp threshold:
  - **Green** `(0.40, 0.85, 0.40)` when hp > 50%
  - **Orange** `(1.00, 0.70, 0.20)` when 25% < hp ≤ 50%
  - **Red** `(0.95, 0.30, 0.30)` when 0 < hp ≤ 25%
- Position: `~6 px` below the label, centered on the player's HUD segment center

### Label text in BATTLE

- Living ship: just `<NAME>` in player color (drop the "ALIVE" suffix — bar conveys it)
- Dead ship: `✕ <NAME>` gray (unchanged from current)

### Implementation

`GameScene.buildHUD()` constructs the bar nodes (one outline `SKShapeNode` + one fill `SKShapeNode` per player). `updateHUD()` updates fill width and fill color each frame.

## 3. Static asteroids in BATTLE

Reuse the existing `Asteroid` entity with `velocity = .zero`. They're targets for bullets (1 hp = 1 score) AND collidable obstacles for ships (ship loses 1 hp, asteroid dies).

### Per-level count (`LevelRoster.battleConfig`)

`BattleConfig` gains a `staticAsteroids: Int` field. Linear scale L1=0 → L9=8:

| Level | walls | mazeClusters | staticAsteroids |
| --- | --- | --- | --- |
| 1 | 3 | 0 | 0 |
| 2 | 4 | 0 | 1 |
| 3 | 5 | 0 | 2 |
| 4 | 5 | 1 | 3 |
| 5 | 6 | 1 | 4 |
| 6 | 7 | 1 | 5 |
| 7 | 8 | 2 | 6 |
| 8 | 9 | 2 | 7 |
| 9 | 10 | 3 | 8 |

### Generator

New `BattleArena.generateStaticAsteroids(in: bounds, count: Int, walls: [Wall], rng: inout SeededGenerator) -> [(position: CGPoint, radius: CGFloat, seed: UInt64)]`. Uses the existing `pickOpenSpot` (which already considers walls); each asteroid uses radius 18–32 (matching the existing spawner's range). Ship-spawn perimeter spots are chosen AFTER asteroids are placed so ships don't spawn on top of them.

### Score

Bullet-vs-asteroid kill awards `Score.asteroid = 1` to the firing ship — same as survival. Encourages clearing static asteroids in BATTLE.

## 4. More centered walls

`BattleArena.edgeMargin: CGFloat = 80 → 200`. Walls are constrained to an inner rectangle 200 px from each edge, leaving the perimeter clean for ship maneuvering and ricochets. Ship spawn positions (perimeter ellipse at 8% inset) and static asteroid placement still use their own logic.

## 5. Bouncing borders

In BATTLE only, ships reflect off the play-bounds rectangle instead of screen-wrapping.

### `Movement.stepBouncing`

```swift
static func stepBouncing<E: Entity>(_ entities: [E], dt: TimeInterval,
                                    bounds: CGRect, energyLoss: CGFloat = 0.5) {
    for e in entities where e.alive {
        e.position.x += e.velocity.x * CGFloat(dt)
        e.position.y += e.velocity.y * CGFloat(dt)
        if e.position.x - e.radius < bounds.minX {
            e.position.x = bounds.minX + e.radius
            e.velocity.x = -e.velocity.x * energyLoss
        }
        if e.position.x + e.radius > bounds.maxX {
            e.position.x = bounds.maxX - e.radius
            e.velocity.x = -e.velocity.x * energyLoss
        }
        if e.position.y - e.radius < bounds.minY {
            e.position.y = bounds.minY + e.radius
            e.velocity.y = -e.velocity.y * energyLoss
        }
        if e.position.y + e.radius > bounds.maxY {
            e.position.y = bounds.maxY - e.radius
            e.velocity.y = -e.velocity.y * energyLoss
        }
    }
}
```

Uses 50% energy loss to match wall-bounce physics. Ship's `position` property is settable via `Entity` extension (already used in `BattleArena.reflectIfNeeded`).

### Wiring in `GameScene.update`

Replace the existing ship movement step in BATTLE with the bouncing variant:

```swift
if mode == .battle {
    Movement.stepBouncing(ships, dt: dt, bounds: bounds)
} else {
    Movement.stepWrapping(ships, dt: dt, bounds: bounds)
}
```

Static asteroids have `velocity = .zero` so any movement step is a no-op for them; they need no bounce logic.

Bullets and powerups are unchanged — bullets still die at the edge, BATTLE powerups stay where placed (zero velocity).

## Files affected

- Modify: `Bashteroids/Entities/Ship.swift` — add `hp` field and `maxBattleHP`
- Modify: `Bashteroids/Systems/Collision.swift` — hitShip with damage; mine inner-zone uses damage 5
- Modify: `Bashteroids/Systems/Movement.swift` — new `stepBouncing` helper
- Modify: `Bashteroids/Systems/BattleArena.swift` — `edgeMargin` 80→200; new `generateStaticAsteroids`
- Modify: `Bashteroids/Systems/LevelRoster.swift` — `BattleConfig.staticAsteroids`; switch table updated
- Modify: `Bashteroids/Scenes/GameScene.swift` — set `ship.hp = maxBattleHP` for BATTLE; static asteroid generation; energy bar HUD; `stepBouncing` ships in BATTLE

No new files. No deletions.

## Edge cases

- **Solo BATTLE round.** Spec already requires ≥ 2 players to start BATTLE. Solo path unreachable.
- **Mine inner kill of a 10-HP ship at full health, no shield.** 5 damage → hp 10 → 5. Ship survives. Spec says "5 hp damage if flown into" — that's the *damage value*, not "must die". Player at full HP survives. Acceptable; differs from survival where 5 damage = death (1 hp). User said BATTLE should be more forgiving; this matches.
- **Static asteroid spawn collision with a wall.** `pickOpenSpot` already enforces wall margins; same logic protects static asteroid placement.
- **Ship spawning on top of a static asteroid.** Adjust `spawnShipsForBattle` to also avoid asteroid positions when placing ship spawn (just iterate jitter angles further).
- **Ricochet stuck against corner.** A ship moving into a corner reflects on both axes the same frame — could create a chatter. Mitigated by the energy-loss factor: each bounce scrubs 50% of that-axis velocity, so the ship dies down quickly.

## Out of scope

- Bouncing bullets (bullets keep dying at the border).
- Bouncing asteroid debris (static asteroids don't move; no dynamic ones in BATTLE).
- HP regen (no healing — once damaged, you're damaged for the round).
- Energy-bar shake / hit flash (could add later as visual polish).
- Per-player HP HUD on tvOS overlay (uses the same scene HUD; no overlay needed).
