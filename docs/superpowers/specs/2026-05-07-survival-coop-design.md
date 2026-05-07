# Survival Co-op Scoring — Design

Date: 2026-05-07

## Goal

From `improvements.md`: "mode survival is a game for all players to work together. It ends until no player is left. The sum of all player scores should be shown at the end and count for the highscore of the last player".

Convert survival mode from "last-player-standing wins" to "team-survives-as-long-as-possible co-op".

## Behavior change

**End condition:** survival ends when **all** ships are dead (`alive.isEmpty`). Was: `alive.count <= 1`.

**Score recording:** one highscore entry instead of per-player entries. Sum all ships' scores into a team total; record under the **last player to die**'s name.

**Last-to-die determination:** track each ship's death tick; pick the ship with the highest tick. On ties (multiple ships die same frame, e.g., mine blast), pick the **lowest player index** (deterministic).

**GameOverScene rendering (layout B):**
- "GAME OVER" — white banner, top
- "TEAM SCORE: NNN" — gold subtitle, middle
- "<NAME> SURVIVED LONGEST" — small footer in the last player's color, below

## Implementation sketch

### `GameScene`

```swift
private var deathTickCounter: Int = 0
private var shipDeathTick: [Int: Int] = [:]   // playerIndex → tick at death
```

In `update(_:)`, increment `deathTickCounter` once per frame (before applyInputs).

In `reapDead()`, when iterating dead ships with `parent != nil` (just-died-this-frame), record:

```swift
if shipDeathTick[ship.playerIndex] == nil {
    shipDeathTick[ship.playerIndex] = deathTickCounter
}
```

In `checkEndCondition()`, replace the survival branch:

```swift
let alive = ships.filter { $0.alive }
if mode == .survival {
    if alive.isEmpty { finish(winner: nil) }
} else {
    // BATTLE: existing last-ship-standing rules
    if initialShipCount == 1 {
        if alive.isEmpty { finish(winner: nil) }
    } else {
        if alive.count <= 1 { finish(winner: alive.first) }
    }
}
```

(Note: BATTLE win condition stays unchanged — it's already correct.)

In `finish(winner:)`, the survival branch becomes:

```swift
if mode == .survival {
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
                          totalScore: totalScore)
} else if mode == .battle {
    // existing battle path
} else {
    // unreachable: only .survival and .battle exist
}
```

### `GameOverScene.Result` enum

Replace `.gameOver(topScore: Int)` and `.winner(...)` (which were both for survival) with a single survival case:

```swift
enum Result {
    case survivalEnd(lastPlayerName: String, lastPlayerColor: SKColor, totalScore: Int)
    case battleWinner(color: SKColor, name: String)
    case battleDraw
}
```

### `GameOverScene.didMove`

```swift
case .survivalEnd(let name, let color, let totalScore):
    renderBanner(text: "GAME OVER", color: .white)
    renderSubtitle(text: "TEAM SCORE: \(totalScore)")  // existing helper, recolor to gold
    let footer = SKLabelNode(text: "\(name) SURVIVED LONGEST")
    footer.fontName = "AvenirNext-Regular"
    footer.fontSize = 22
    footer.fontColor = color
    footer.position = CGPoint(x: size.width / 2, y: size.height * 0.37)
    addChild(footer)
```

The existing `renderSubtitle` is white; for the score subtitle, override the color to gold `(245, 194, 66)` to match the highscore heading.

## Files affected

- Modify: `Bashteroids/Scenes/GameScene.swift` (death tick tracking; `checkEndCondition` survival branch; `finish` survival branch)
- Modify: `Bashteroids/Scenes/GameOverScene.swift` (new `Result` enum case, banner/subtitle/footer layout for survival)

No new files. No deletions.

## Edge cases

- **No deaths recorded.** Defensive: if `shipDeathTick` is empty (impossible during normal play because `finish` only runs on alive.isEmpty in survival), `lastIdx = 0` falls back to player 0.
- **Single-player.** Same code path: solo ship dies → alive.isEmpty → finish → one entry recorded under their name with their score = team total. Visually identical treatment to multi-player end.
- **Zero-team-total game.** All players die before scoring (improbable but possible). The highscore record is gated on `totalScore > 0`, so no zero-score entry pollutes the leaderboard. The GameOverScene still renders normally.

## Out of scope

- Respawning dead players (would change "ends when all dead" semantics).
- Timed bonuses for surviving longer.
- Per-player score breakdown on the GameOverScene (only team total shown).
- Spectator camera for dead players (they wait silently for the run to end).
