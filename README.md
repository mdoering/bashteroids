# Bashteroids

A classic-vector Asteroids-style arcade game for iPad and Mac, played with Bluetooth controllers. Single-player and local couch co-op for up to 4 players.

See [`docs/specs.md`](docs/specs.md) for the gameplay design.

## Stack

- SpriteKit + Swift (Xcode 26, iOS 17+ deployment target)
- iOS (iPad, landscape) + Mac Catalyst, single shared target
- `GameController` framework for Bluetooth pads
- `AVAudioEngine` for procedural synth SFX
- All graphics drawn at runtime via `SKShapeNode` — no bundled image or audio assets

## Project layout

```
bashteroids/
├── docs/specs.md                  # Game design spec
├── Bashteroids.xcodeproj          # Xcode project (synchronized folder mode)
└── Bashteroids/
    ├── Info.plist                 # GameController flags, orientation
    ├── Assets.xcassets/           # AppIcon
    ├── App/                       # SwiftUI entry + SpriteView host + fullscreen toggle
    ├── Scenes/                    # Title, Game, GameOver, Game+Debug
    ├── Entities/                  # Ship, Asteroid, UFO, Alien, Mine, Rock, Snake, PowerUp, Bullet
    ├── Systems/                   # Movement, Collision, Spawner, LevelRoster
    ├── Input/                     # GameController + GCKeyboard discovery, per-player binding
    ├── Audio/                     # AVAudioEngine + synth SFX
    ├── Render/                    # CGPath builders for vector silhouettes
    └── Utils/                     # Vec, SeededGenerator, HighScore, DebugSettings
```

The `Bashteroids/` folder is registered as a `PBXFileSystemSynchronizedRootGroup`, so any file added under it is picked up automatically — no `project.pbxproj` edits are needed when adding sources.

## Build & run

### Mac Catalyst (no simulator runtime required)

```sh
xcodebuild -project Bashteroids.xcodeproj \
           -scheme Bashteroids \
           -destination 'platform=macOS,variant=Mac Catalyst' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Then either open the resulting `.app` from `~/Library/Developer/Xcode/DerivedData/Bashteroids-*/Build/Products/Debug-maccatalyst/`, or open the project in Xcode and run the `Bashteroids` scheme against `My Mac (Mac Catalyst)`.

### iPad simulator

Download an iOS simulator runtime first:

```sh
xcodebuild -downloadPlatform iOS
```

Then build & run from Xcode against an iPad simulator destination.

### Physical iPad

Open the project in Xcode, set your team in *Signing & Capabilities*, change the bundle identifier from `com.markus.Bashteroids` to something in your namespace, then run.

## Modes

Pick the mode and starting level on the title screen using the D-pad on any joined controller (or `M` and arrow up/down on a keyboard). Both selections persist between launches.

- **Survival** (default): the existing single-player or co-op mode against asteroids, UFOs, alien monsters, snakes, mines, and rocks. Score-based; a run lives in the leaderboard.
- **Battle** (2+ players required): last-ship-standing deathmatch. The arena is dotted with **strong walls** (warm gray, indestructible — bullets die, ships bounce off losing 50% of their normal-component velocity) and **weak walls** (warm orange, made of 4 chunks at 5 hp each — bullets erode them visually as they take damage). Ship-vs-ship rules from survival apply: shields absorb hits, otherwise contact kills both. No enemies spawn; powerups drip every 30-60s and vanish after 30s with a 5s fade if uncollected (60% shield, 20% dual-canon, 20% boost). Round ends when only one ship is left (or zero — that's a draw).

Levels 1–9 control how dense the spawn / wall set is. The default level is whatever level you last reached.

## Levels

Each game is structured as discrete levels. The roster for each level (count of asteroids, UFOs, aliens, mines, rocks, snakes, power-ups) lives in [`Bashteroids/Systems/LevelRoster.swift`](Bashteroids/Systems/LevelRoster.swift) — levels 1-6 are hand-picked, level 7+ uses a formula. A level is **complete** when every asteroid, UFO, alien monster and snake spawned for it has been destroyed.

Between levels the game shows a `LEVEL N` banner; ships flash for ≈1 s before play resumes, and ship-vs-ship collisions are disabled during the transition. The highest level reached is shown next to your name on the title-screen leaderboard, which keeps your top 10 runs.

## Entities

The screen is populated by a fixed cast. Entities that enter from off-screen are announced 3 seconds in advance by an **edge-glow warning** along the side they'll come from — the glow's colour tells you what's incoming.

| Entity     | Glow      | Health        | Behaviour                                                                                                                              | Score |
|------------|-----------|---------------|----------------------------------------------------------------------------------------------------------------------------------------|-------|
| **Ship**   | —         | 1 hit         | Player avatar. Thrust + turn + fire (+ brake when collected). Screen-wraps. Reload 2.0 s (1.33 s with dual-canon). Thrust shows an orange flame at the rear; collected power-ups show as small markers on the hull. | —     |
| **Asteroid** | white   | 1 bullet      | Irregular hollow polygon, drifts in a straight line, screen-wraps. Speed 80–160 px/s, radius 18–32 — set per spawn from a fixed range. Appears from level 1. | 1     |
| **UFO**    | red       | 1 bullet      | Flying saucer that sine-drifts across the screen at 140 px/s, fires aimed bullets at the nearest ship every 2.5–4.5 s. Screen-wraps. Joins from level 3. | 5     |
| **Alien monster** | purple | 2 bullets | Saucer with downward spikes. Same drift movement as a UFO, but its laser is short-range (≤ 140 px) and fires faster (every 2.0–3.5 s). Brief alpha flash on each non-killing hit. Screen-wraps. Joins from level 5. | 10    |
| **Snake**  | green     | 4 bullets     | Six-segment chain that homes on the nearest ship while sine-winding around its heading (max turn 1.4 rad/s, speed 90 px/s). Any segment is a valid hit-target — bullets, ramming, mine blasts and rocks all check the whole body. Screen-wraps. Joins from level 5. | 15    |
| **Mine**   | none      | 1 bullet (or auto) | Drops at a random interior point with no warning, flashes for 6 s, then explodes in a 140 px radius. Two zones: a **60 px inner kill zone** (shields don't save you) and a **60–140 px outer blast** (consumes a shield, kills if no shield). Player-laid mines (via the Minelayer powerup) follow the same zoning but auto-detonate after 60 s instead of 6 s, and can be remote-detonated by the placing player. Joins from level 4. | 5 (blast) |
| **Rock**   | orange    | **indestructible** | Solid filled polygon. Crosses the screen once in a straight line and despawns off the far edge. Anything it touches dies — asteroids, bullets, UFOs, aliens, snakes, power-ups, and ships. **Shields do not block a rock.** Triggers mines on contact. Joins from level 6. | —     |
| **Bullet** | —         | —             | Short laser projectile. Player bullets travel until they leave the play area. Alien-monster bullets expire after 140 px to keep their fire short-range. Bullets die on any hit.            | —     |
| **Other ship** (PvP) | — | 1 hit       | Treated as a target by other players' bullets and ramming. See **Power-ups → Shield** for shield-vs-shield rules.                       | 20    |
| **Wall (strong)** | — | indestructible | Warm-gray vector polygon. Absorbs all bullets. Ships bounce off, losing 50% of their normal-component velocity per bounce. Only spawns in BATTLE mode. | — |
| **Wall (weak)** | — | 5 hp × 4 chunks | Warm-orange vector polygon split into 4 wedges. Each chunk takes 5 bullet hits, eroding visually as it loses hp. Once a chunk hits 0 hp it vanishes; once all chunks are gone the wall is destroyed. Ships bounce as for strong walls (no chunk damage from the bounce). Only spawns in BATTLE mode. | — |

## Power-ups

Power-ups drip-feed alongside enemies starting from level 2, drift in slowly from a random edge, and are picked up by flying through them.

| Power-up   | Shape                                   | Effect                                                                                                                                                           |
|------------|-----------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Shield**     | Cyan hexagon                       | Ship gains a cyan ring. The next collision with an asteroid, UFO, alien monster, snake, or another ship destroys *that* offender and consumes the shield — the ship survives. Mine blasts also consume the shield instead of killing the ship. **Rocks bypass shields.** Stacks up to 2: a second shield pickup adds an outer ring; each absorbed hit drops one ring. |
| **Dual-canon** | Yellow parallel lines              | Reload drops from 2.0 s to 1.33 s. Bullets fire from alternating offsets ±4 px from the nose. Two short yellow bars appear at the front of the ship while active. Stays for the rest of the run. |
| **Boost**      | Orange double chevron `>>`         | Increases the ship's max velocity by ~43% (from 140 px/s to 200 px/s). A second pickup raises it again to 250 px/s; further pickups do nothing. Two small orange chevrons appear at the rear of the ship while equipped. Stays for the rest of the run. |
| **Minelayer**  | Spiked-circle silhouette           | Arms the ship to place one mine. Press **Y** (controller) or **M** (keyboard) to drop it at the ship's current position; press again to detonate it from anywhere. The placed mine also self-detonates after 60 s. The placing player is in the blast like anyone else. One-shot — pickup is consumed by the place/detonate cycle. Not available on Siri Remote (no spare button). |

## Controls

| Action  | Controller                                       | Keyboard          |
|---------|--------------------------------------------------|-------------------|
| Turn    | Left stick X / D-pad ←/→                         | ← / →             |
| Thrust  | A button / right trigger / right stick ↑         | ↑                 |
| Brake   | B button / right stick ↓                         | ↓                 |
| Fire    | X button / right shoulder / left trigger         | Space             |
| Minelayer | Y button *(needs minelayer pickup)* | M *(needs minelayer pickup)* |
| Join    | A button on Title screen                         | A                 |
| Start   | Start/Menu / X button                            | Space / Enter     |
| Exit fullscreen (Mac) | —                                      | Esc               |

One keyboard player can join alongside up to 3 controllers. Each player picks a name on the title screen after joining.

## Debug build extras

Builds run as **Debug** (`Product → Run` in Xcode, or `-configuration Debug` from `xcodebuild`) include a cheat panel that's stripped from Release:

- **In-game spawn-on-keystroke:**
  - `1` asteroid · `2` UFO · `3` mine · `4` rock · `5` alien monster · `6` snake
  - `Shift+1` shield · `Shift+2` dual-canon · `Shift+3` boost · `Shift+4` minelayer
  Entities spawn from a random screen edge with no warning glow; mines drop at a random interior point.
