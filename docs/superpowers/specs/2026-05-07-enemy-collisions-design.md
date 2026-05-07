# Enemy-vs-Enemy Collisions — Design

Date: 2026-05-07

## Goal

Snakes, alien monsters, UFOs, and asteroids currently pass through each other freely. Add a new collision pass so they damage each other on contact, matching the bullet damage model. From `improvements.md`: "enemies hitting asteroids or each other should also suffer hits".

## Damage model

Each enemy already has an effective HP via existing fields:

| Entity | HP | Hit handler |
| --- | --- | --- |
| Asteroid | 1 | `alive = false` |
| UFO | 1 | `alive = false` |
| Alien monster | 2 (`hitsRemaining`) | `registerBulletHit()` |
| Snake | 4 (`hitsRemaining`) | `registerBulletHit()` |

Each collision deals **1 hit** to both participants. The existing `registerBulletHit()` flash-and-decrement logic is reused — the "bullet" framing is just an internal API name.

## Pair table

| Pair | Test | On hit |
| --- | --- | --- |
| Asteroid ↔ UFO | circle-overlap | both die |
| Asteroid ↔ Alien | circle-overlap | asteroid dies, alien `registerBulletHit()` |
| Asteroid ↔ Snake | `snake.hitTest(point: asteroid.position, radius: asteroid.radius)` | asteroid dies, snake `registerBulletHit()` |
| UFO ↔ UFO | circle-overlap (inner pairs) | both die |
| UFO ↔ Alien | circle-overlap | UFO dies, alien `registerBulletHit()` |
| UFO ↔ Snake | `snake.hitTest(...)` against UFO | UFO dies, snake `registerBulletHit()` |
| Alien ↔ Alien | circle-overlap (inner pairs) | both `registerBulletHit()` |
| Alien ↔ Snake | `snake.hitTest(...)` against alien | both `registerBulletHit()` |
| Snake ↔ Snake | `snake.hitTest(...)` against other snake's head | both `registerBulletHit()` |

**Skipped:** Asteroid-vs-asteroid (intentional — would chain-react and clear the level too easily). Rocks already destroy everything they touch (unchanged).

## Score

Enemy-vs-enemy kills award **0 points**. The score model awards only to bullet owners — no ship was involved, so no credit.

## Continuous-contact behavior

Multi-HP pairs (alien-vs-alien, alien-vs-snake, snake-vs-snake) can overlap continuously across multiple frames. Each frame deducts 1 hp from each. Worst case: two snakes head-on take 4 frames (~67 ms at 60 fps) to mutually destruct. Visually reads as "they fly into each other and explode" — acceptable. No per-pair cooldown bookkeeping.

## Visual on contact

Each enemy-vs-enemy collision emits a small `Explosion.burst(at: midpoint, radius: 8, color: .white, parent: parent)` at the midpoint between the two participants — a debris spark that's visible whether the hit is lethal or not. The existing `registerBulletHit()` alpha flash on the entity remains; this spark is in addition (helps players see the contact point during chaotic frames).

To draw the spark, `Collision.resolve(...)` gains a `parent: SKNode? = nil` parameter that the GameScene supplies as `self`. When `parent` is nil (no caller passes one), the spark is silently skipped.

## Implementation

A new pass in `Collision.resolve(...)`, inserted **after the rock pass and before the ship pass**. Stateless. Follows the existing per-loop structure (`for x in xs where x.alive`).

For pairs of the same type (UFO-vs-UFO, alien-vs-alien, snake-vs-snake), inner-loop indexing (`for j in (i+1)..<count`) avoids double-counting.

## Files affected

- Modify: `Bashteroids/Systems/Collision.swift` (new enemy-vs-enemy pass)

No new files. No deletions. No API changes.

## Out of scope

- Score for enemy-vs-enemy kills (deferred — no ship credit).
- Asteroid-vs-asteroid collisions.
- Per-pair cooldown to slow continuous-contact damage.
- Visual / audio changes (uses existing `registerBulletHit()` flash + reapDead explosions).
- Mine-explosion damage to other enemies (already handled in `reapDead`).
