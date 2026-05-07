# BATTLE Wall Redesign — Design

Date: 2026-05-07

## Goal

Replace the current round, asteroid-shaped BATTLE walls with elongated, hand-drawn-looking polyline walls. Each wall is a chain of polygon segments that may bend along its length. Strong (impenetrable, warm gray) and weak (destructible, warm orange) properties move from the wall level to the **segment** level so a single wall can mix solid sections and tear-down sections.

## Non-goals

- New collision physics. The existing `BattleArena.reflectShipsOffWalls` and `Collision` bullet-vs-wall pipeline are chunk-agnostic and continue to work as-is.
- New wall behaviors (moving walls, regenerating walls, etc).
- Survival-mode wall presence. Walls remain BATTLE-only.
- Per-wall strength labels (`strong` / `weak` walls). Strength now lives on chunks; walls are inherently mixed.

## Architecture summary

A `Wall` is unchanged at the public surface — same `Entity` conformance, same broad-phase bounding circle, same `chunks: [Chunk]` exposure to the collision pipeline. Internals change:

- The `WallStrength` enum no longer applies to the whole wall. It moves to a new `Chunk.strength` field.
- The per-wall `Wall.strength` property is removed.
- `Wall.makeWeakWedges(...)` (radial wedge splitter) is removed.
- A new `Wall.makeSegmentChain(...)` helper constructs the chunk array as a polyline of N rough quadrilaterals.
- `Shapes.wallVertices(...)` (circular-polygon helper) is removed — no longer used.
- `BattleArena` constants resize for the new wall scale; `generate(...)` rewrites for the new placement model. `LevelRoster.battleConfig` simplifies.

## Section 1 — Wall geometry

A wall is a chain of N convex quadrilateral segments placed along a meandering polyline.

### Per-wall random parameters (drawn at generation)

| Parameter | Range | Purpose |
| --- | --- | --- |
| Initial heading | `[0, 2π)` | overall wall direction; free rotation |
| Bend amplitude `α` | `[0, 0.6 rad]` (~0–35°) | per-step rotation jitter |
| Strength bias `β` | `[0, 1]` | per-segment probability of being strong |
| Segment count `N` | `[3, 6]` | wall length in segments |

### Per-segment dimensions

| Constant | Value |
| --- | --- |
| `segmentLength` | 50 px (along the local long axis) |
| `segmentThickness` | 30 px (perpendicular short axis) |
| `segmentCornerJitter` | ±5 px (per-corner, both axes) |

### Generation algorithm

```
1. Pick the wall's starting position (rejection-sampled — see Section 3).
2. Draw α, β, N from the ranges above.
3. Pick an initial heading θ ∈ [0, 2π).
4. Walk N steps:
     a. Place a segment along the current heading θ. The segment's four
        corners are at:
            forward-left  = cursor + perp * (thickness/2) + jitter
            forward-right = cursor - perp * (thickness/2) + jitter
            back-left     = cursor + step + perp * (thickness/2) + jitter
            back-right    = cursor + step - perp * (thickness/2) + jitter
        where `step = direction(θ) * segmentLength` and `perp` is the
        right-hand perpendicular of `step`. Each "+jitter" applies an
        independent ±5 px offset on x and y.
     b. Roll strong with probability β; otherwise weak (5 hp).
     c. Advance the cursor by `step`.
     d. Rotate θ by a uniform random Δ ∈ [-α, +α].
5. Return the chunk array.
```

The polyline traces from the wall's starting corner outward. Adjacent segments share their dividing edge (forward-left → forward-right of segment i becomes back-left → back-right of segment i+1) but each segment owns its own SKShapeNode and is an independent convex polygon for collision math.

### Visuals

Strong segments: stroke `SKColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)` — same warm gray as today's strong walls.

Weak segments: stroke `SKColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1)` — same warm orange as today's weak walls.

Visible seams between adjacent strong/weak segments are intentional — they make the mix obvious to players and lend a "rough hand-drawn wall" character.

## Section 2 — Collisions, erosion, reflection

The collision pipeline is **chunk-agnostic**. No changes to `Collision.resolve` or `BattleArena.reflectShipsOffWalls` are needed; both iterate `wall.chunks` and call existing helpers.

### Bullet ↔ wall (existing logic, behavior preserved)

- Broad-phase: `wall.radius` bounding circle.
- Per-chunk: `Wall.pointInPolygon` test on each live chunk's vertices.
- Hit handling:
  - Strong chunk: bullet dies; chunk hp unchanged (hp = `Int.max`).
  - Weak chunk: bullet dies; `chunk.hp -= 1`; if `hp > 0` call `Wall.erodeChunk` (vertex pull-in + alpha dim); if `hp ≤ 0` remove the chunk's SKShapeNode.
  - Wall stays `alive == true` as long as **any** chunk (strong or weak) is alive. A wall with all-strong chunks never dies. A wall with all-weak chunks dies when all 3-6 weak chunks are destroyed.

### Ship ↔ wall (existing logic, behavior preserved)

`BattleArena.reflectIfNeeded` runs SAT against every live chunk's edges. Strong and weak chunks are equally solid for ships; reflection physics applies (50% speed reduction on the normal component, push-out by penetration depth + ε).

### Edge case: shared interior edges

When two adjacent chunks both live, their shared dividing edge is interior to the wall. The SAT's "outward normal" math runs per chunk, so the shared edge appears as an outward-facing edge of *each* of the two chunks. A ship moving along the wall's outside surface picks the actual outer edge as the deepest-penetration axis (correct). A ship that's somehow inside the wall (e.g., spawned overlapping it) gets pushed out via the closest-edge SAT and may briefly traverse one chunk's interior before exiting — recovers within a couple of frames. Not a player-visible issue in normal play.

### Erosion

`Wall.erodeChunk` works unchanged on the new 4-vertex quads. Vertex pull-in toward the chunk's local centroid still works geometrically. Alpha dim per hp still works.

## Section 3 — Generation tuning + LevelRoster

### `BattleArena` constants

```swift
enum BattleArena {
    static let edgeMargin: CGFloat = 80
    static let interWallMargin: CGFloat = 60       // was 80
    static let segmentLength: CGFloat = 50
    static let segmentThickness: CGFloat = 30
    static let segmentCornerJitter: CGFloat = 5
    static let segmentCountRange: ClosedRange<Int> = 3...6
    static let bendAmplitudeRange: ClosedRange<CGFloat> = 0...0.6
    static let strengthBiasRange: ClosedRange<CGFloat> = 0...1
    static let mazeClusterGap: CGFloat = 100        // was 120
    static let placementTries = 50
}
```

Removed: `strongRadiusRange`, `weakRadiusRange` (single-polygon size knobs), and the `scale = 1 + (level - 1) * 0.05` multiplier.

### `LevelRoster.battleConfig`

```swift
struct BattleConfig {
    let walls: Int          // total wall count
    let mazeClusters: Int   // walls placed in offset pairs (perpendicular to primary's heading)
}
```

| Level | walls | mazeClusters |
| --- | --- | --- |
| 1 | 3 | 0 |
| 2 | 4 | 0 |
| 3 | 5 | 0 |
| 4 | 5 | 1 |
| 5 | 6 | 1 |
| 6 | 7 | 1 |
| 7 | 8 | 2 |
| 8 | 9 | 2 |
| 9 | 10 | 3 |

Old `BattleConfig.strong` / `BattleConfig.weak` removed — strength is per-chunk now.

### Wall placement

Each wall's bounding circle for placement: `radius = N * segmentLength / 2 + segmentThickness / 2 + ε` — conservative estimate that ignores bend (a bent wall still fits within this circle as long as α stays inside `[0, 0.6]`). `pickOpenSpot` and `overlapsAny` use this radius unchanged.

### Maze cluster placement

Currently maze clusters place a partner wall in a cardinal direction `mazeClusterGap` away from the primary. With elongated walls, the partner is offset **perpendicular to the primary's heading** by `mazeClusterGap`, creating parallel walls that form a corridor. The partner's heading copies the primary's (also free rotation, but parallel to the primary). The bend amplitude / strength bias / segment count are drawn fresh per partner.

If the partner can't be placed (off-bounds or collides), the cluster degrades to a single-wall placement (existing fallback).

## Section 4 — Files affected

### Modified

**`Bashteroids/Entities/Wall.swift`:**
- Remove `Wall.strength: WallStrength` field. Walls don't have a global strength.
- Remove `Wall.makeWeakWedges(...)` static helper.
- Remove `Wall.polygonCentroid(...)` static helper if no longer used.
- Add `var strength: WallStrength` field to `Chunk` struct (replaces the wall-level `strength`). `Chunk.alive` stays as `hp > 0`. Strong chunks have `hp = Int.max`; weak chunks have `hp = Wall.weakChunkHP` (5).
- Add `Wall.makeSegmentChain(startPosition: CGPoint, heading: CGFloat, segmentCount: Int, bendAmplitude: CGFloat, strengthBias: CGFloat, parent: SKNode, rng: inout SeededGenerator) -> [Chunk]` — implements the Section 1 algorithm.
- Replace `Wall.init(strength:centerPosition:radius:seed:)` with `Wall.init(centerPosition: CGPoint, heading: CGFloat, segmentCount: Int, bendAmplitude: CGFloat, strengthBias: CGFloat, seed: UInt64)`. The wall constructs its chunks from these parameters via `makeSegmentChain`. The `radius` is no longer a constructor input — it's computed inside `init` from the constructor parameters as `CGFloat(segmentCount) * BattleArena.segmentLength / 2 + BattleArena.segmentThickness / 2 + epsilon` (matches the placement estimate; intentionally over-conservative on bent walls). Stored as `let radius` on the Wall.
- Color resolution in `wallChunk(...)` calls changes from `wall.strength`-derived to `chunk.strength`-derived.

**`Bashteroids/Render/Shapes.swift`:**
- Remove `wallVertices(radius:seed:count:)`. The new wall doesn't use circular polygons.
- Keep `wallChunk(vertices:color:)` — still used unchanged.

**`Bashteroids/Systems/BattleArena.swift`:**
- Replace the size-related constants with the Section 3 set.
- Rewrite `generate(in:level:seed:)` per Section 1 + Section 3.
- Update cluster partner placement to use perpendicular-to-heading offsets rather than cardinal.
- `reflectShipsOffWalls` and `reflectIfNeeded` unchanged.
- `pickOpenSpot` / `overlapsAny` / `rectInsetByEdge` unchanged.

**`Bashteroids/Systems/LevelRoster.swift`:**
- `BattleConfig` field rename: `strong` + `weak` → `walls`.
- `battleConfig(for:)` switch table updated to the Section 3 numbers.

### Unchanged

- `Bashteroids/Systems/Collision.swift` — bullet-vs-wall pipeline is chunk-agnostic.
- `Bashteroids/Scenes/GameScene.swift` — wall lifecycle (generate, render, reap) unchanged.
- `Bashteroids/Entities/Ship.swift`, `Bashteroids/Entities/PowerUp.swift`, `Bashteroids/Entities/Mine.swift` — none touched.
- `README.md` — gets a small update to the wall description in the implementation plan's docs task.

### No new files. No deletions.

## Risks and open questions

- **Maze cluster geometry on bent walls.** A primary wall that bends 35° per step ends with a different heading than it started. The partner placement uses the primary's *initial* heading (the property stored on Wall). The partner is parallel to the start, not the end. For walls that bend a lot, the partner may not feel like a true corridor. Acceptable: corridors are a soft hint, not a strict guarantee.
- **Concave chunks.** The corner jitter (±5 px) is bounded such that no 4-vertex quad becomes concave or self-intersecting (the worst case is jitter pushing the back-left point past the back-right point in x — won't happen with 5 px jitter on a 50 px segment). Mathematically guaranteed by `2 * segmentCornerJitter < segmentLength`.
- **Closer wall packing.** `interWallMargin` drops from 80 to 60 px. With the larger walls, this should preserve flying corridors comparable to the old layout. Subject to playtest.
- **Bounding-circle conservatism.** Using `N * segmentLength / 2 + segmentThickness / 2` for placement overestimates the actual wall radius on highly bent walls (which curl back on themselves and have a smaller true bounding circle). Consequence: placements are a bit more conservative than necessary. Trade-off accepted.
- **Bend doubling back.** A wall with α = 0.6 that turns the same direction 6 times in a row could nearly self-intersect. Mathematically: 6 × 0.6 = 3.6 rad ≈ 206°. Practically: the random walk averages near 0, so consistent same-direction turns are rare. If observed in playtest, clamp the cumulative bend to π/2 from the initial heading.

## Out of scope (revisited)

- Moving walls
- Walls that regenerate
- Survival-mode walls
- Per-wall scoring (e.g., points for destroying)
- Wall-vs-wall placement that adapts to other entities (powerups, ships)
