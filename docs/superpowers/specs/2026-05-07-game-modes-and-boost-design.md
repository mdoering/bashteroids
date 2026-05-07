# Game Modes, Boost Powerup, and Level Selector — Design

Date: 2026-05-07

## Goal

Three intertwined gameplay changes:

1. **Game-mode selector** on the title screen: `SURVIVAL` (existing) or `BATTLE` (new last-ship-standing deathmatch with destructible arena walls). Survival is the default.
2. **Brake / boost rework:** every ship can brake from spawn (drop the `hasBrakes` powerup gate). The brakes powerup is replaced by a **boost** powerup that raises the ship's max velocity. Base max speed is lowered to 140 px/s; first boost = 200, second boost = 250.
3. **Level selector** on the title screen (1–9), defaulting to the last level the player reached.

Ships in two phases: Phase 1 = quick refactors + selectors + plumbing. Phase 2 = BATTLE arena.

## Non-goals

- Score recording / leaderboards in BATTLE mode (different game, different metric).
- Per-player mode/level overrides (selection is global per round).
- BATTLE mode with 1 player (selector is disabled until ≥2 players have joined).
- Multi-round / "best of 3" tournament structure in BATTLE — each press of "start" is one round.
- Network play (still strictly local couch co-op).

## Architecture summary

Single Xcode target unchanged. New work breaks into:

1. **Title-screen selector UI** (Section 1) — a compact mode + level row above the player slots.
2. **Brake / boost rework** (Section 2) — ship physics, powerup kind rename, ship marker swap.
3. **Level selector + persistence** (Section 3) — `GameSettings` UserDefaults wrapper.
4. **`GameMode` plumbing** (Section 4) — enum + `GameScene` parameterization. Phase 1's BATTLE branch is a `// TODO(phase2)` no-op.
5. **BATTLE arena** (Section 5) — `Wall` entity with chunks, `BattleArena` generator, ship-reflection physics, bullet absorb / chunk erosion.
6. **BATTLE round flow** (Section 6) — ship placement, powerup drip, win condition, eliminated-ship rendering, `GameOverScene` branch.

Existing folder layout (`App/`, `Scenes/`, `Entities/`, `Systems/`, `Input/`, `Audio/`, `Render/`, `Utils/`) is preserved.

## Section 1 — Title-screen layout

A new compact selector bar lives between the title text and the player slots:

```
                      < SURVIVAL >    < L 4 >
                       MODE             LEVEL
```

- **Mode:** `SURVIVAL` / `BATTLE`. D-pad left/right cycles. Keyboard: `M`. Wraps.
- **Level:** 1–9. D-pad up/down cycles. Keyboard: arrow up / arrow down. Wraps at 1↔9.
- **BATTLE disabled with fewer than 2 joined players** — text dims to gray and the selector ignores attempts to set it. A small hint shows under the selector: `BATTLE NEEDS 2+ PLAYERS`. (The mode silently snaps back to `SURVIVAL` if a player drops below 2 after BATTLE was selected.)
- **Selection is global** (not per-player). Any joined controller can change it. Last-changed value wins.
- Selectors are disabled while a player is in name-entry (existing inline editor on iPad/Mac, SwiftUI overlay on tvOS).
- **Persisted to UserDefaults** between launches via `GameSettings`.
- The DEBUG-only `[DEBUG] START LEVEL: N` indicator and the corresponding 0–9 keyboard shortcut in `TitleScene` are removed (the always-visible level selector replaces them).

## Section 2 — Brake / boost rework

### Physics in `Ship.swift`

| Constant | Old | New |
| --- | --- | --- |
| `maxSpeed` | 280 | 140 |
| `boostedMaxSpeedL1` | — | 200 |
| `boostedMaxSpeedL2` | — | 250 |
| `brakeDeceleration` | 200 | 200 (unchanged) |

- The `hasBrakes: Bool` field and its `didSet` are deleted. The `braking` per-frame input flag is read by every ship; the `if braking && hasBrakes` guard in `update(dt:)` becomes `if braking`. Every ship can brake from spawn.
- New field `var boostLevel: Int = 0` (clamped 0...2). The velocity clamp in `update(dt:)` reads from a computed:
  ```swift
  var effectiveMaxSpeed: CGFloat {
      switch boostLevel {
      case 1:  return Self.boostedMaxSpeedL1
      case 2:  return Self.boostedMaxSpeedL2
      default: return Self.maxSpeed
      }
  }
  ```
- The `brakesMarker` `SKShapeNode` field is renamed `boostMarker`. Its `didSet` lights up when `boostLevel >= 1`; **no separate visual for `boostLevel == 2`** (the marker stays at the same alpha — that's a deliberate user-side decision).

### Powerup model

- `PowerUpKind`: rename case `.brakes` → `.boost`. `Shapes.powerUp(kind:)` gets a new orange double-chevron icon (`>>`) for `.boost`; the red downward triangle is deleted.
- The pickup handler in `Collision.swift` (whichever switch arm currently handles `.brakes`) becomes:
  ```swift
  case .boost:
      if ship.boostLevel < 2 { ship.boostLevel += 1 }
  ```
- `Spawner` powerup roulette: replace `.brakes` with `.boost`. Survival weighting unchanged (uniform across the three kinds today). BATTLE weighting is in Section 6.

### Ship-marker change

- `Ship.makeBrakesMarker()` → `Ship.makeBoostMarker()`. Geometry: two short orange chevrons at the rear (centered around `(-7, 0)`, pointing right toward `+x` so they read as "fast"). Same alpha-on-when-active behavior, driven by `boostLevel >= 1`.
- Color: `SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)` (matches the existing thrust-flame orange; keeps the ship palette tight).

### Documentation

- README "Power-ups" table: replace the `Brakes` row with `Boost` (orange chevron, +43% / +79% max velocity at L1 / L2, permanent for the run, stacks once).
- README "Controls" table: drop the *(needs brakes pickup)* qualifier on the Brake row.

## Section 3 — Level selector + persistence

### New file `Bashteroids/Utils/GameSettings.swift`

```swift
import Foundation

enum GameSettings {
    private static let levelKey = "bashteroids.lastPlayedLevel"
    private static let modeKey  = "bashteroids.lastMode"

    static var lastPlayedLevel: Int {
        get {
            let raw = UserDefaults.standard.integer(forKey: levelKey)
            return raw == 0 ? 1 : max(1, min(9, raw))
        }
        set { UserDefaults.standard.set(max(1, min(9, newValue)), forKey: levelKey) }
    }

    static var lastMode: GameMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey),
                  let mode = GameMode(rawValue: raw) else { return .survival }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }
}
```

`UserDefaults.standard.integer(forKey:)` returns 0 for absent keys, which acts as the "first launch ever" sentinel — defaults to level 1.

### TitleScene wiring

- New private `@MainActor` fields: `selectedLevel: Int`, `selectedMode: GameMode`, both seeded from `GameSettings` in `didMove(to:)`.
- New input handlers:
  - D-pad left/right (any controller, any time selectors are enabled): cycle mode (with the BATTLE-needs-2-players guard).
  - D-pad up/down: bump level (1↔9 wrap).
  - Keyboard: `M` cycles mode; arrow up/down bumps level.
- `tryStart()` becomes:
  ```swift
  guard !transitioning, !manager.slots.isEmpty, activeNameSlot == nil else { return }
  if selectedMode == .battle && manager.slots.count < 2 { return }
  GameSettings.lastPlayedLevel = selectedLevel
  GameSettings.lastMode = selectedMode
  let next = GameScene(size: size, level: selectedLevel, mode: selectedMode)
  ...
  ```

### GameScene parameterization

- `GameScene.init(size: CGSize, level: Int, mode: GameMode)` replaces the current bare `init(size:)`. `currentLevel` and `mode` are stored on the scene.
- The `#if DEBUG; currentLevel = max(1, DebugSettings.startLevel); #else; currentLevel = 1; #endif` block in `didMove(to:)` is deleted — the level comes from the initializer in both Debug and Release.
- `GameScene` writes `GameSettings.lastPlayedLevel = currentLevel` whenever `currentLevel` changes (a new helper called from the existing level-state-machine transition).

### Removals

- `Bashteroids/Utils/DebugSettings.swift` — delete `startLevel` if it has no other consumers; otherwise leave the file in place. (`grep -n` confirms `startLevel` is the only thing in there today; the whole file gets deleted.)

## Section 4 — `GameMode` model + GameScene parameterization

### New file `Bashteroids/Systems/GameMode.swift`

```swift
enum GameMode: String { case survival, battle }
```

### Phase-1 BATTLE branch

`GameScene.didMove(to:)` runs the existing survival-mode setup unchanged for both modes in Phase 1. A single comment marks the Phase-2 split:

```swift
addChild(hudLayer)
buildHUD()
updateHUD()

// TODO(phase2): if mode == .battle, generate walls + skip survival spawner.
spawner = Spawner(bounds: playBounds, glowParent: self)
spawner.mode = mode
```

`Spawner` gains `var mode: GameMode = .survival`. In Phase 1 it does nothing different. Phase 2 adds the actual BATTLE branches.

This means **selecting BATTLE in Phase 1 plays a survival round.** That's intentional — Phase 1 ships and is verifiable end-to-end (selectors work, persistence works, brake/boost rework works) before Phase 2 introduces walls.

## Section 5 — BATTLE arena: walls, geometry, collisions (Phase 2)

### Entity model

New file `Bashteroids/Entities/Wall.swift`:

```swift
enum WallStrength { case strong, weak }

final class Wall: Entity {
    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat                    // bounding circle for broad-phase
    var alive: Bool = true
    let strength: WallStrength
    private(set) var chunks: [Chunk]
}

struct Chunk {
    var vertices: [CGPoint]                // wall-local
    var hp: Int                            // 5 for weak, .max for strong
    let originalVertices: [CGPoint]        // for erosion math
    let shape: SKShapeNode                 // owned by Wall.node
    var alive: Bool { hp > 0 }
}
```

A `Wall` owns 1+ chunks. Strong walls are single-chunk with `hp = .max` and a **warm-gray** outline (`SKColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)`). Weak walls own 4 chunks with `hp = 5` each, **warm-orange** outline (`SKColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1)`).

### Generator

New file `Bashteroids/Systems/BattleArena.swift`:

```swift
enum BattleArena {
    static func generate(in bounds: CGRect, level: Int, seed: UInt64) -> [Wall]
}
```

Algorithm:

1. Look up `LevelRoster.battleConfig(for: level)` → `(strongCount, weakCount, mazeClusters)`.
2. **Strong walls first** via Poisson-disc sampling (each candidate position must be ≥ `2 * maxWallRadius + 80 px` from any existing wall and the play-area edge). If sampling fails after N tries, accept the closest-to-spec point.
3. **Weak walls** via the same sampling, but `mazeClusters` of them are placed in a short line/L-shape (2–3 walls in a row with `~120 px` gaps) instead of fully random — that creates the partial-corridor feel.
4. Each wall's shape is a hollow `Shapes.asteroid`-style irregular polygon. Strong walls: radius `35–55 px`. Weak walls: radius `25–40 px`. Both scaled `× 1 + (level - 1) * 0.05` so L9 walls are ~40% bigger than L1.
5. Weak-wall chunks are constructed by splitting the wall's polygon into 4 radial wedges from its centroid (each wedge spans ~90° of the perimeter, with a 4 px inner gap between adjacent wedges so chunks read as distinct from the start). Wedge polygons are convex by construction, which keeps the ship-vs-wall closest-edge test well-defined.
6. Walls leave `≥ 80 px` clearance from the play-area bounds and from each other.

### `LevelRoster` additions

```swift
struct BattleConfig {
    let strong: Int
    let weak: Int
    let mazeClusters: Int
}

extension LevelRoster {
    static func battleConfig(for level: Int) -> BattleConfig {
        let l = max(1, min(9, level))
        switch l {
        case 1: return BattleConfig(strong: 4,  weak: 0, mazeClusters: 0)
        case 2: return BattleConfig(strong: 5,  weak: 1, mazeClusters: 0)
        case 3: return BattleConfig(strong: 6,  weak: 2, mazeClusters: 0)
        case 4: return BattleConfig(strong: 6,  weak: 3, mazeClusters: 1)
        case 5: return BattleConfig(strong: 7,  weak: 4, mazeClusters: 1)
        case 6: return BattleConfig(strong: 8,  weak: 4, mazeClusters: 1)
        case 7: return BattleConfig(strong: 9,  weak: 5, mazeClusters: 2)
        case 8: return BattleConfig(strong: 10, weak: 6, mazeClusters: 2)
        case 9: return BattleConfig(strong: 12, weak: 6, mazeClusters: 3)
        default: return BattleConfig(strong: 4, weak: 0, mazeClusters: 0)
        }
    }
}
```

### Visual erosion of weak chunks

On bullet hit (chunk-only):

- `chunk.hp -= 1`.
- If `hp > 0`:
  - Pick 1–2 vertices of the chunk via a chunk-local `SeededGenerator(seed: chunkIndex * 31 + hp)` and pull them toward the chunk's centroid by `8–14%` of their distance to the centroid. (Deterministic so the pattern doesn't shimmer.)
  - Update `chunk.shape.path` from the new vertices.
  - Set `chunk.shape.alpha = 0.5 + 0.1 * CGFloat(hp)` (so 1.0 at full hp, 0.5 at hp=0+1).
- If `hp == 0`:
  - `chunk.shape.removeFromParent()`.
  - Mark `chunk.alive = false`.
  - If `wall.chunks.allSatisfy { !$0.alive }`, set `wall.alive = false` and remove it from the scene's wall list.

### Collisions in `Systems/Collision.swift`

- **Bullet ↔ wall (chunk-by-chunk):** if a bullet's position is inside any live chunk's polygon (point-in-polygon test on the chunk vertices), the bullet dies (`bullet.alive = false`). For weak chunks, also call the erosion handler above. For strong chunks, no further state change.

- **Ship ↔ wall (chunk-by-chunk):** for each live chunk whose bounding-circle test passes, find the closest edge segment to the ship's position. If the perpendicular distance from the ship to the segment is `≤ ship.radius` AND the ship is on the inside-relative-to-the-edge side of the segment:
  ```swift
  let n = perpendicular outward-pointing normal of the segment
  let vn = velocity • n
  if vn < 0 {
      ship.velocity = (ship.velocity - 2 * vn * n) * 0.5
      // push outside by penetration depth
      let penetration = ship.radius - perpendicularDistance
      ship.position += n * (penetration + 0.5)
  }
  ```
  The push-out prevents the ship from sticking inside the wall on the next frame. Ship does not take damage and shields are not consumed. Weak walls do not take damage from a ship-bounce — only bullets erode them.

- **Other entity ↔ wall:** N/A — no asteroids/UFOs/snakes/etc spawn in BATTLE mode (the survival spawner is skipped).

Broad-phase order each frame:
1. Each ship and each bullet against each wall's bounding circle.
2. Walls that pass: against each chunk's bounding circle.
3. Chunks that pass: edge-segment / point-in-polygon math.

Wall count caps at ~16 per arena, chunks at ≤ 4 per weak wall, so the worst-case N for the inner test is small (≤ 16 walls × 4 chunks × 4 ships × edges/chunk).

## Section 6 — BATTLE round flow

### Ship placement at round start

After walls are generated, `spawnShipsForJoinedPlayers(in:)` is overridden in BATTLE: each ship is placed at one of N evenly-spaced points around an inset perimeter ellipse (8% inset from `playBounds`), with rejection sampling to ensure ≥ 60 px clearance from any wall. Headings face roughly toward the arena center plus a small random jitter (±0.3 rad).

### Powerup drip

`Spawner` gains:

```swift
private var nextBattlePowerUpTime: TimeInterval?

mutating func scheduleBattlePowerUp(at currentTime: TimeInterval) {
    nextBattlePowerUpTime = currentTime + .random(in: 30...60)
}

mutating func updateBattlePowerUps(currentTime: TimeInterval, bounds: CGRect, walls: [Wall]) -> PowerUp? {
    guard let due = nextBattlePowerUpTime, currentTime >= due else { return nil }
    let kind = Self.weightedRandomBattleKind()  // 60% shield, 20% dualCanon, 20% boost
    let pos = Self.randomOpenSpot(in: bounds, walls: walls)
    nextBattlePowerUpTime = currentTime + .random(in: 30...60)
    return PowerUp(kind: kind, position: pos, velocity: .zero)
}
```

`randomOpenSpot` rejection-samples points until one is ≥ 40 px from every wall chunk and ≥ 80 px from any ship; gives up after 30 tries and returns the best candidate so far (last-resort).

Powerups in BATTLE have **zero velocity** (they sit and wait, no drift). Powerup spawning continues until the round ends.

Initial schedule call happens in `GameScene.didMove(to:)` for the BATTLE branch.

### Win condition

In `GameScene.update(_:)` BATTLE branch:

```swift
let aliveShips = ships.filter { $0.alive }
if !roundEnding {
    switch aliveShips.count {
    case 0: endRound(result: .draw)
    case 1: endRound(result: .winner(aliveShips[0]))
    default: break
    }
}
```

`endRound` sets a 1.5 s pause flag; after the pause, `view?.presentScene(GameOverScene(size:, mode: .battle, result: ...))`.

### Eliminated ships

When a ship dies in BATTLE:

- `ship.alive = false`.
- The existing ship `node.removeFromParent()` is replaced with a swap-to-debris: the ship's outline turns dark gray (`alpha 0.4`) and stays at the death position for the rest of the round. (No movement, no collision.)
- The HUD label for that player gains an `✕` prefix and dims to gray.

### HUD changes for BATTLE

Per-player HUD label format:
- Survival (unchanged): `<NAME>  <SCORE>`
- BATTLE: `<NAME>  ALIVE` (color = player color) → on death → `✕ <NAME>` (gray).

### `GameOverScene` changes

`GameOverScene.init(size:, mode: GameMode, result: GameResult)` where:

```swift
enum GameResult {
    case survivalScore(level: Int)              // existing path
    case battleWinner(playerIndex: Int, color: SKColor, name: String)
    case battleDraw
}
```

Layout:
- `.survivalScore`: existing layout (per-player score + level reached).
- `.battleWinner`: large `<NAME> WINS` banner in the player's color, the ship icon below, "Press START for title".
- `.battleDraw`: large `DRAW` banner in white, two crossed ship outlines below.

### Highscore handling

`HighScore.record(...)` is **only called for survival**. BATTLE rounds are not recorded — survival's leaderboard stays survival-only.

### `lastPlayedLevel` write

`GameScene` writes `GameSettings.lastPlayedLevel = currentLevel` at the start of each level transition (existing state machine hook). Works in both modes (in BATTLE there's only one "level" per round, the one selected on the title; the write happens once on round start).

## Section 7 — File summary

### New files
- `Bashteroids/Systems/GameMode.swift` — `GameMode` enum
- `Bashteroids/Utils/GameSettings.swift` — UserDefaults wrapper
- `Bashteroids/Entities/Wall.swift` — wall + chunk model
- `Bashteroids/Systems/BattleArena.swift` — wall generation + reflection helpers

### Modified files
- `Bashteroids/Entities/Ship.swift` — drop `hasBrakes`; add `boostLevel`; `maxSpeed` 280→140 + boosted-1 200 + boosted-2 250; `brakesMarker` → `boostMarker`
- `Bashteroids/Entities/PowerUp.swift` — `.brakes` → `.boost`
- `Bashteroids/Render/Shapes.swift` — replace red brake icon with orange chevron; new wall-outline helpers
- `Bashteroids/Systems/Collision.swift` — boost handler; ship-vs-wall reflection; bullet-vs-wall absorb / chunk erosion
- `Bashteroids/Systems/Spawner.swift` — `mode` field; BATTLE powerup drip; skip enemy spawning in BATTLE
- `Bashteroids/Systems/LevelRoster.swift` — add `BattleConfig` + `battleConfig(for:)`
- `Bashteroids/Scenes/GameScene.swift` — new initializer `init(size:level:mode:)`; mode-dispatched setup; ship-vs-wall step; BATTLE win-condition check
- `Bashteroids/Scenes/GameScene+Debug.swift` — drop the start-level branch; entity spawn cheats become no-ops in BATTLE
- `Bashteroids/Scenes/TitleScene.swift` — selectors, input handling, `tryStart()` updated, `[DEBUG] START LEVEL` removed
- `Bashteroids/Scenes/GameOverScene.swift` — branch on `mode` for the result banner
- `README.md` — Power-ups table (Brakes → Boost), Controls table (drop "needs brakes pickup"), add Modes section, update level-select description

### Deleted files
- `Bashteroids/Utils/DebugSettings.swift` — `startLevel` is the only field; the file goes when superseded

## Plan phasing

**Phase 1** (ships first; survival plays differently, BATTLE selector exists but plays a survival round):
- Section 2 — brake / boost rework
- Section 3 — level selector + persistence
- Section 4 — `GameMode` plumbing + `GameScene` parameterization
- Section 1 — title-selector UI fully wired (BATTLE branch in Section 4 is the `// TODO(phase2)` no-op)

**Phase 2** (BATTLE arena on top of Phase 1):
- Section 5 — Wall + BattleArena
- Section 6 — BATTLE round flow + `GameOverScene` branch
- Replace the `// TODO(phase2)` with the real BATTLE setup

Each phase ends with a green build on iOS + Mac Catalyst + tvOS (per CLAUDE.md "Build verification") and a clean run-through of survival mode at the very least.

## Risks and open questions

- **Ship-vs-wall reflection precision.** Edge-segment math on irregular polygons can mis-fire at sharp concave corners. Mitigation: chunks are convex by construction (radial wedges of the polygon), so the closest-edge test is well-defined.
- **BATTLE powerup placement on dense L9 arenas.** With 12 strong + 6 weak walls + maze clusters, the open-spot rejection sampler may fail. Acceptable failure mode: drop the powerup at the last-best candidate even if it's closer than 40 px from a wall (still reachable). If a powerup ends up unreachable, players just don't pick it up — not a crash.
- **Eliminated-ship debris cluttering tight arenas.** Worst case 4 ships, 3 dead → 3 debris nodes plus 12+ walls. Should be fine visually; revisit if it feels noisy in playtest.
- **Selector input collision with name entry.** The selectors are gated on `activeNameSlot == nil` (and the tvOS overlay being absent) so D-pad inputs during name entry don't sneak through. Already the case for other title inputs.

## Out of scope (revisited)
- Network play
- BATTLE leaderboards / ranked play
- Weapon variants exclusive to BATTLE (e.g. mines as a player-droppable weapon)
- "Last hit" credit / kill-counter HUD in BATTLE — last-ship-standing only
- Multi-round series in BATTLE
