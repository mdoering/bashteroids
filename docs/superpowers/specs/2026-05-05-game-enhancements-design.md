# Bashteroids Game Enhancements — Design Spec
_2026-05-05_

## Overview

Ten additions to the existing Bashteroids SpriteKit game, grouped into seven areas. All new entities follow the existing Ship/UFO/Asteroid pattern (class + position/velocity/alive + SKNode + update(dt:)). No new abstractions introduced.

---

## 1. Player Names

### Storage
`UserDefaults`, keys `"player_name_0"` … `"player_name_3"`. Default value `"P1"` … `"P4"` when unset. Persists across launches, keyed by slot index.

### Entry flow
1. Player presses **A** (controller) → slot tile appears, `joinEnabled = false` immediately, slot enters *name-input mode* (cursor `_` appends to displayed name)
2. Player types on physical keyboard: printable chars append (max 8 chars, auto-uppercased), Backspace deletes last char
3. Player presses **Return/Enter** (keyboard) → name written to `UserDefaults`, cursor removed, `joinEnabled = true`
4. If nothing was typed, the previous or default name is kept unchanged
5. While name-input mode is active no other controller can join
6. Pressing A on an already-confirmed slot re-enters name-input mode (blocks joining again until Return)

### Display
- Slot tile in `TitleScene` gains a second `SKLabelNode` below the ship sprite showing the current name, `fontSize 14`, player color
- In name-input mode the label text is `currentInput + "_"` (blinking via `SKAction.repeatForever(.sequence([.fadeOut, .fadeIn]))`)
- HUD score label in `GameScene` changes from `"P1  42"` to `"MARKUS  42"` using the stored name

---

## 2. Solo Mode

Mechanically already supported: `tryStart()` allows 1 slot; `checkEndCondition()` handles `initialShipCount == 1` → `finish(winner: nil)` → "GAME OVER" screen.

**Only change:** `buildHUD()` renders labels for `manager.slots.count` active slots only (not always 4), repositioning them to fill the HUD bar evenly. Inactive player labels are not shown.

---

## 3. Difficulty Scaling

All scaling is driven by `Spawner.elapsed`. Purely additive changes inside `Spawner`.

### Asteroid speed
- Min speed: `60 + elapsed/180 * 50` pt/s, capped at 110
- Max speed: `120 + elapsed/180 * 80` pt/s, capped at 200

### Asteroid size
- After 120s, mean radius shrinks from 25 → 18 pt (harder targets)

### New enemy eligibility
- **Mines** eligible after 60s; `rollMine()` chance grows from 0% → 20% over the next 60s
- **Alien monsters** eligible after 120s; `rollAlien()` chance grows from 0% → 25% over the next 60s
- Each decision cycle independently rolls: UFO → mine → alien → asteroid (asteroid is default fallback)

---

## 4. Visual Changes

### Laser bullets
- `Shapes.bullet(color:heading:)` gains a `heading: CGFloat` parameter
- Draws a `CGPath` line segment of length **~6 pt** centred on the bullet position, oriented along `heading`
- Line width 1.5, `strokeColor = color`, `fillColor = .clear`
- `Bullet` stores `heading: CGFloat` (computed from velocity angle at creation)
- Player bullets use their ship color; enemy bullets use white

### Asteroid interior circle
- `Shapes.asteroid(radius:seed:vertexCount:)` adds a child `SKShapeNode(circleOfRadius: radius * 0.38)`
- `strokeColor = SKColor(white: 0.35, alpha: 1)`, `fillColor = .clear`, `lineWidth = 1`

---

## 5. Power-ups

### Entity
New `PowerUp` class. Straight-line motion at 50–90 pt/s, no screen-wrapping (`Movement.stepBounded` removes it when it leaves). Spawned from screen edges like asteroids.

```
enum PowerUpKind { case shield, dualCanon }
```

### Visuals
- **Shield** — hexagon outline, cyan (`#00FFFF`), radius ~14 pt
- **Dual-canon** — two short parallel horizontal lines in yellow (~16 pt wide, 4 pt apart)

### Pickup collision
Circle overlap, radius 14 pt, checked in `Collision.resolve`. On pickup: power-up `alive = false`; ship gains effect.

### Shield effect (`Ship`)
- New property `hasShield: Bool`
- When `true`: dim ring child node (`SKShapeNode(circleOfRadius: collisionRadius + 6)`, white, alpha 0.4) attached to ship node
- Next collision that would kill the ship consumes the shield instead — ship survives, ring removed, `hasShield = false`

### Dual-canon effect (`Ship`)
- New properties `hasDualCanon: Bool`, `canonAlternate: Bool`
- `reloadInterval` drops to `0.667s` (1.5× rate)
- `fire()` spawns bullet offset `±4 pt` perpendicular to heading (i.e. `CGPoint.fromAngle(heading ± .pi/2, length: 4)`), alternating sides via `canonAlternate`

### Stacking
Both effects can be active simultaneously. Picking up a duplicate power-up while already active is silently ignored.

### Spawning
`Spawner` rolls a 15% chance for a power-up each decision cycle (eligible after 30s), resolved before the asteroid/UFO/mine/alien roll. Power-ups enter from a screen edge with an inward velocity, same edge-entry path as asteroids. Edge-glow warning in white.

---

## 6. New Enemies

### Space Mine
- Spawned at a random position within the play area (not from an edge), zero velocity
- Visual: `SKShapeNode` circle (radius ~14 pt) with 6 short spike lines radiating outward
- Lifetime: **6 seconds**. Flash pulse period starts at 1.5s and linearly accelerates to 0.2s; implemented as a repeating `SKAction` sequence that updates `strokeColor` alpha
- On expiry: `Explosion.burst` with radius ~120 pt; any ship, UFO, or alien monster whose `position` is within that radius is marked `alive = false`. Asteroids are unaffected
- Scoring: 5 pts awarded to the nearest living ship at detonation time
- No edge-glow warning (appears silently). Because mines are stationary and interior, `Spawner` uses a separate code path for them: skips `entryPosition`/`inwardAngle`, picks a random point at least 80 pt from all screen edges, creates no glow node, and schedules them with the same `warningDuration` delay (the delay is just internal scheduling — nothing visible happens)

### Alien Monster
- Moves and wraps identically to UFO. `AlienMonster` duplicates UFO's `baseHeading`, `driftPhase`, `driftRate`, `driftAmplitude`, and `speed` state (no shared base class — consistent with the no-abstraction rule)
- Visual: UFO path extended with 4 downward triangular spike segments on the lower hull
- Fires short-range lasers: `Bullet` with `maxDistance: CGFloat? = 140 pt`; `Bullet` gains `private var distanceTravelled: CGFloat = 0`; `update(dt:)` accumulates `velocity.magnitude * dt` and sets `alive = false` when `distanceTravelled >= maxDistance`
- Only fires when nearest ship is within 200 pt
- Scores 10 pts on destruction

---

## 7. Controls

### L2 shooting
`PlayerSlot.installFireHandler` adds `gp.leftTrigger.pressedChangedHandler` alongside existing `buttonX` and `rightShoulder` handlers. One-line addition.

### X button to start
`TitleScene.update(_:)` polls `buttonX` with edge detection (new `xWasPressed: [ObjectIdentifier: Bool]` dict, mirrors existing `menuWasPressed`). Triggers `tryStart()` same as menu button.

---

## Files changed

| File | Change |
|------|--------|
| `Utils/HighScore.swift` | No change |
| `Render/Shapes.swift` | Laser bullet shape, asteroid inner circle, power-up shapes, mine shape, alien shape |
| `Entities/Bullet.swift` | Add `heading`, optional `maxDistance` |
| `Entities/Ship.swift` | Add `hasShield`, `hasDualCanon`, `canonAlternate`; update `fire()` and `reloadInterval` |
| `Entities/PowerUp.swift` | New file |
| `Entities/Mine.swift` | New file |
| `Entities/AlienMonster.swift` | New file |
| `Systems/Collision.swift` | Ship-vs-powerup, mine explosion radius, alien-vs-bullet |
| `Systems/Spawner.swift` | Speed scaling, size scaling, mine/alien rolls, power-up roll |
| `Systems/Movement.swift` | No change |
| `Input/PlayerSlot.swift` | L2 fire handler |
| `Input/ControllerManager.swift` | `playerName(at:)` helper; expose name-input blocking |
| `Scenes/TitleScene.swift` | Name entry flow, slot label, X-button start |
| `Scenes/GameScene.swift` | Power-up/mine/alien arrays, HUD name labels, mine detonation, scoring |
