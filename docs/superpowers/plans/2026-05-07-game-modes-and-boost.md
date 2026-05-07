# Game Modes, Boost Powerup, and Level Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a BATTLE deathmatch mode (selectable from the title), rework brakes into a stacking boost powerup, and expose a 1–9 level selector — all behind selectors persisted between launches.

**Architecture:** Two implementation phases. Phase 1 lands the title-screen selectors (mode + level), the brake/boost physics rework, and `GameMode` plumbing through `GameScene` — selecting BATTLE in Phase 1 plays a survival round. Phase 2 layers on the BATTLE arena (destructible vector walls, ship-bounce reflection, last-ship-standing rules, dedicated `GameOverScene` banners).

**Tech Stack:** Swift 5 + SpriteKit, single Xcode target, three destinations (iOS / Mac Catalyst / tvOS). Build verification per destination after every task per CLAUDE.md.

**Spec:** `docs/superpowers/specs/2026-05-07-game-modes-and-boost-design.md`

---

## File Structure

**New files (Phase 1):**
- `Bashteroids/Systems/GameMode.swift` — single-line enum, used everywhere a "mode" question is asked.
- `Bashteroids/Utils/GameSettings.swift` — UserDefaults wrapper for `lastPlayedLevel: Int` (1–9) and `lastMode: GameMode`.

**New files (Phase 2):**
- `Bashteroids/Entities/Wall.swift` — `Wall` + `Chunk` value type, polygon math, hp/erosion state.
- `Bashteroids/Systems/BattleArena.swift` — wall generator (Poisson-disc sampling + maze clusters) and the per-frame ship-vs-wall reflection helper.

**Modified files (Phase 1):**
- `Bashteroids/Entities/Ship.swift` — drop `hasBrakes`; add `boostLevel` + `effectiveMaxSpeed`; lower `maxSpeed`; rename marker.
- `Bashteroids/Entities/PowerUp.swift` — `.brakes` → `.boost` in `PowerUpKind`.
- `Bashteroids/Render/Shapes.swift` — replace red brake icon with orange chevron; later (Phase 2) add wall outline helpers.
- `Bashteroids/Systems/Collision.swift` — boost handler replaces brake handler.
- `Bashteroids/Systems/Spawner.swift` — `.brakes` → `.boost` in the powerup kinds array; `var mode: GameMode = .survival` field added (consumed in Phase 2).
- `Bashteroids/Scenes/GameScene.swift` — new initializer `init(size:level:mode:)`, drop `DebugSettings.startLevel` read, write `GameSettings.lastPlayedLevel` on every level transition.
- `Bashteroids/Scenes/GameScene+Debug.swift` — `.brakes` → `.boost` in spawn cheats.
- `Bashteroids/Scenes/TitleScene.swift` — mode + level selector UI and input handling, drop the `[DEBUG] START LEVEL` HUD and 0–9 keys, wire `tryStart()` to pass `level` and `mode` to `GameScene`.
- `Bashteroids/Utils/DebugSettings.swift` — file deleted (sole field `startLevel` is superseded).
- `README.md` — update Power-ups + Controls tables; add Modes section.

**Modified files (Phase 2):**
- `Bashteroids/Render/Shapes.swift` — wall outline + chunk wedge helpers.
- `Bashteroids/Systems/Collision.swift` — bullet-vs-wall absorb / chunk erosion; ship-vs-wall reflection (delegated to `BattleArena`).
- `Bashteroids/Systems/Spawner.swift` — `scheduleBattlePowerUp` / `updateBattlePowerUps`, and `mode == .battle` shortcut in `startLevel(_:)` to skip the survival queue.
- `Bashteroids/Systems/LevelRoster.swift` — `BattleConfig` + `battleConfig(for:)`.
- `Bashteroids/Scenes/GameScene.swift` — wall list field; mode-dispatched `didMove`; ship placement override in BATTLE; ship-vs-wall step in update loop; BATTLE win-condition check; eliminated-ship debris.
- `Bashteroids/Scenes/GameOverScene.swift` — new `Result` cases `.battleWinner` and `.battleDraw` with their own banners.
- `README.md` — add BATTLE section, document new wall mechanics.

---

## Phase 1

### Task 1: GameMode + GameSettings (foundation)

These two files have no callers yet. Land them first so later tasks can import them without forward references.

**Files:**
- Create: `Bashteroids/Systems/GameMode.swift`
- Create: `Bashteroids/Utils/GameSettings.swift`

- [ ] **Step 1: Create `GameMode.swift`**

```swift
enum GameMode: String { case survival, battle }
```

- [ ] **Step 2: Create `GameSettings.swift`**

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

`UserDefaults.integer(forKey:)` returns 0 for absent keys — that 0 acts as the "first launch" sentinel and we coerce to 1.

- [ ] **Step 3: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three end with `** BUILD SUCCEEDED **`. Zero new warnings.

- [ ] **Step 4: Commit**

```bash
git add Bashteroids/Systems/GameMode.swift Bashteroids/Utils/GameSettings.swift
git commit -m "feat: GameMode enum + GameSettings UserDefaults wrapper

Adds the survival/battle mode enum and a small UserDefaults
shim for lastPlayedLevel (1-9, defaulting to 1) and lastMode
(defaulting to .survival). No callers yet — foundation for the
title-screen selectors and the GameScene mode parameter."
```

---

### Task 2: Brake / boost physics rework

Drops the `hasBrakes` powerup gate, lowers `maxSpeed`, adds a stacking `boostLevel`, swaps the powerup kind name and ship marker.

**Files:**
- Modify: `Bashteroids/Entities/Ship.swift`
- Modify: `Bashteroids/Entities/PowerUp.swift`
- Modify: `Bashteroids/Render/Shapes.swift`
- Modify: `Bashteroids/Systems/Collision.swift`
- Modify: `Bashteroids/Systems/Spawner.swift`
- Modify: `Bashteroids/Scenes/GameScene+Debug.swift`

- [ ] **Step 1: Update `Ship.swift` constants and add boost field**

Replace the constants block at the top of the class (current lines 4–10):

```swift
final class Ship: Entity {
    static let thrustAccel: CGFloat = 220
    static let maxSpeed: CGFloat = 140
    static let boostedMaxSpeedL1: CGFloat = 200
    static let boostedMaxSpeedL2: CGFloat = 250
    static let turnRate: CGFloat = 4.0          // rad/s at full input
    static let reloadInterval: TimeInterval = 2.0
    static let maxShieldStack: Int = 2
    static let maxCanonLevel: Int = 2           // 0 = single, 1 = dual, 2 = quad
    static let maxBoostLevel: Int = 2           // 0 = base, 1 = +43%, 2 = +79%
    static let brakeDeceleration: CGFloat = 200 // px/s² when braking
```

- [ ] **Step 2: Replace `hasBrakes` field with `boostLevel`**

In `Ship.swift`, replace the field declaration block (current lines 59–64):

```swift
    var hasBrakes: Bool = false {
        didSet {
            guard hasBrakes != oldValue else { return }
            brakesMarker.alpha = hasBrakes ? 1 : 0
        }
    }
```

with:

```swift
    var boostLevel: Int = 0 {
        didSet {
            guard boostLevel != oldValue else { return }
            // No separate visual for L2; marker is on for any boostLevel >= 1.
            boostMarker.alpha = boostLevel >= 1 ? 1 : 0
        }
    }

    var effectiveMaxSpeed: CGFloat {
        switch boostLevel {
        case 1:  return Self.boostedMaxSpeedL1
        case 2:  return Self.boostedMaxSpeedL2
        default: return Self.maxSpeed
        }
    }
```

Also rename the `brakesMarker` field declaration (line 34):

```swift
    private let brakesMarker: SKShapeNode
```

becomes:

```swift
    private let boostMarker: SKShapeNode
```

- [ ] **Step 3: Update the `update(dt:)` method**

In `Ship.swift`, the thrust/brake block (lines 108–122) becomes:

```swift
        if thrusting {
            let push = CGPoint.fromAngle(heading, length: Self.thrustAccel * CGFloat(dt))
            velocity = (velocity + push).clampedMagnitude(to: effectiveMaxSpeed)
            thrustFlame.alpha = CGFloat.random(in: 0.6...1.0)
            thrustFlame.xScale = CGFloat.random(in: 0.85...1.15)
        } else {
            thrustFlame.alpha = 0
            if braking {
                let speed = velocity.length
                if speed > 0 {
                    let newSpeed = max(0, speed - Self.brakeDeceleration * CGFloat(dt))
                    velocity = velocity.normalized() * newSpeed
                }
            }
        }
```

Two changes vs. before: `Self.maxSpeed` → `effectiveMaxSpeed`, and `if braking && hasBrakes` → `if braking`.

- [ ] **Step 4: Update the marker init in `init(playerIndex:color:position:heading:)`**

In `Ship.swift`, the marker construction block (lines 95–98) becomes:

```swift
        let boost = Ship.makeBoostMarker()
        boost.alpha = 0
        n.addChild(boost)
        self.boostMarker = boost
```

- [ ] **Step 5: Replace `makeBrakesMarker()` with `makeBoostMarker()`**

In `Ship.swift`, replace the static helper (lines 202–211):

```swift
    private static func makeBrakesMarker() -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -8, y:  3)); path.addLine(to: CGPoint(x: -3, y:  3))
        path.move(to: CGPoint(x: -8, y: -3)); path.addLine(to: CGPoint(x: -3, y: -3))
        let n = SKShapeNode(path: path)
        n.strokeColor = SKColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1)
        n.fillColor   = .clear
        n.lineWidth   = 1
        return n
    }
```

with:

```swift
    private static func makeBoostMarker() -> SKShapeNode {
        // Two small chevrons pointing forward (+x): looks like ">>" trailing
        // the ship, evoking speed. Drawn at the rear of the silhouette.
        let path = CGMutablePath()
        path.move(to:    CGPoint(x: -10, y:  3))
        path.addLine(to: CGPoint(x:  -6, y:  0))
        path.addLine(to: CGPoint(x: -10, y: -3))
        path.move(to:    CGPoint(x:  -6, y:  3))
        path.addLine(to: CGPoint(x:  -2, y:  0))
        path.addLine(to: CGPoint(x:  -6, y: -3))
        let n = SKShapeNode(path: path)
        n.strokeColor = SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        n.fillColor   = .clear
        n.lineWidth   = 1.5
        n.lineJoin    = .miter
        return n
    }
```

- [ ] **Step 6: Rename `.brakes` to `.boost` in `PowerUp.swift`**

In `Bashteroids/Entities/PowerUp.swift`, replace line 3:

```swift
enum PowerUpKind { case shield, dualCanon, brakes }
```

with:

```swift
enum PowerUpKind { case shield, dualCanon, boost }
```

- [ ] **Step 7: Update the powerup pickup handler in `Collision.swift`**

In `Bashteroids/Systems/Collision.swift`, replace the switch (lines 151–155):

```swift
                    switch pu.kind {
                    case .shield:    ship.shieldCount = min(ship.shieldCount + 1, Ship.maxShieldStack)
                    case .dualCanon: ship.canonLevel  = min(ship.canonLevel + 1, Ship.maxCanonLevel)
                    case .brakes:    ship.hasBrakes   = true
                    }
```

with:

```swift
                    switch pu.kind {
                    case .shield:    ship.shieldCount = min(ship.shieldCount + 1, Ship.maxShieldStack)
                    case .dualCanon: ship.canonLevel  = min(ship.canonLevel + 1, Ship.maxCanonLevel)
                    case .boost:     ship.boostLevel  = min(ship.boostLevel + 1, Ship.maxBoostLevel)
                    }
```

- [ ] **Step 8: Replace the brake icon in `Shapes.swift`**

In `Bashteroids/Render/Shapes.swift`, replace `brakesPowerUp()` (lines 156–168) and update the dispatcher.

Replace `powerUp(kind:)` (lines 131–137):

```swift
    static func powerUp(kind: PowerUpKind) -> SKShapeNode {
        switch kind {
        case .shield:    return shieldPowerUp()
        case .dualCanon: return dualCanonPowerUp()
        case .brakes:    return brakesPowerUp()
        }
    }
```

with:

```swift
    static func powerUp(kind: PowerUpKind) -> SKShapeNode {
        switch kind {
        case .shield:    return shieldPowerUp()
        case .dualCanon: return dualCanonPowerUp()
        case .boost:     return boostPowerUp()
        }
    }
```

Then replace `brakesPowerUp()` with `boostPowerUp()`:

```swift
    private static func boostPowerUp() -> SKShapeNode {
        // Orange double chevron pointing right ">>" — evokes speed.
        let path = CGMutablePath()
        path.move(to:    CGPoint(x: -10, y:  6))
        path.addLine(to: CGPoint(x:  -2, y:  0))
        path.addLine(to: CGPoint(x: -10, y: -6))
        path.move(to:    CGPoint(x:   0, y:  6))
        path.addLine(to: CGPoint(x:   8, y:  0))
        path.addLine(to: CGPoint(x:   0, y: -6))
        let node = SKShapeNode(path: path)
        node.strokeColor = SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        node.fillColor   = .clear
        node.lineWidth   = 1.5
        node.lineJoin    = .miter
        node.isAntialiased = true
        return node
    }
```

- [ ] **Step 9: Update the powerup kinds array in `Spawner.swift`**

In `Bashteroids/Systems/Spawner.swift`, line 162:

```swift
            let kinds: [PowerUpKind] = [.shield, .dualCanon, .brakes]
```

becomes:

```swift
            let kinds: [PowerUpKind] = [.shield, .dualCanon, .boost]
```

- [ ] **Step 10: Update `GameScene+Debug.swift` for the renamed kind**

In `Bashteroids/Scenes/GameScene+Debug.swift`, line 24:

```swift
            case .three: debugSpawnPowerUp(.brakes)
```

becomes:

```swift
            case .three: debugSpawnPowerUp(.boost)
```

Also update the comment block at the top of the file (lines 9–10):

```swift
// Shift+number drops a power-up that drifts inward from a random edge:
//   Shift+1 = shield, Shift+2 = dual-canon, Shift+3 = brakes
```

becomes:

```swift
// Shift+number drops a power-up that drifts inward from a random edge:
//   Shift+1 = shield, Shift+2 = dual-canon, Shift+3 = boost
```

- [ ] **Step 11: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero warnings. Most likely failure: any other file still referencing `.brakes`. Run `grep -rn "\.brakes\|hasBrakes\|brakesMarker" Bashteroids/` and fix any stragglers (none expected; the steps above are exhaustive but verify).

- [ ] **Step 12: Commit**

```bash
git add Bashteroids/Entities/Ship.swift Bashteroids/Entities/PowerUp.swift \
        Bashteroids/Render/Shapes.swift Bashteroids/Systems/Collision.swift \
        Bashteroids/Systems/Spawner.swift Bashteroids/Scenes/GameScene+Debug.swift
git commit -m "feat(physics): boost powerup replaces brakes; brakes always on

Lowers Ship.maxSpeed 280 → 140 and adds boostLevel (0/1/2) with
+43% / +79% caps. Every ship can brake from spawn now (drops the
hasBrakes powerup gate). The brakes powerup becomes a boost
powerup with an orange double-chevron icon and an orange chevron
ship marker. Stacks once."
```

---

### Task 3: GameScene parameterization + level persistence

Adds the `level: Int, mode: GameMode` initializer, deletes the DEBUG-only `startLevel` knob, and writes `GameSettings.lastPlayedLevel` on every level transition.

**Files:**
- Modify: `Bashteroids/Scenes/GameScene.swift`
- Delete: `Bashteroids/Utils/DebugSettings.swift`

- [ ] **Step 1: Add `currentLevel`/`mode` initializer**

In `Bashteroids/Scenes/GameScene.swift`, currently `GameScene` is initialized via the bare `SKScene.init(size:)`. Add explicit init at the top of the class (just after the property block, before `didMove(to:)`).

Find the properties block and the existing `currentLevel: Int = 1` declaration around line 28. After that block but before `didMove(to:)` (around line 49), add:

```swift
    let mode: GameMode

    init(size: CGSize, level: Int, mode: GameMode) {
        self.mode = mode
        super.init(size: size)
        self.currentLevel = max(1, min(9, level))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
```

(The existing `private var currentLevel: Int = 1` declaration stays — we mutate it from the init.)

- [ ] **Step 2: Drop the DEBUG `startLevel` read in `didMove(to:)`**

In `GameScene.didMove(to view:)`, locate the block (currently lines 66–70):

```swift
        #if DEBUG
        currentLevel = max(1, DebugSettings.startLevel)
        #else
        currentLevel = 1
        #endif
```

Delete it entirely. `currentLevel` is now seeded by the initializer (default 1 if no level was passed).

- [ ] **Step 3: Write `GameSettings.lastPlayedLevel` on level transitions**

In `GameScene`, locate `checkLevelComplete()` (around line 392). After the `currentLevel += 1` line (line 397), add a write to `GameSettings`:

```swift
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
```

Also write the level on initial scene appearance, so that even if a player dies on level 1 immediately, the title scene next time still defaults to 1 (idempotent). Add a call at the top of `didMove(to:)`, right after the existing `backgroundColor = .black` line:

```swift
    override func didMove(to view: SKView) {
        backgroundColor = .black
        GameSettings.lastPlayedLevel = currentLevel
        spawner = Spawner(bounds: playBounds, glowParent: self)
        ...
```

- [ ] **Step 4: Delete `DebugSettings.swift`**

```bash
git rm Bashteroids/Utils/DebugSettings.swift
```

(Verify no other references first: `grep -rn "DebugSettings" Bashteroids/`. The only references in the repo today are the one we just removed in `GameScene.didMove` and the title-scene `[DEBUG] START LEVEL` block which is removed in Task 4. Both are deleted by then. If any references remain at this stage, the build will fail in step 5 — proceed and fix on failure.)

- [ ] **Step 5: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected failure here: `TitleScene.swift` still calls `GameScene(size:)` (the bare initializer that no longer compiles cleanly because we declared a custom init that requires `level:` and `mode:`). Two ways to handle this:

1. **(Recommended)** Add a temporary convenience init that defaults to `level: 1, mode: .survival`, immediately above the new `init(size:level:mode:)`:

   ```swift
       convenience init(size: CGSize) {
           self.init(size: size, level: 1, mode: .survival)
       }
   ```

   Add this only for Task 3 — Task 4 will remove it once `TitleScene` is updated to call the full init.

2. Skip Step 5 verification until Task 4 lands. Less safe — leaves the build red between tasks.

Pick option 1: add the convenience init now. Build should pass. The convenience init is removed in Task 4 Step 7.

- [ ] **Step 6: Commit**

```bash
git add Bashteroids/Scenes/GameScene.swift
git rm Bashteroids/Utils/DebugSettings.swift
git commit -m "refactor: GameScene takes level + mode via init; drops DebugSettings.startLevel

Adds GameScene.init(size:level:mode:) and writes
GameSettings.lastPlayedLevel on every level transition. The
DEBUG-only startLevel is now superseded by the always-visible
level selector landing in the next commit. Temporary
convenience init keeps TitleScene compiling until that lands."
```

---

### Task 4: Title-screen mode + level selectors

Adds the selector UI, wires input, and updates `tryStart()` to pass the selection through.

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift` (drop convenience init)

- [ ] **Step 1: Add selector state to `TitleScene`**

In `Bashteroids/Scenes/TitleScene.swift`, add to the property block at the top of the class (after `private var slotAWasPressed: [Int: Bool] = [:]`):

```swift
    private var selectedLevel: Int = GameSettings.lastPlayedLevel
    private var selectedMode: GameMode = GameSettings.lastMode

    private var modeLabel: SKLabelNode!
    private var levelLabel: SKLabelNode!
    private var battleHintLabel: SKLabelNode!
    private var dpadEdge: [ObjectIdentifier: (left: Bool, right: Bool, up: Bool, down: Bool)] = [:]
```

- [ ] **Step 2: Build the selector UI in `didMove(to:)`**

In `TitleScene.didMove(to view:)`, after the existing `hint` (the "PRESS A TO JOIN ..." line) but before `addChild(slotsLayer)`, insert:

```swift
        let selectorY = size.height * 0.58
        let selectorSpacing: CGFloat = 240

        let modeLeft = SKLabelNode(text: "<")
        modeLeft.fontName = "AvenirNext-Regular"
        modeLeft.fontSize = 22
        modeLeft.fontColor = SKColor(white: 0.55, alpha: 1)
        modeLeft.position = CGPoint(x: size.width / 2 - selectorSpacing - 40, y: selectorY)
        addChild(modeLeft)

        let modeRight = SKLabelNode(text: ">")
        modeRight.fontName = "AvenirNext-Regular"
        modeRight.fontSize = 22
        modeRight.fontColor = SKColor(white: 0.55, alpha: 1)
        modeRight.position = CGPoint(x: size.width / 2 - selectorSpacing + 40, y: selectorY)
        addChild(modeRight)

        let mode = SKLabelNode(text: "")
        mode.fontName = "AvenirNext-Bold"
        mode.fontSize = 26
        mode.position = CGPoint(x: size.width / 2 - selectorSpacing, y: selectorY)
        addChild(mode)
        self.modeLabel = mode

        let modeCaption = SKLabelNode(text: "MODE")
        modeCaption.fontName = "AvenirNext-Regular"
        modeCaption.fontSize = 12
        modeCaption.fontColor = SKColor(white: 0.45, alpha: 1)
        modeCaption.position = CGPoint(x: size.width / 2 - selectorSpacing, y: selectorY - 24)
        addChild(modeCaption)

        let levelLeft = SKLabelNode(text: "<")
        levelLeft.fontName = "AvenirNext-Regular"
        levelLeft.fontSize = 22
        levelLeft.fontColor = SKColor(white: 0.55, alpha: 1)
        levelLeft.position = CGPoint(x: size.width / 2 + selectorSpacing - 40, y: selectorY)
        addChild(levelLeft)

        let levelRight = SKLabelNode(text: ">")
        levelRight.fontName = "AvenirNext-Regular"
        levelRight.fontSize = 22
        levelRight.fontColor = SKColor(white: 0.55, alpha: 1)
        levelRight.position = CGPoint(x: size.width / 2 + selectorSpacing + 40, y: selectorY)
        addChild(levelRight)

        let level = SKLabelNode(text: "")
        level.fontName = "AvenirNext-Bold"
        level.fontSize = 26
        level.position = CGPoint(x: size.width / 2 + selectorSpacing, y: selectorY)
        addChild(level)
        self.levelLabel = level

        let levelCaption = SKLabelNode(text: "LEVEL")
        levelCaption.fontName = "AvenirNext-Regular"
        levelCaption.fontSize = 12
        levelCaption.fontColor = SKColor(white: 0.45, alpha: 1)
        levelCaption.position = CGPoint(x: size.width / 2 + selectorSpacing, y: selectorY - 24)
        addChild(levelCaption)

        let battleHint = SKLabelNode(text: "BATTLE NEEDS 2+ PLAYERS")
        battleHint.fontName = "AvenirNext-Regular"
        battleHint.fontSize = 12
        battleHint.fontColor = SKColor(red: 0.7, green: 0.4, blue: 0.4, alpha: 1)
        battleHint.position = CGPoint(x: size.width / 2 - selectorSpacing,
                                      y: selectorY - 44)
        battleHint.alpha = 0
        addChild(battleHint)
        self.battleHintLabel = battleHint

        renderSelectors()
```

- [ ] **Step 3: Add `renderSelectors()` helper**

Add this method to `TitleScene` (alongside `renderSlots()`):

```swift
    private func renderSelectors() {
        let battleAvailable = manager.slots.count >= 2

        if selectedMode == .battle && !battleAvailable {
            // Snap back to survival if BATTLE became unavailable.
            selectedMode = .survival
        }

        modeLabel.text = selectedMode == .survival ? "SURVIVAL" : "BATTLE"
        modeLabel.fontColor = selectedMode == .survival
            ? SKColor.white
            : SKColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1)

        if !battleAvailable {
            modeLabel.fontColor = SKColor(white: 0.6, alpha: 1)
        }

        levelLabel.text = "L \(selectedLevel)"
        levelLabel.fontColor = .white

        battleHintLabel.alpha = battleAvailable ? 0 : 1
    }
```

- [ ] **Step 4: Hook `renderSelectors()` into the slots-changed callback**

In the existing `manager.onSlotsChanged = { [weak self] in ... }` block (after the `self.renderSlots()` call), add a `self.renderSelectors()` line at the end of the closure body so the BATTLE availability state stays current:

```swift
        manager.onSlotsChanged = { [weak self] in
            guard let self else { return }
            let newCount = self.manager.slots.count
            if newCount > self.prevSlotCount {
                ...  // existing body unchanged
            }
            self.prevSlotCount = newCount
            self.renderSlots()
            self.renderSelectors()
        }
```

- [ ] **Step 5: Add D-pad selector input handling in `update(_:)`**

In `TitleScene.update(_ currentTime:)`, the existing per-controller polling block currently handles only menu/X/A. Add a D-pad polling block alongside it.

Locate the existing per-controller loop (around line 141 of `TitleScene.swift`):

```swift
        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)
            ...
        }
```

Inside that loop, before the menu/X polling, add D-pad polling. The full updated loop body:

```swift
        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)

            // D-pad selector input. Treat extendedGamepad and microGamepad
            // d-pads identically. Edge-trigger so a held d-pad doesn't spin.
            let dx: Float
            let dy: Float
            if let gp = c.extendedGamepad {
                dx = gp.dpad.xAxis.value
                dy = gp.dpad.yAxis.value
            } else if let mg = c.microGamepad {
                dx = mg.dpad.xAxis.value
                dy = mg.dpad.yAxis.value
            } else {
                dx = 0; dy = 0
            }
            let prev = dpadEdge[id] ?? (false, false, false, false)
            let curr = (left:  dx < -0.5,
                        right: dx >  0.5,
                        up:    dy >  0.5,
                        down:  dy < -0.5)
            let nameEntryActive: Bool = {
                if activeNameSlot != nil { return true }
                #if os(tvOS)
                if NameEntryCoordinator.shared.request != nil { return true }
                #endif
                return false
            }()
            if !nameEntryActive {
                if curr.left  && !prev.left  { cycleMode(by: -1) }
                if curr.right && !prev.right { cycleMode(by:  1) }
                if curr.up    && !prev.up    { cycleLevel(by:  1) }
                if curr.down  && !prev.down  { cycleLevel(by: -1) }
            }
            dpadEdge[id] = curr

            // Menu / X polling — existing code unchanged.
            let menuPressed = c.extendedGamepad?.buttonMenu.isPressed ?? false
            ...
        }
```

- [ ] **Step 6: Add the cycle helpers**

In `TitleScene`, add after `renderSelectors()`:

```swift
    private func cycleMode(by delta: Int) {
        let battleAvailable = manager.slots.count >= 2
        if !battleAvailable { return }
        selectedMode = (selectedMode == .survival) ? .battle : .survival
        renderSelectors()
    }

    private func cycleLevel(by delta: Int) {
        var next = selectedLevel + delta
        if next < 1 { next = 9 }
        if next > 9 { next = 1 }
        selectedLevel = next
        renderSelectors()
    }
```

- [ ] **Step 7: Add keyboard handling for `M` and arrow up/down**

In `TitleScene.handleKeyDown(_:)` (around line 149), add cases for `M` and arrows. Insert these before the existing `case .keyA:` case:

```swift
        if activeNameSlot == nil {
            switch code {
            case .keyM:    cycleMode(by: 1); return
            case .upArrow:   cycleLevel(by: 1); return
            case .downArrow: cycleLevel(by: -1); return
            default: break
            }
        }
```

- [ ] **Step 8: Update `tryStart()` to pass mode + level**

In `TitleScene.tryStart()` (around line 103):

```swift
    private func tryStart() {
        guard !transitioning, !manager.slots.isEmpty, activeNameSlot == nil else { return }
        transitioning = true
        let next = GameScene(size: size)
        next.scaleMode = scaleMode
        view?.presentScene(next, transition: .fade(withDuration: 0.4))
    }
```

becomes:

```swift
    private func tryStart() {
        guard !transitioning, !manager.slots.isEmpty, activeNameSlot == nil else { return }
        if selectedMode == .battle && manager.slots.count < 2 {
            // Selector should already prevent this, but belt-and-suspenders.
            return
        }
        transitioning = true
        GameSettings.lastPlayedLevel = selectedLevel
        GameSettings.lastMode = selectedMode
        let next = GameScene(size: size, level: selectedLevel, mode: selectedMode)
        next.scaleMode = scaleMode
        view?.presentScene(next, transition: .fade(withDuration: 0.4))
    }
```

- [ ] **Step 9: Remove the DEBUG start-level UI and shortcut**

In `TitleScene`, delete the `#if DEBUG ... #endif` block in `didMove(to:)` (the `[DEBUG] START LEVEL: N` label, around lines 62–71). Also delete the `digit(for:)` helper (lines 191–206) and the DEBUG digit branch in `handleKeyDown` (lines 165–173). Specifically delete:

```swift
        #if DEBUG
        let dbg = SKLabelNode(text: "[DEBUG] START LEVEL: \(DebugSettings.startLevel)")
        dbg.fontName = "AvenirNext-Regular"
        dbg.fontSize = 12
        dbg.fontColor = SKColor(white: 0.5, alpha: 1)
        dbg.horizontalAlignmentMode = .right
        dbg.position = CGPoint(x: size.width - 20, y: size.height - 150)
        dbg.name = "debug-start-level"
        addChild(dbg)
        #endif
```

and:

```swift
        #if DEBUG
        if let digit = TitleScene.digit(for: code) {
            DebugSettings.startLevel = max(1, digit)
            if let label = childNode(withName: "debug-start-level") as? SKLabelNode {
                label.text = "[DEBUG] START LEVEL: \(DebugSettings.startLevel)"
            }
            return
        }
        #endif
```

and:

```swift
    #if DEBUG
    private static func digit(for code: GCKeyCode) -> Int? {
        switch code {
        case .zero:  return 0
        case .one:   return 1
        case .two:   return 2
        case .three: return 3
        case .four:  return 4
        case .five:  return 5
        case .six:   return 6
        case .seven: return 7
        case .eight: return 8
        case .nine:  return 9
        default:     return nil
        }
    }
    #endif
```

- [ ] **Step 10: Drop the temporary convenience init in `GameScene`**

In `Bashteroids/Scenes/GameScene.swift`, delete the temporary convenience init added in Task 3 Step 5:

```swift
    convenience init(size: CGSize) {
        self.init(size: size, level: 1, mode: .survival)
    }
```

Also: `GameOverScene.returnToTitle()` constructs `TitleScene(size: size)` — that's the bare `SKScene.init(size:)` and is unaffected.

But — does anywhere else construct `GameScene(size:)`? Run `grep -rn "GameScene(size" Bashteroids/`. The only remaining caller should be `TitleScene.tryStart()` (now updated). If `GameOverScene` re-presents a game scene anywhere, it doesn't (it goes back to title). Confirmed safe to delete.

- [ ] **Step 11: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero warnings.

- [ ] **Step 12: Commit**

```bash
git add Bashteroids/Scenes/TitleScene.swift Bashteroids/Scenes/GameScene.swift
git commit -m "feat(title): mode + level selectors with persistence

Adds two compact selectors to the title screen — SURVIVAL/BATTLE
on the left, level 1-9 on the right. D-pad left/right cycles
mode (any joined controller); D-pad up/down cycles level. Wraps
at 1↔9. BATTLE is disabled with <2 joined players (text dims,
hint shows). Keyboard: M / arrow up / arrow down. Selection
persists in UserDefaults via GameSettings.

The DEBUG-only [DEBUG] START LEVEL HUD and 0-9 keyboard shortcut
are removed (the always-visible selector replaces them)."
```

---

### Task 5: README updates for Phase 1

Documentation catches up with the physics rework before BATTLE lands.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the "Brakes" power-up row**

In `README.md`, locate the Power-ups table. The row is:

```markdown
| **Brakes**     | Red downward triangle              | Unlocks the brake input. Holding brake reduces the ship's speed at 200 px/s² toward 0 — heading is unchanged and the ship never reverses. Two short red bars appear at the rear of the ship while equipped. Stays for the rest of the run. |
```

Replace with:

```markdown
| **Boost**      | Orange double chevron `>>`         | Increases the ship's max velocity by ~43% (from 140 px/s to 200 px/s). A second pickup raises it again to 250 px/s; further pickups do nothing. Two small orange chevrons appear at the rear of the ship while equipped. Stays for the rest of the run. |
```

- [ ] **Step 2: Drop the "needs brakes pickup" qualifier from the Controls table**

The current Brake row is:

```markdown
| Brake   | B button / right stick ↓ *(needs brakes pickup)* | ↓ *(needs brakes pickup)* |
```

becomes:

```markdown
| Brake   | B button / right stick ↓                         | ↓                 |
```

- [ ] **Step 3: Add a Modes section before "Levels"**

Above the existing `## Levels` heading, insert:

```markdown
## Modes

Pick the mode and starting level on the title screen using the D-pad on any joined controller (or `M` and arrow up/down on a keyboard). Both selections persist between launches.

- **Survival** (default): the existing single-player or co-op mode against asteroids, UFOs, alien monsters, snakes, mines, and rocks. Score-based; a run lives in the leaderboard.
- **Battle** (2+ players required): a deathmatch round inside an arena enclosed by destructible vector walls. No enemies, sparse powerups, last ship standing wins.

Levels 1–9 control how dense the spawn / wall set is. The default level is whatever level you last reached.
```

- [ ] **Step 4: Update the Title scene description in "Debug build extras"**

Currently:

```markdown
- **Title screen:** number keys 1-9 set the start level for the next game (0 resets to 1). The current value shows in the top-right as `[DEBUG] START LEVEL: N`.
```

Delete that bullet entirely (the level selector covers this in Release).

- [ ] **Step 5: Update the in-game spawn-on-keystroke list**

```markdown
  - `Shift+1` shield · `Shift+2` dual-canon · `Shift+3` brakes
```

becomes:

```markdown
  - `Shift+1` shield · `Shift+2` dual-canon · `Shift+3` boost
```

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "docs(readme): boost powerup, modes section, brake-as-default

Documents the Phase 1 changes: brakes is now always-on, the brake
powerup is replaced by a boost (orange chevron), and the title
screen has mode + level selectors. BATTLE mode is mentioned but
arena specifics land in the Phase 2 commit."
```

---

### Phase 1 verification checkpoint

Before starting Phase 2, manually verify Phase 1 in Xcode:

1. Run on Mac Catalyst (or simulator). Confirm:
   - Title screen shows the new selectors
   - Selecting BATTLE with 1 player ghosts the toggle and shows the hint
   - Joining a 2nd controller un-ghosts BATTLE
   - Selecting BATTLE then starting plays a survival round (Phase-1 expected behavior)
   - Picking up a `>>` powerup makes the ship's max speed visibly higher
2. Quit and relaunch — selectors restore to the last-played mode + level.

Phase 2 starts below.

---

## Phase 2

### Task 6: Wall entity + chunk model

A `Wall` is a SpriteKit-renderable obstacle composed of one (strong) or four (weak) chunks. Each chunk is a convex polygon with hp.

**Files:**
- Create: `Bashteroids/Entities/Wall.swift`
- Modify: `Bashteroids/Render/Shapes.swift` (add wall outline helper)

- [ ] **Step 1: Add the wall-outline helper to `Shapes.swift`**

In `Bashteroids/Render/Shapes.swift`, add after the existing `rock(...)` helper (around line 86):

```swift
    /// Builds the local-coordinate vertices of an irregular hollow polygon
    /// suitable for a wall. Same `seed` ⇒ same shape. Vertices are returned
    /// CCW around the polygon centroid.
    static func wallVertices(radius: CGFloat, seed: UInt64, count: Int = 9) -> [CGPoint] {
        var rng = SeededGenerator(seed: seed)
        var verts: [CGPoint] = []
        verts.reserveCapacity(count)
        for i in 0..<count {
            let baseAngle = CGFloat(i) / CGFloat(count) * .pi * 2
            let angleJitter = rng.cgFloat(in: -0.10...0.10)
            let radiusJitter = rng.cgFloat(in: 0.85...1.10)
            let r = radius * radiusJitter
            let a = baseAngle + angleJitter
            verts.append(CGPoint(x: r * cos(a), y: r * sin(a)))
        }
        return verts
    }

    /// SKShapeNode with a closed polygon path through `vertices`. Stroke only.
    static func wallChunk(vertices: [CGPoint], color: SKColor) -> SKShapeNode {
        let path = CGMutablePath()
        for (i, v) in vertices.enumerated() {
            if i == 0 { path.move(to: v) } else { path.addLine(to: v) }
        }
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.strokeColor = color
        node.fillColor   = .clear
        node.lineWidth   = 1.5
        node.lineJoin    = .miter
        node.isAntialiased = true
        return node
    }
```

- [ ] **Step 2: Create `Wall.swift`**

Create `Bashteroids/Entities/Wall.swift` with:

```swift
import SpriteKit

enum WallStrength {
    case strong, weak
}

/// One destructible (or indestructible) wall. Owns 1+ chunks. Strong walls have
/// a single chunk with .max hp. Weak walls have 4 wedge chunks with hp 5 each.
final class Wall: Entity {
    static let weakChunkHP: Int = 5
    static let weakChunkCount: Int = 4

    static let strongStroke = SKColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1)
    static let weakStroke   = SKColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1)

    let node: SKNode
    var velocity: CGPoint = .zero
    let radius: CGFloat              // bounding circle of the whole wall
    var alive: Bool = true
    let strength: WallStrength
    private(set) var chunks: [Chunk] = []

    init(strength: WallStrength,
         centerPosition: CGPoint,
         radius: CGFloat,
         seed: UInt64) {
        self.strength = strength
        self.radius = radius
        let n = SKNode()
        n.position = centerPosition
        self.node = n

        let outerVerts = Shapes.wallVertices(radius: radius, seed: seed)
        switch strength {
        case .strong:
            let chunk = Chunk(
                centroid: .zero,
                vertices: outerVerts,
                originalVertices: outerVerts,
                hp: .max,
                shape: Shapes.wallChunk(vertices: outerVerts, color: Self.strongStroke),
                index: 0
            )
            n.addChild(chunk.shape)
            self.chunks = [chunk]
        case .weak:
            self.chunks = Wall.makeWeakWedges(from: outerVerts, parent: n)
        }
    }

    func update(dt: TimeInterval) { /* walls don't move */ }

    /// Splits the wall polygon into 4 radial wedges from its centroid. Each
    /// wedge is convex, ~90° of the perimeter, with a small inner gap so
    /// chunks read as visually distinct from the start.
    private static func makeWeakWedges(from outerVerts: [CGPoint], parent: SKNode) -> [Chunk] {
        let centroid = polygonCentroid(outerVerts)
        let count = weakChunkCount
        var perAngleSlot: [[CGPoint]] = Array(repeating: [], count: count)
        // Bin outer vertices by their angle relative to the centroid.
        for v in outerVerts {
            let a = atan2(v.y - centroid.y, v.x - centroid.x)
            let normalized = a < 0 ? a + 2 * .pi : a
            let slot = min(count - 1, Int(normalized / (2 * .pi) * CGFloat(count)))
            perAngleSlot[slot].append(v)
        }
        // For each wedge, build a convex polygon: centroid + the slot's
        // outer vertices (sorted by angle) with a small inset toward the
        // centroid for the inner gap.
        let innerGap: CGFloat = 4
        var chunks: [Chunk] = []
        for (i, slotVerts) in perAngleSlot.enumerated() {
            // Add a leading + trailing boundary point at the wedge's
            // angular limits so all four wedges tile cleanly.
            let startAngle = (CGFloat(i)     / CGFloat(count)) * 2 * .pi
            let endAngle   = (CGFloat(i + 1) / CGFloat(count)) * 2 * .pi
            let r = max(slotVerts.map { hypot($0.x - centroid.x, $0.y - centroid.y) }.max() ?? 0,
                        20)
            let leading  = CGPoint(x: centroid.x + r * cos(startAngle),
                                   y: centroid.y + r * sin(startAngle))
            let trailing = CGPoint(x: centroid.x + r * cos(endAngle),
                                   y: centroid.y + r * sin(endAngle))
            var ringVerts: [CGPoint] = [leading] + slotVerts + [trailing]
            ringVerts.sort { atan2($0.y - centroid.y, $0.x - centroid.x)
                <  atan2($1.y - centroid.y, $1.x - centroid.x) }
            // Build wedge: ring vertices + an inset centroid point.
            let wedge = ringVerts + [CGPoint(x: centroid.x + cos((startAngle + endAngle) / 2) * innerGap,
                                              y: centroid.y + sin((startAngle + endAngle) / 2) * innerGap)]
            let shape = Shapes.wallChunk(vertices: wedge, color: weakStroke)
            parent.addChild(shape)
            chunks.append(Chunk(
                centroid: centroid,
                vertices: wedge,
                originalVertices: wedge,
                hp: weakChunkHP,
                shape: shape,
                index: i
            ))
        }
        return chunks
    }

    private static func polygonCentroid(_ verts: [CGPoint]) -> CGPoint {
        var cx: CGFloat = 0
        var cy: CGFloat = 0
        for v in verts { cx += v.x; cy += v.y }
        let n = CGFloat(verts.count)
        return CGPoint(x: cx / n, y: cy / n)
    }
}

/// One destructible piece of a wall.
struct Chunk {
    let centroid: CGPoint        // wall-local
    var vertices: [CGPoint]      // wall-local; current (eroded) shape
    let originalVertices: [CGPoint]
    var hp: Int
    let shape: SKShapeNode
    let index: Int               // 0..<weakChunkCount; used as RNG seed
    var alive: Bool { hp > 0 }
}
```

- [ ] **Step 3: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`. The new code has no callers yet so it just compiles.

- [ ] **Step 4: Commit**

```bash
git add Bashteroids/Entities/Wall.swift Bashteroids/Render/Shapes.swift
git commit -m "feat(battle): Wall entity + chunk model

Adds the Wall class, its Chunk struct, and the makeWeakWedges
splitter that breaks an irregular polygon into 4 radial-wedge
chunks of 5 hp each. Strong walls are single-chunk with .max
hp. Wall outline rendering uses the new Shapes.wallChunk helper.
No callers yet — wired up in BattleArena."
```

---

### Task 7: BattleArena generator + LevelRoster.battleConfig

**Files:**
- Create: `Bashteroids/Systems/BattleArena.swift`
- Modify: `Bashteroids/Systems/LevelRoster.swift`

- [ ] **Step 1: Add `BattleConfig` and `battleConfig(for:)` to `LevelRoster.swift`**

At the bottom of `Bashteroids/Systems/LevelRoster.swift`, after the closing brace of the `LevelRoster` enum, add:

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

- [ ] **Step 2: Create `BattleArena.swift`**

Create `Bashteroids/Systems/BattleArena.swift` with:

```swift
import SpriteKit

enum BattleArena {
    static let edgeMargin: CGFloat = 80
    static let interWallMargin: CGFloat = 80
    static let strongRadiusRange: ClosedRange<CGFloat> = 35...55
    static let weakRadiusRange:   ClosedRange<CGFloat> = 25...40
    static let mazeClusterGap: CGFloat = 120
    static let placementTries = 50

    /// Generate the wall set for a BATTLE round. Caller adds each Wall.node
    /// as a child of the GameScene.
    static func generate(in bounds: CGRect, level: Int, seed: UInt64) -> [Wall] {
        var rng = SeededGenerator(seed: seed)
        let cfg = LevelRoster.battleConfig(for: level)
        let scale: CGFloat = 1 + CGFloat(level - 1) * 0.05

        var walls: [Wall] = []

        // Strong walls first.
        for _ in 0..<cfg.strong {
            let r = rng.cgFloat(in: strongRadiusRange) * scale
            if let pos = pickOpenSpot(in: bounds, walls: walls, radius: r, rng: &rng) {
                walls.append(Wall(strength: .strong,
                                  centerPosition: pos,
                                  radius: r,
                                  seed: rng.next()))
            }
        }

        // Weak walls — split into clustered (maze) and standalone.
        let standaloneWeak = max(0, cfg.weak - cfg.mazeClusters * 2)

        for _ in 0..<cfg.mazeClusters {
            // A cluster is 2 weak walls in a short L (or line) ~120 px apart.
            let r = rng.cgFloat(in: weakRadiusRange) * scale
            guard let anchor = pickOpenSpot(in: bounds, walls: walls,
                                            radius: r, rng: &rng) else { continue }
            walls.append(Wall(strength: .weak,
                              centerPosition: anchor,
                              radius: r,
                              seed: rng.next()))
            // Place the partner along a random cardinal direction.
            let dir = [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0),
                       CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)]
                .randomElement(using: &rng) ?? CGPoint(x: 1, y: 0)
            let partnerPos = CGPoint(
                x: anchor.x + dir.x * mazeClusterGap,
                y: anchor.y + dir.y * mazeClusterGap)
            // Only place the partner if it's still inside bounds + clear.
            if rectInsetByEdge(bounds).contains(partnerPos),
               !overlapsAny(partnerPos, radius: r, walls: walls) {
                walls.append(Wall(strength: .weak,
                                  centerPosition: partnerPos,
                                  radius: r,
                                  seed: rng.next()))
            }
        }

        for _ in 0..<standaloneWeak {
            let r = rng.cgFloat(in: weakRadiusRange) * scale
            if let pos = pickOpenSpot(in: bounds, walls: walls, radius: r, rng: &rng) {
                walls.append(Wall(strength: .weak,
                                  centerPosition: pos,
                                  radius: r,
                                  seed: rng.next()))
            }
        }

        return walls
    }

    // MARK: - Geometry helpers

    private static func rectInsetByEdge(_ bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: edgeMargin, dy: edgeMargin)
    }

    private static func overlapsAny(_ p: CGPoint, radius: CGFloat, walls: [Wall]) -> Bool {
        for w in walls {
            let need = w.radius + radius + interWallMargin
            if w.node.position.distanceSquared(to: p) < need * need {
                return true
            }
        }
        return false
    }

    private static func pickOpenSpot(in bounds: CGRect,
                                     walls: [Wall],
                                     radius: CGFloat,
                                     rng: inout SeededGenerator) -> CGPoint? {
        let inner = rectInsetByEdge(bounds)
        guard inner.width > 0 && inner.height > 0 else { return nil }
        for _ in 0..<placementTries {
            let p = CGPoint(x: rng.cgFloat(in: inner.minX...inner.maxX),
                            y: rng.cgFloat(in: inner.minY...inner.maxY))
            if !overlapsAny(p, radius: radius, walls: walls) { return p }
        }
        return nil
    }

    // MARK: - Ship-vs-wall reflection

    /// Apply ship-vs-wall reflection physics in-place. Returns true if the
    /// ship was reflected (used by callers for sound effects).
    @discardableResult
    static func reflectShipsOffWalls(_ ships: [Ship], walls: [Wall]) -> Bool {
        var reflected = false
        for ship in ships where ship.alive {
            let shipPos = ship.position
            for wall in walls where wall.alive {
                let wallPos = wall.node.position
                // Broad-phase: bounding circle of the whole wall.
                let outer = wall.radius + ship.radius
                if shipPos.distanceSquared(to: wallPos) > outer * outer { continue }

                for chunkIdx in 0..<wall.chunks.count {
                    guard wall.chunks[chunkIdx].alive else { continue }
                    let chunk = wall.chunks[chunkIdx]
                    if reflectIfNeeded(ship: ship, wall: wall, chunk: chunk) {
                        reflected = true
                    }
                }
            }
        }
        return reflected
    }

    private static func reflectIfNeeded(ship: Ship, wall: Wall, chunk: Chunk) -> Bool {
        let wallPos = wall.node.position
        let localShip = CGPoint(x: ship.position.x - wallPos.x,
                                y: ship.position.y - wallPos.y)

        var bestPenetration: CGFloat = -.infinity
        var bestNormal: CGPoint = .zero

        let n = chunk.vertices.count
        for i in 0..<n {
            let a = chunk.vertices[i]
            let b = chunk.vertices[(i + 1) % n]
            let edge = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let len = hypot(edge.x, edge.y)
            guard len > 0 else { continue }

            // Outward normal (right-hand perpendicular for CCW polygon).
            let nx = edge.y / len
            let ny = -edge.x / len
            let normal = CGPoint(x: nx, y: ny)

            // Distance from localShip to the line through (a,b).
            let toShip = CGPoint(x: localShip.x - a.x, y: localShip.y - a.y)
            let signedDist = toShip.x * normal.x + toShip.y * normal.y

            if signedDist < ship.radius {
                // Inside this edge plane (or close to it). Track the deepest
                // edge — that's the one we reflect off.
                let penetration = ship.radius - signedDist
                if penetration > bestPenetration {
                    bestPenetration = penetration
                    bestNormal = normal
                }
            }
        }

        guard bestPenetration > 0 else { return false }

        // Only reflect if the ship is moving INTO the wall.
        let vn = ship.velocity.x * bestNormal.x + ship.velocity.y * bestNormal.y
        guard vn < 0 else {
            // Already moving outward — just nudge out so we don't re-trigger.
            ship.position = CGPoint(x: ship.position.x + bestNormal.x * bestPenetration,
                                    y: ship.position.y + bestNormal.y * bestPenetration)
            return false
        }

        // Reflect velocity across the normal, with 50% energy loss.
        let reflectedVx = (ship.velocity.x - 2 * vn * bestNormal.x) * 0.5
        let reflectedVy = (ship.velocity.y - 2 * vn * bestNormal.y) * 0.5
        ship.velocity = CGPoint(x: reflectedVx, y: reflectedVy)

        // Push ship outside by the penetration depth + a small epsilon.
        ship.position = CGPoint(
            x: ship.position.x + bestNormal.x * (bestPenetration + 0.5),
            y: ship.position.y + bestNormal.y * (bestPenetration + 0.5)
        )
        return true
    }
}
```

- [ ] **Step 3: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`. New code, still no callers.

- [ ] **Step 4: Commit**

```bash
git add Bashteroids/Systems/BattleArena.swift Bashteroids/Systems/LevelRoster.swift
git commit -m "feat(battle): BattleArena wall generator + reflection helper

Generates the per-level wall set: strong walls placed first via
rejection sampling, then weak walls (some grouped into 2-wall
maze clusters at higher levels). Includes the ship-vs-wall
closest-edge reflection helper that loses 50% of normal-component
velocity on bounce."
```

---

### Task 8: Bullet vs wall collision + chunk erosion

The core BATTLE-mode bullet behavior: bullets die on any wall, and weak chunks erode visually as they take damage.

**Files:**
- Modify: `Bashteroids/Entities/Wall.swift`
- Modify: `Bashteroids/Systems/Collision.swift`

- [ ] **Step 1: Add the chunk-hit / erosion API to `Wall.swift`**

In `Bashteroids/Entities/Wall.swift`, add to the `Wall` class (after `func update(dt:)`):

```swift
    /// Returns true if `point` is inside any live chunk. Side effect: if the
    /// hit chunk is weak, decrements its hp and updates the visual.
    func registerBulletHit(at point: CGPoint) -> Bool {
        let local = CGPoint(x: point.x - node.position.x,
                            y: point.y - node.position.y)

        for i in 0..<chunks.count {
            guard chunks[i].alive else { continue }
            if Wall.pointInPolygon(local, polygon: chunks[i].vertices) {
                if strength == .weak {
                    chunks[i].hp -= 1
                    if chunks[i].hp <= 0 {
                        chunks[i].shape.removeFromParent()
                    } else {
                        Wall.erodeChunk(&chunks[i])
                    }
                    if !chunks.contains(where: { $0.alive }) {
                        alive = false
                    }
                }
                return true
            }
        }
        return false
    }

    private static func erodeChunk(_ chunk: inout Chunk) {
        // Pick 1-2 vertices and pull them toward the chunk's local centroid by 8-14%.
        var rng = SeededGenerator(seed: UInt64(chunk.index) * 31 + UInt64(max(0, chunk.hp)))
        let nToMove = Int(rng.cgFloat(in: 1.0...2.0))
        let count = chunk.originalVertices.count
        var newVerts = chunk.vertices
        for _ in 0..<nToMove {
            let idx = Int(rng.cgFloat(in: 0..<CGFloat(count)))
            let pull = rng.cgFloat(in: 0.08...0.14)
            let v = newVerts[idx]
            newVerts[idx] = CGPoint(
                x: v.x + (chunk.centroid.x - v.x) * pull,
                y: v.y + (chunk.centroid.y - v.y) * pull
            )
        }
        chunk.vertices = newVerts

        let path = CGMutablePath()
        for (i, v) in newVerts.enumerated() {
            if i == 0 { path.move(to: v) } else { path.addLine(to: v) }
        }
        path.closeSubpath()
        chunk.shape.path = path
        chunk.shape.alpha = 0.5 + 0.1 * CGFloat(chunk.hp)
    }

    /// Standard ray-cast point-in-polygon test (CCW polygon).
    static func pointInPolygon(_ p: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i]
            let b = polygon[j]
            if (a.y > p.y) != (b.y > p.y) {
                let xIntersect = (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
                if p.x < xIntersect { inside.toggle() }
            }
            j = i
        }
        return inside
    }
```

- [ ] **Step 2: Add walls to the `Collision.resolve(...)` signature**

`Collision.resolve(...)` is called once per frame from `GameScene.update(_:)`. Extend its signature with a `walls:` parameter and add the bullet-vs-wall pass.

In `Bashteroids/Systems/Collision.swift`, change the function signature (line 4):

```swift
    static func resolve(ships: [Ship],
                        asteroids: [Asteroid],
                        ufos: [UFO],
                        alienMonsters: [AlienMonster],
                        bullets: [Bullet],
                        powerUps: [PowerUp],
                        rocks: [Rock],
                        mines: [Mine],
                        snakes: [Snake],
                        shipsCollideWithEachOther: Bool) {
```

becomes:

```swift
    static func resolve(ships: [Ship],
                        asteroids: [Asteroid],
                        ufos: [UFO],
                        alienMonsters: [AlienMonster],
                        bullets: [Bullet],
                        powerUps: [PowerUp],
                        rocks: [Rock],
                        mines: [Mine],
                        snakes: [Snake],
                        walls: [Wall],
                        shipsCollideWithEachOther: Bool) {
```

- [ ] **Step 3: Add the bullet-vs-wall pass**

In `Collision.resolve(...)`, find the bullet-loop block (starts at line 92, "for bullet in bullets where bullet.alive"). Inside that loop, after the last existing inner block (`for ship in ships ...`, ending around line 144) and before the loop's closing brace, add a wall test:

The relevant insertion location is right after this block:

```swift
            for ship in ships where ship.alive {
                if bullet.owner === ship { continue }
                if !shipsCollideWithEachOther, bullet.owner is Ship { continue }
                if overlap(bullet, ship) {
                    bullet.alive = false
                    hitShip(ship)
                    (bullet.owner as? Ship)?.score += Score.ship
                    break
                }
            }
```

Add immediately after:

```swift
            if !bullet.alive { continue }
            for wall in walls where wall.alive {
                let outer = wall.radius + bullet.radius
                if wall.node.position.distanceSquared(to: bullet.position) > outer * outer { continue }
                if wall.registerBulletHit(at: bullet.position) {
                    bullet.alive = false
                    break
                }
            }
```

- [ ] **Step 4: Update the existing call site in `GameScene.swift`**

In `GameScene.update(_ currentTime:)`, the existing call (around line 144) is:

```swift
        Collision.resolve(ships: ships, asteroids: asteroids, ufos: ufos,
                          alienMonsters: alienMonsters,
                          bullets: bullets, powerUps: powerUps,
                          rocks: rocks, mines: mines,
                          snakes: snakes,
                          shipsCollideWithEachOther: pvpEnabled)
```

becomes:

```swift
        Collision.resolve(ships: ships, asteroids: asteroids, ufos: ufos,
                          alienMonsters: alienMonsters,
                          bullets: bullets, powerUps: powerUps,
                          rocks: rocks, mines: mines,
                          snakes: snakes,
                          walls: walls,
                          shipsCollideWithEachOther: pvpEnabled)
```

This requires `var walls: [Wall] = []` to exist on `GameScene`. Add that to the property block at the top of the class (alongside the other entity arrays):

```swift
    private var walls: [Wall] = []
```

(Position it near the existing `private var snakes: [Snake] = []` line.)

- [ ] **Step 5: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`. The walls array is empty in survival mode, so no behavior change yet.

- [ ] **Step 6: Commit**

```bash
git add Bashteroids/Entities/Wall.swift Bashteroids/Systems/Collision.swift Bashteroids/Scenes/GameScene.swift
git commit -m "feat(battle): bullet-vs-wall collision + chunk erosion

Bullets die when they enter any live wall chunk. Weak chunks
decrement hp and visually erode (1-2 vertices nudged inward,
alpha drops linearly with hp). When all of a weak wall's chunks
are gone, the wall is removed. Strong walls are unaffected.
Wall list is empty in survival, so no observable change yet."
```

---

### Task 9: Ship vs wall reflection

Wires `BattleArena.reflectShipsOffWalls(...)` into `GameScene.update(_:)`.

**Files:**
- Modify: `Bashteroids/Scenes/GameScene.swift`

- [ ] **Step 1: Call the reflection helper after movement, before collisions**

In `GameScene.update(_ currentTime:)`, the movement section (around lines 135–141) currently:

```swift
        Movement.stepWrapping(ships,    dt: dt, bounds: bounds)
        Movement.stepWrapping(asteroids, dt: dt, bounds: bounds)
        Movement.stepWrapping(ufos,     dt: dt, bounds: bounds)
        Movement.stepBounded(bullets,  dt: dt, bounds: bounds)
        Movement.stepBounded(powerUps, dt: dt, bounds: bounds)
        Movement.stepBounded(rocks, dt: dt, bounds: bounds.insetBy(dx: -60, dy: -60))

        let pvpEnabled = (levelState == .spawning)
```

After the rocks line and before the `let pvpEnabled` line, insert:

```swift
        if mode == .battle && !walls.isEmpty {
            BattleArena.reflectShipsOffWalls(ships, walls: walls)
        }
```

This runs after ships have moved this frame but before the collision pass — so reflected ships are in their corrected positions when collisions resolve.

- [ ] **Step 2: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Bashteroids/Scenes/GameScene.swift
git commit -m "feat(battle): wire ship-vs-wall reflection into update loop

Calls BattleArena.reflectShipsOffWalls in BATTLE mode, between
the ship movement step and the collision pass, so reflected
ships have their corrected positions before collisions resolve.
Still a no-op until walls are generated (next commit)."
```

---

### Task 10: BATTLE mode round flow

Generates walls on scene appearance, places ships safely, branches the spawner, replaces the survival win condition with last-ship-standing.

**Files:**
- Modify: `Bashteroids/Scenes/GameScene.swift`
- Modify: `Bashteroids/Systems/Spawner.swift`

- [ ] **Step 1: Add `mode` to `Spawner` and a BATTLE-mode `startLevel` shortcut**

In `Bashteroids/Systems/Spawner.swift`, add to the property block at the top of the class (after `var bounds: CGRect`, around line 26):

```swift
    var mode: GameMode = .survival
    private var nextBattlePowerUpTime: TimeInterval?
```

Then update `startLevel(_:)` (around line 64) to skip the survival queue in BATTLE:

```swift
    func startLevel(_ config: LevelConfig) {
        queue.removeAll(keepingCapacity: true)
        for p in pending { p.glow?.removeFromParent() }
        pending.removeAll(keepingCapacity: true)

        if mode == .battle {
            // BATTLE mode runs on its own powerup drip schedule (see
            // updateBattlePowerUps). No enemies queued.
            nextBattlePowerUpTime = TimeInterval.random(in: 30...60)
            elapsed = 0
            timeToNextSpawn = .infinity
            return
        }

        append(.asteroid, count: config.asteroids)
        append(.ufo,      count: config.ufos)
        append(.alien,    count: config.aliens)
        append(.mine,     count: config.mines)
        append(.rock,     count: config.rocks)
        append(.snake,    count: config.snakes)
        append(.powerUp,  count: config.powerUps)
        queue.shuffle(using: &rng)

        elapsed = 0
        timeToNextSpawn = 0.5
    }
```

Then add a new `updateBattlePowerUps(...)` helper at the end of the `Spawner` class (after `inwardAngle(side:)`):

```swift
    /// Per-frame BATTLE powerup drip. Call from GameScene.update AFTER
    /// Spawner.update so `elapsed` is current (Spawner.update increments
    /// `elapsed` unconditionally). Returns one Spawn (the powerup) if a drop
    /// is due this frame.
    func updateBattlePowerUps(walls: [Wall], rng: inout SeededGenerator) -> Spawn? {
        guard mode == .battle, let due = nextBattlePowerUpTime else { return nil }
        guard elapsed >= due else { return nil }

        let kinds: [(PowerUpKind, Int)] = [(.shield, 3), (.dualCanon, 1), (.boost, 1)]
        let totalWeight = kinds.reduce(0) { $0 + $1.1 }
        var pick = Int(rng.cgFloat(in: 0..<CGFloat(totalWeight)))
        var chosen: PowerUpKind = .shield
        for (k, w) in kinds {
            if pick < w { chosen = k; break }
            pick -= w
        }

        let position = randomOpenSpotForPowerUp(walls: walls, rng: &rng)
        nextBattlePowerUpTime = elapsed + TimeInterval(rng.cgFloat(in: 30...60))

        return Spawn(kind: .powerUp(kind: chosen, speed: 0),
                     position: position,
                     velocity: .zero,
                     side: .top)
    }

    /// Pick a random open spot for a BATTLE powerup. Prefers spots ≥ 40 px
    /// from any wall chunk; gives up after 30 tries and uses the best
    /// candidate so far.
    private func randomOpenSpotForPowerUp(walls: [Wall],
                                          rng: inout SeededGenerator) -> CGPoint {
        let inner = bounds.insetBy(dx: 60, dy: 60)
        let minClearance: CGFloat = 40
        var best = CGPoint(x: inner.midX, y: inner.midY)
        var bestClearance: CGFloat = -.infinity

        for _ in 0..<30 {
            let p = CGPoint(x: rng.cgFloat(in: inner.minX...inner.maxX),
                            y: rng.cgFloat(in: inner.minY...inner.maxY))
            var clearance: CGFloat = .infinity
            for w in walls where w.alive {
                let d = sqrt(w.node.position.distanceSquared(to: p)) - w.radius
                clearance = min(clearance, d)
            }
            if clearance >= minClearance { return p }
            if clearance > bestClearance {
                bestClearance = clearance
                best = p
            }
        }
        return best
    }
```

`Spawner.update(dt:)` is also called every frame for survival mode and currently advances `elapsed` and tries to drain the queue. In BATTLE the queue is empty (Step 1 returned early), so `update(dt:)` is harmless to call — `elapsed` continues to advance, the queue check is a no-op, and `pending` is empty so nothing is yielded. Keep calling it from `GameScene` unchanged.

- [ ] **Step 2: Wire BATTLE setup into `GameScene.didMove(to:)`**

In `Bashteroids/Scenes/GameScene.swift`, find the `didMove(to:)` block. The existing structure (after our Task 3 changes) is roughly:

```swift
    override func didMove(to view: SKView) {
        backgroundColor = .black
        GameSettings.lastPlayedLevel = currentLevel
        spawner = Spawner(bounds: playBounds, glowParent: self)

        spawnShipsForJoinedPlayers(in: playBounds)
        initialShipCount = ships.count

        addChild(hudLayer)
        buildHUD()
        updateHUD()
        ...
```

Replace the `spawner = ...` line and what follows up to the start of `addChild(hudLayer)` with:

```swift
        spawner = Spawner(bounds: playBounds, glowParent: self)
        spawner.mode = mode

        if mode == .battle {
            generateBattleWalls()
            spawnShipsForBattle(in: playBounds)
        } else {
            spawnShipsForJoinedPlayers(in: playBounds)
        }
        initialShipCount = ships.count
```

Then add two new helper methods to the class (alongside `spawnShipsForJoinedPlayers(in:)`):

```swift
    private func generateBattleWalls() {
        let seed = UInt64(Date().timeIntervalSince1970 * 1000)
        walls = BattleArena.generate(in: playBounds, level: currentLevel, seed: seed)
        for wall in walls {
            addChild(wall.node)
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
                + CGFloat.random(in: -0.3...0.3)
            let ship = Ship(playerIndex: slot.index,
                            color: slot.color,
                            position: bestPos,
                            heading: heading)
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
```

- [ ] **Step 3: Branch the win condition**

In `GameScene.checkEndCondition()` (around line 456):

```swift
    private func checkEndCondition() {
        let alive = ships.filter { $0.alive }
        if initialShipCount == 1 {
            if alive.isEmpty { finish(winner: nil) }
        } else {
            if alive.count <= 1 { finish(winner: alive.first) }
        }
    }
```

In BATTLE the existing rule (`alive.count <= 1` triggers `finish(winner: alive.first)`) is exactly right — the only change needed is `finish(winner:)` constructing a different `GameOverScene.Result` (handled in Task 11).

For BATTLE, also handle the 2+ player case where the survival rule of "kill self if no other alive" doesn't apply: in BATTLE, if `alive.count == 0`, that's a draw. The existing branch handles this correctly via `finish(winner: alive.first)` which is `nil` — the new `finish` will branch on mode + nil-vs-non-nil. So no change needed here.

- [ ] **Step 4: Drip BATTLE powerups in the update loop**

In `GameScene.update(_:)`, locate the level-state branch (around line 151):

```swift
        if levelState == .transitioning {
            handleLevelTransition(dt: dt)
        } else {
            let spawns = spawner.update(dt: dt)
            for s in spawns { spawn(s) }
        }
```

For BATTLE we don't want the level-transition state machine — there's no second level in a BATTLE round. Add a branch:

```swift
        if mode == .battle {
            _ = spawner.update(dt: dt)  // advance elapsed only
            var rng = battleRNG
            if let pu = spawner.updateBattlePowerUps(walls: walls, rng: &rng) {
                spawn(pu)
            }
            battleRNG = rng
        } else if levelState == .transitioning {
            handleLevelTransition(dt: dt)
        } else {
            let spawns = spawner.update(dt: dt)
            for s in spawns { spawn(s) }
        }
```

Add the RNG to the property block at the top of the class:

```swift
    private var battleRNG = SeededGenerator(seed: UInt64(Date().timeIntervalSince1970 * 1000))
```

- [ ] **Step 5: Skip the level-state-machine init in BATTLE**

In `GameScene.didMove(to:)`, the trailing block currently sets up the level state machine:

```swift
        levelState = .transitioning
        transitionTime = 0
        bannerStarted = false
        flashStarted = false
```

In BATTLE mode there's only one round. Add a guard: in BATTLE, jump straight to `.spawning` and call `spawner.startLevel(...)` immediately (so the BATTLE powerup drip starts):

```swift
        if mode == .battle {
            levelState = .spawning
            spawner.startLevel(LevelRoster.config(for: currentLevel))
        } else {
            levelState = .transitioning
            transitionTime = 0
            bannerStarted = false
            flashStarted = false
        }
```

`startLevel(_:)` already early-returns the survival-queue setup in BATTLE (Step 1) and just initializes `nextBattlePowerUpTime`.

- [ ] **Step 6: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Bashteroids/Scenes/GameScene.swift Bashteroids/Systems/Spawner.swift
git commit -m "feat(battle): round flow — wall gen, ship placement, powerup drip

In BATTLE mode GameScene generates walls via BattleArena, places
ships at the arena perimeter with a clearance check, skips the
survival level-transition state machine, and drips powerups every
30-60s using a weighted pool (3:1:1 for shield:dualCanon:boost).
Win condition unchanged in shape (last-ship-standing); the
GameOverScene branch lands in the next commit."
```

---

### Task 11: GameOverScene branch + finish() wiring

The existing `finish(winner:)` constructs a `GameOverScene.Result.winner(...)` or `.gameOver(...)`. For BATTLE we add `.battleWinner` and `.battleDraw`.

**Files:**
- Modify: `Bashteroids/Scenes/GameOverScene.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift`

- [ ] **Step 1: Add the BATTLE result cases to `GameOverScene.Result`**

In `Bashteroids/Scenes/GameOverScene.swift`, change the `Result` enum (lines 5–8):

```swift
    enum Result {
        case gameOver(topScore: Int)
        case winner(color: SKColor, label: String, score: Int)
    }
```

becomes:

```swift
    enum Result {
        case gameOver(topScore: Int)
        case winner(color: SKColor, label: String, score: Int)
        case battleWinner(color: SKColor, name: String)
        case battleDraw
    }
```

- [ ] **Step 2: Update `didMove(to:)` to render the new cases**

The existing `didMove(to:)` reduces every result to `(text, color, score)` then renders banner + scoreLabel + hint. Replace the destructure block (lines 27–32) with explicit cases that handle each result independently:

Currently:

```swift
        let (text, color, score): (String, SKColor, Int) = {
            switch result {
            case .gameOver(let s): return ("GAME OVER", .white, s)
            case .winner(let c, let label, let s): return (label, c, s)
            }
        }()

        let banner = SKLabelNode(text: text)
        banner.fontName = "AvenirNext-Bold"
        banner.fontSize = 72
        banner.fontColor = color
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        addChild(banner)

        let scoreLabel = SKLabelNode(text: "SCORE  \(score)")
        scoreLabel.fontName = "AvenirNext-Bold"
        scoreLabel.fontSize = 32
        scoreLabel.fontColor = SKColor(white: 0.75, alpha: 1)
        scoreLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.45)
        addChild(scoreLabel)
```

becomes:

```swift
        switch result {
        case .gameOver(let s):
            renderBanner(text: "GAME OVER", color: .white)
            renderSubtitle(text: "SCORE  \(s)")
        case .winner(let c, let label, let s):
            renderBanner(text: label, color: c)
            renderSubtitle(text: "SCORE  \(s)")
        case .battleWinner(let c, let name):
            renderBanner(text: "\(name) WINS", color: c)
        case .battleDraw:
            renderBanner(text: "DRAW", color: .white)
        }
```

Add the two helper methods to the `GameOverScene` class:

```swift
    private func renderBanner(text: String, color: SKColor) {
        let banner = SKLabelNode(text: text)
        banner.fontName = "AvenirNext-Bold"
        banner.fontSize = 72
        banner.fontColor = color
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        addChild(banner)
    }

    private func renderSubtitle(text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 32
        label.fontColor = SKColor(white: 0.75, alpha: 1)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.45)
        addChild(label)
    }
```

The `hint` ("PRESS A · START · SPACE") and the input handling stay unchanged.

- [ ] **Step 3: Locate `GameScene.finish(winner:)` and branch on mode**

`GameScene` already has a `finish(winner:)` method called by `checkEndCondition`. Locate it (search for `func finish(winner` in `GameScene.swift`). Identify two things in the current body:

1. Any `HighScore.record(...)` call(s) — these record survival results and must NOT fire in BATTLE.
2. The existing `.winner(...)` / `.gameOver(...)` `Result` construction — preserved unchanged for survival.

Replace the body so it (a) gates high-score recording behind `mode == .survival`, and (b) adds the BATTLE branch:

```swift
    private func finish(winner: Ship?) {
        guard !transitioning else { return }
        transitioning = true
        audio.stopAllThrust()

        if mode == .survival {
            // Record high scores only for survival.
            for ship in ships where ship.score > 0 {
                let name = UserDefaults.standard.string(forKey: "player_name_\(ship.playerIndex)")
                    ?? "P\(ship.playerIndex + 1)"
                HighScore.record(name: name, score: ship.score, level: currentLevel)
            }
        }

        let result: GameOverScene.Result
        if mode == .battle {
            if let w = winner {
                let name = UserDefaults.standard.string(forKey: "player_name_\(w.playerIndex)")
                    ?? "P\(w.playerIndex + 1)"
                result = .battleWinner(color: w.color, name: name)
            } else {
                result = .battleDraw
            }
        } else if let w = winner {
            let name = UserDefaults.standard.string(forKey: "player_name_\(w.playerIndex)")
                ?? "P\(w.playerIndex + 1)"
            result = .winner(color: w.color, label: "\(name) WINS", score: w.score)
        } else {
            let topScore = ships.map(\.score).max() ?? 0
            result = .gameOver(topScore: topScore)
        }

        let next = GameOverScene(size: size, result: result)
        next.scaleMode = scaleMode
        view?.presentScene(next, transition: .fade(withDuration: 0.5))
    }
```

If the existing `finish` is already roughly this shape, just add the `if mode == .survival` guard around `HighScore.record(...)` and the BATTLE branch. If it is different (e.g., labels its `.winner` text differently), preserve the existing survival labels verbatim — only swap the wrapping logic.

- [ ] **Step 4: Build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Bashteroids/Scenes/GameOverScene.swift Bashteroids/Scenes/GameScene.swift
git commit -m "feat(battle): GameOverScene banners for winner / draw

Adds .battleWinner and .battleDraw cases to GameOverScene.Result
with their own banners (no score line). GameScene.finish branches
on mode and only records high scores in survival. BATTLE banners
show the winning player's name in their color, or 'DRAW' when the
last two ships kill each other simultaneously."
```

---

### Task 12: README updates for Phase 2 + final verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Expand the Modes section with BATTLE specifics**

In `README.md`, replace the existing Modes section's BATTLE bullet:

```markdown
- **Battle** (2+ players required): a deathmatch round inside an arena enclosed by destructible vector walls. No enemies, sparse powerups, last ship standing wins.
```

with:

```markdown
- **Battle** (2+ players required): last-ship-standing deathmatch. The arena is dotted with **strong walls** (warm gray, indestructible — bullets die, ships bounce off losing 50% of their normal-component velocity) and **weak walls** (warm orange, made of 4 chunks at 5 hp each — bullets erode them visually as they take damage). Ship-vs-ship rules from survival apply: shields absorb hits, otherwise contact kills both. No enemies spawn; powerups drip every 30-60s (60% shield, 20% dual-canon, 20% boost). Round ends when only one ship is left (or zero — that's a draw).
```

- [ ] **Step 2: Add a BATTLE row to the Entities table**

After the existing "Other ship (PvP)" row, add:

```markdown
| **Wall (strong)** | — | indestructible | Warm-gray vector polygon. Absorbs all bullets. Ships bounce off, losing 50% of their normal-component velocity per bounce. Only spawns in BATTLE mode. | — |
| **Wall (weak)** | — | 5 hp × 4 chunks | Warm-orange vector polygon split into 4 wedges. Each chunk takes 5 bullet hits, eroding visually as it loses hp. Once a chunk hits 0 hp it vanishes; once all chunks are gone the wall is destroyed. Ships bounce as for strong walls (no chunk damage from the bounce). Only spawns in BATTLE mode. | — |
```

- [ ] **Step 3: Final smoke build all three destinations**

```bash
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'platform=macOS,variant=Mac Catalyst' -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
    -destination 'generic/platform=tvOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: all three `** BUILD SUCCEEDED **`, zero warnings.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): document BATTLE mode walls and round flow

Expands the Modes section with the BATTLE specifics — wall
strengths, bounce physics, powerup drip cadence and weighting,
and the win condition. Adds strong / weak walls to the Entities
table."
```

- [ ] **Step 5: Hand off for manual verification**

The headless build can't exercise BATTLE gameplay. Manual checks the user should run on Mac Catalyst (or any destination):

1. Title with 1 player → BATTLE selector is dimmed and pressing left/right does nothing
2. Title with 2 players → BATTLE selector is selectable; cycling through L1–L9 with up/down works and wraps
3. Start a BATTLE round at L1 → ~4 strong walls visible, no weak walls
4. Bullets die when they hit either wall type
5. Ship hits a wall → bounces, doesn't die
6. Shoot a weak wall chunk → its outline gets jaggier / dimmer per hit; vanishes after 5 hits
7. After ~30–60 s a powerup appears at a random open spot
8. Last-ship-standing → "WINS" banner with player name in their color
9. Two ships kill each other simultaneously → "DRAW" banner
10. Returning to title → mode + level selectors restore to what was just played
