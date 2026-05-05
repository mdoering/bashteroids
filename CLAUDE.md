# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

Bashteroids — a classic-vector Asteroids clone for iPad + Mac (Catalyst), built with SpriteKit + Swift. See `specs.md` for the gameplay design and `README.md` for the project layout.

## Locked design decisions

These were settled during planning. Don't relitigate without asking.

- **Stack:** SpriteKit + Swift, single Xcode target, iOS 17+ deployment, iPad landscape only, Mac Catalyst enabled. No Android, no cross-platform engine.
- **Multiplayer:** Local couch co-op only, 1–4 players, each with their own Bluetooth controller. **No networking.**
- **Assets:** Fully procedural. Graphics are `SKShapeNode` line primitives via `CGPath`. Audio is synthesized with `AVAudioEngine` (oscillators + noise + ADSR). Do **not** add `.png`, `.wav`, `.caf`, etc. — there are no asset files.
- **Physics:** Custom integration in the `update(_:)` loop. Do **not** use `SKPhysicsBody` / SpriteKit's physics engine — screen-wrapping inertia and the precise collision rules are simpler with hand-rolled circle-vs-circle.

## Project structure conventions

The `Bashteroids/` folder is a `PBXFileSystemSynchronizedRootGroup`. **Any new `.swift` file dropped under it is auto-included in the build** — no `project.pbxproj` edits required. Keep the existing folder layout (`App/`, `Scenes/`, `Entities/`, `Systems/`, `Input/`, `Audio/`, `Render/`, `Utils/`) as new code is added.

`Info.plist` lives inside `Bashteroids/` but is excluded from the Resources build phase via a `PBXFileSystemSynchronizedBuildFileExceptionSet`. If you add other non-source files (configuration, etc.) that shouldn't be bundled as resources, extend that exception set.

## Build verification

Quick smoke test (no simulator runtime needed):

```sh
xcodebuild -project Bashteroids.xcodeproj \
           -scheme Bashteroids \
           -destination 'platform=macOS,variant=Mac Catalyst' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Should end with `** BUILD SUCCEEDED **` and zero warnings. Run this after any non-trivial change before claiming work is complete.

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

## Deferred work

- **tvOS support.** Confirmed as a good fit (controller-driven game, procedural assets scale to 4K) and easy to add — extend `SUPPORTED_PLATFORMS` with `appletvos appletvsimulator`, set `TVOS_DEPLOYMENT_TARGET`, change `TARGETED_DEVICE_FAMILY = "2,3"`, wrap iOS-only modifiers (`statusBarHidden`, `persistentSystemOverlays`) in `#if os(iOS)`, and add a Brand Assets icon set. Revisit **after** gameplay is working on iPad/Mac so we're not debugging three destinations at once.

## Things to avoid

- **Don't** add a Podfile, Package.swift, Carthage config, or any third-party dependency manager. SpriteKit + AVFoundation + GameController cover everything.
- **Don't** restructure the project into multiple Swift packages or add a separate macOS AppKit target. One target, two destinations (iOS + Catalyst).
- **Don't** use `SKAction.playSoundFileNamed` — there are no sound files. Audio goes through the synth in `Audio/`.
- **Don't** introduce a HUD beyond what `specs.md` requires (no score display, no menus beyond Title/GameOver).
