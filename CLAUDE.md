# CLAUDE.md

Guidance for Claude Code when working in this repo.

## What this is

Bashteroids — a classic-vector Asteroids clone for iPad + Mac (Catalyst) + Apple TV, built with SpriteKit + Swift. See `specs.md` for the gameplay design and `README.md` for the project layout.

## Locked design decisions

These were settled during planning. Don't relitigate without asking.

- **Stack:** SpriteKit + Swift, single Xcode target, iOS 17+ / tvOS 17+ deployment, iPad with all four orientations declared (Apple is deprecating `UIRequiresFullScreen` and orientation-locking; gameplay is designed around landscape but the app no longer refuses portrait), Mac Catalyst enabled, tvOS enabled. No Android, no cross-platform engine.
- **Multiplayer:** Local couch co-op only, 1–4 players, each with their own Bluetooth controller. **No networking.**
- **Assets:** Mostly procedural. Graphics are `SKShapeNode` line primitives via `CGPath` (the title/help backdrops and tvOS app icon are PNGs in `Assets.xcassets`). All gameplay sound effects are synthesized with `AVAudioEngine` (oscillators + noise + ADSR) — do **not** add `.wav`/`.caf` SFX files. Background music *is* allowed as bundled `.m4a`/`.mp3` files in `Bashteroids/Audio/Resources/` and is played by `MusicPlayer` (separate from the synth `AudioEngine`).
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

## Title scene input model (intended behavior)

The title scene uses a single shared focus, navigable from any input device. **Don't change these semantics without asking** — they were settled after a few iterations and will surprise users if regressed.

**Focus layout:**
- Slot row (slot0–slot3) is at the top.
- Selector column (mode → level → density → audio → help) is on the right.
- Begin Game (start) sits at the bottom.

**Navigation:**
- D-pad / arrow keys.
- Slot row: down → start, up → mode. Left/right moves between tiles (clamped — slot0 left and slot3 right don't wrap), with one exception: slot3 right → audio (the rightmost slot is adjacent to the selector column visually).
- Selectors / help / start: left → slot 3 (P4). Up/down moves through the column. Right cycles selector value **only while in edit mode** (see below).
- mode-up returns to the slot you came from (`lastSlotFocusIndex`).

**Claim-keeps-stored-name:**
- Joining a slot does **not** auto-open the name editor. The slot keeps its previously stored name (or the `P\(idx+1)` default on first launch). To rename, the player must explicitly focus their own tile and press A (controller / keyboard) or long-press it (touch).
- The pre-October-2026 auto-open behavior was removed; don't restore it without asking.

**Modal selector editing:**
- A on a focused selector toggles edit mode (visual cue: arrows scale to 1.3×).
- While editing, left/right cycles the value; up/down is ignored; A exits.
- Edit mode is cleared automatically when focus leaves the selector to a slot.
- Touch is **direct manipulation** and bypasses edit mode: tapping arrows or swiping ≥30 pt over a selector tile cycles the value immediately.

**Controllers (claim / leave / edit name):**

| Action | Button | Required state |
|---|---|---|
| Claim slot | A | Controller unclaimed; focus on an empty slot tile (or the controller's `intendedSlot` is on one — d-pad keeps these aligned) |
| Edit name | A | Controller claimed; focus on **its own** slot tile |
| Leave slot | B | Controller claimed; MFi only — Siri Remote has no B |
| Toggle selector edit | A | Focus on mode/level/density/audio |
| Begin (focused) | A | Focus on Begin Game |
| Begin (shortcut) | X / Menu / Play-Pause | Anytime; Menu is MFi-only (Siri Remote's Menu is system-reserved) |
| Open help | A | Focus on Help |
| Confirm name | A | Name editor open |

**Important controller details:**
- A on a claimed controller does **not** auto-open the name editor — that was the old "dual-A handler" and was removed. The user must navigate focus to *their own* slot first.
- Unclaimed controllers' A is wired through `ControllerManager.installJoinHandler` (a `pressedChangedHandler` on `buttonA`). It claims at the controller's `intendedSlot`. The d-pad in `TitleScene.update` calls `syncIntendedSlot(controller:)` so `intendedSlot` tracks the focused slot whenever focus is on the slot row. If the user navigates focus *away* from the slot row before pressing A, the unclaimed controller still claims at the last-pinned `intendedSlot` — that's intentional (don't surprise the user by silently consuming an A press, and stale-but-empty intended slots are still valid claim targets).
- A press on a claimed controller's *own* slot tile opens the name editor; A press on someone else's claimed tile or an empty tile (when this controller is already claimed) is a no-op by design.
- Two unclaimed controllers connecting at once each get a different default `intendedSlot` (`assignDefaultIntent(for:)`) so their preview triangles don't pile on slot 0.
- Releasing a slot via B keeps `intendedSlot[id]` parked on the slot the player just left — so the preview triangle doesn't snap back to the leftmost (red) tile.

**Keyboard:**
- Arrow keys navigate focus.
- A / Enter / Keypad-Enter route through `confirmFocused()` (no controller arg), so the keyboard's "claim" / "edit name" path uses focus to pick the slot — `claimKeyboard(atSlot:)` was added specifically so Enter on a focused empty slot claims that exact tile.
- Space starts the game (or opens help if Help is focused).
- Esc currently exits Mac fullscreen on title; on game-over it returns to title.

**iPad touch:**
- Tap on an empty slot tile (and no touch player yet): claims for touch.
- Tap on the touch player's *own* slot tile: leaves it.
- Long-press (≥400 ms) on the touch player's own slot tile: opens the name editor. Long-press fires while still holding (Task-based, see `TitleTapCatcher` in `TouchHUDView.swift`) — the tap notification is suppressed if the long-press already fired. **Don't** re-implement long-press by classifying on `onEnded` only; that was the old behavior and felt sluggish.
- Horizontal swipe (≥30 pt) over a selector tile: cycles its value, regardless of focus / edit mode.
- The four overlay tap-catchers in `GameContainerView` are gated by `TouchOverlayState.shared` and only mount on iOS / Catalyst.

**Game-over input model:**
- During the score-reveal phase (non-NORMAL survival): any controller button or any key plays the reveal animation, advancing the state.
- After reveal: **A** (controller) / **R** (keyboard) replays. *Every other* controller button (X, Menu) and *every other* key returns to the title. Touch: tap-on-hint replays; tap-outside returns to title.

## Things to avoid

- **Don't** add a Podfile, Package.swift, Carthage config, or any third-party dependency manager. SpriteKit + AVFoundation + GameController cover everything.
- **Don't** restructure the project into multiple Swift packages or add a separate macOS AppKit target. One target, three destinations (iOS, Mac Catalyst, tvOS).
- **Don't** use `SKAction.playSoundFileNamed` for sound effects — those go through the synth in `Audio/`. Background music for menu scenes is the exception: it loads bundled files via `MusicPlayer.shared.play(resource:ext:)`.
- **Don't** introduce a HUD beyond what `specs.md` requires (no score display, no menus beyond Title/GameOver).
- **Don't** poll `microGamepad.buttonMenu` to start the game on tvOS — it's system-reserved (returns to home). Use `buttonX` (play/pause on second-gen+ Siri Remote).
