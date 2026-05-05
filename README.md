# Bashteroids

A classic-vector Asteroids-style arcade game for iPad and Mac, played with Bluetooth controllers. Single-player and local couch co-op for up to 4 players.

See [`specs.md`](specs.md) for the gameplay design.

## Stack

- SpriteKit + Swift (Xcode 26, iOS 17+ deployment target)
- iOS (iPad, landscape) + Mac Catalyst, single shared target
- `GameController` framework for Bluetooth pads
- `AVAudioEngine` for procedural synth SFX
- All graphics drawn at runtime via `SKShapeNode` — no bundled image or audio assets

## Project layout

```
bashteroids/
├── specs.md                       # Game design spec
├── Bashteroids.xcodeproj          # Xcode project (synchronized folder mode)
└── Bashteroids/
    ├── Info.plist                 # GameController flags, orientation
    ├── Assets.xcassets/           # AppIcon + AccentColor slots
    ├── App/                       # SwiftUI entry + SpriteView host
    ├── Scenes/                    # Title, Game, GameOver scenes
    ├── Entities/                  # Ship, Asteroid, UFO, Bullet (TBD)
    ├── Systems/                   # Movement, Collision, Spawner (TBD)
    ├── Input/                     # GameController discovery & per-player binding (TBD)
    ├── Audio/                     # AVAudioEngine + synth SFX (TBD)
    ├── Render/                    # CGPath builders for vector silhouettes (TBD)
    └── Utils/                     # Vec, Random helpers (TBD)
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

## Controls (planned)

| Action  | Default mapping              |
|---------|------------------------------|
| Turn    | Left stick X / D-pad ←/→     |
| Thrust  | Right trigger / A button     |
| Fire    | Right shoulder / X button    |
| Join    | A button on Title screen     |
| Start   | Start/Menu (host)            |

## Status

Skeleton stage — Xcode project + SwiftUI/SpriteKit scaffolding only. Title screen renders a placeholder; gameplay, input, audio, and entities are not yet implemented. See the implementation plan at `~/.claude/plans/plan-to-build-a-eventual-anchor.md`.
