# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

Bashteroids — a classic-vector Asteroids clone for iPad + Mac (Catalyst) + Apple TV, built with SpriteKit + Swift. See `specs.md` for the gameplay design and `README.md` for the project layout.

## Locked design decisions

These were settled during planning. Don't relitigate without asking.

- **Stack:** SpriteKit + Swift, single Xcode target, iOS 17+ / tvOS 17+ deployment, iPad with all four orientations declared (Apple is deprecating `UIRequiresFullScreen` and orientation-locking; gameplay is designed around landscape but the app no longer refuses portrait), Mac Catalyst enabled, tvOS enabled. No Android, no cross-platform engine.
- **Multiplayer:** Local couch co-op only, 1–4 players, each with their own Bluetooth controller. **No networking.**
- **Assets:** Fully procedural. Graphics are `SKShapeNode` line primitives via `CGPath`. Audio is synthesized with `AVAudioEngine` (oscillators + noise + ADSR). Do **not** add `.png`, `.wav`, `.caf`, etc. — there are no asset files.
- **Physics:** Custom integration in the `update(_:)` loop. Do **not** use `SKPhysicsBody` / SpriteKit's physics engine — screen-wrapping inertia and the precise collision rules are simpler with hand-rolled circle-vs-circle.

## Project structure conventions

The `Bashteroids/` folder is a `PBXFileSystemSynchronizedRootGroup`. **Any new `.swift` file dropped under it is auto-included in the build** — no `project.pbxproj` edits required. Keep the existing folder layout (`App/`, `Scenes/`, `Entities/`, `Systems/`, `Input/`, `Audio/`, `Render/`, `Utils/`) as new code is added.

`Info.plist` lives inside `Bashteroids/` but is excluded from the Resources build phase via a `PBXFileSystemSynchronizedBuildFileExceptionSet`. If you add other non-source files (configuration, etc.) that shouldn't be bundled as resources, extend that exception set.

## Build verification

Quick smoke test (no simulator runtime needed). All three destinations should pass before claiming any non-trivial change complete:

```sh
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
           -destination 'generic/platform=iOS' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
           -destination 'platform=macOS,variant=Mac Catalyst' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
           -destination 'generic/platform=tvOS' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Each should end with `** BUILD SUCCEEDED **` and zero warnings.

### Manual verification (tvOS-specific runtime checks)

The headless build does not exercise Siri Remote behavior or the SwiftUI text-entry overlay. After tvOS-touching changes, run on a tvOS simulator (or hardware) and confirm:

- Siri Remote can join → turn → thrust → fire → start a game (touch-surface click is fire; play/pause button starts)
- A second MFi controller can join alongside the Siri Remote
- Player-name entry pops the SwiftUI overlay with a focused text field and the system on-screen keyboard
- The focused app icon parallaxes correctly on the tvOS home screen

### Regenerating the tvOS app icon

The eight `AppIcon.brandassets` PNGs are committed, but if `icon.svg` changes, regenerate them with:

```sh
brew install librsvg imagemagick   # one-time
./scripts/render-tv-icons.sh
```

## Coding style

- Swift 5 language mode, but feel free to use Swift 6 features available in Xcode 26.
- Prefer `final class` for SpriteKit nodes/scenes; structs for plain value types (`Vec`, configs).
- Per-frame work goes through `SKScene.update(_ currentTime:)` → systems run in fixed order: Movement → Spawner → Collision.
- Keep allocations out of the per-frame path where reasonable; reuse `SKShapeNode`s rather than recreating them.
- No comments unless the *why* is non-obvious. Don't restate what well-named code already says.

## Implementation plan

The full step-by-step plan is at `~/.claude/plans/plan-to-build-a-eventual-anchor.md`. When picking up work, follow that order unless the user redirects:

1. ✅ Xcode project skeleton
2. Math & rendering primitives (`Utils/Vec.swift`, `Render/Shapes.swift`)
3. Entity layer (`Entities/`)
4. Systems (`Systems/`)
5. Input (`Input/`)
6. Audio (`Audio/`)
7. Scene flow (`Scenes/`)
8. Polish

## Things to avoid

- **Don't** add a Podfile, Package.swift, Carthage config, or any third-party dependency manager. SpriteKit + AVFoundation + GameController cover everything.
- **Don't** restructure the project into multiple Swift packages or add a separate macOS AppKit target. One target, three destinations (iOS, Mac Catalyst, tvOS).
- **Don't** use `SKAction.playSoundFileNamed` — there are no sound files. Audio goes through the synth in `Audio/`.
- **Don't** introduce a HUD beyond what `specs.md` requires (no score display, no menus beyond Title/GameOver).
- **Don't** poll `microGamepad.buttonMenu` to start the game on tvOS — it's system-reserved (returns to home). Use `buttonX` (play/pause on second-gen+ Siri Remote).
