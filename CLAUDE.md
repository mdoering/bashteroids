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

The title scene has **no slot focus** — focus lives only on the right-side menu (mode → level → density → audio → help → Begin Game). Slots are claimed via a join flow that walks the player through color and name picking. **Don't change these semantics without asking** — they were settled after a few iterations and will surprise users if regressed.

**Focus + selectors (menu only):**
- Up/down navigates the menu column.
- Left/right *directly* cycles the focused selector's value (no edit mode, no `editingSelector` flag). Mode/level/density/audio cycle; help/start are no-ops on ◀▶.
- A on a fully-claimed-idle controller (or on the keyboard with a player already claimed) triggers the focused menu item — help opens help, start tries to begin, selectors are no-ops.
- X / Menu / Play-Pause: "begin game" shortcut from any state outside a mid-claim. (Menu is MFi-only — Siri Remote's Menu is system-reserved.)

**Slot tiles:**
- Unclaimed slots render with a grey ring and show the **stored name on top + `JOIN` below**, both in the muted grey. Names persist per slot index via `UserDefaults` key `player_name_<idx>`.
- A claimed slot's ring + ghost ship preview the slot's color. Claimed-idle slots also show the stored name in their color.

**Join flow (single A → color → name → idle):**
1. Unclaimed controller presses A → `ControllerManager.installJoinHandler` claims the leftmost-free slot. `TitleScene.onSlotsChanged` notices the new claim and calls `enterColorPicker(slot:)` → tile enters **pickColor phase**.
2. In pickColor: ◀▶ cycles candidate colors (skipping ones already locked by other claimed-idle / name-editing slots). A confirms the color (palette index persists to `UserDefaults` key `slot_color_<idx>`). Tile enters **nameEditing phase**.
3. In nameEditing: ↑↓ cycles live char, ◀▶ moves cursor, **X inserts the live char** (the role A used to have — A is now the universal "next/confirm" button so triple-A = quick-join with stored defaults), A/Y/Menu confirms the name. Tile becomes **claimed-idle**.
4. B at any phase releases the slot (back to unclaimed). Keyboard's Esc does the same for the keyboard player.

**Triple-A quick join:** three consecutive A presses claim the leftmost free slot, accept the remembered color, and accept the stored name. The X-as-insert mapping is what makes this possible — A is never the "type a character" button.

**Simultaneous claims:** multiple players can be mid-claim at the same time, each operating on their own tile independently. A controller's ◀▶ is routed to its own slot's phase if it's mid-claim; otherwise it cycles the right-side selectors. If two pickers land on the same color and one confirms, the other's candidate auto-advances silently to the next free color (`rebumpCandidatesAfterLock`), so the candidate is guaranteed free at confirm time.

**Color memory:** each slot remembers the palette index of its last confirmed color in `UserDefaults` (`slot_color_<idx>`). `enterColorPicker` uses that as the initial candidate if it's not currently locked, else falls back to the slot-index default, else the first non-locked color.

**Controllers (claim / leave / mid-claim):**

| Action | Button | Phase / state |
|---|---|---|
| Claim leftmost-free slot | A | Controller unclaimed (handled by `installJoinHandler`) |
| Cycle color candidate | ◀ / ▶ | Controller in pickColor on its own slot |
| Confirm color | A / X / Menu | Controller in pickColor on its own slot |
| Cycle live char | ↑ / ↓ | Controller in nameEditing on its own slot |
| Move cursor | ◀ / ▶ | Controller in nameEditing on its own slot |
| Insert live char | X | Controller in nameEditing on its own slot |
| Confirm name | A / Y / Menu | Controller in nameEditing on its own slot |
| Release slot | B | Controller claimed (any phase); MFi only — Siri Remote has no B |
| Cycle focused selector | ◀ / ▶ | Controller unclaimed OR claimed-idle |
| Move focus | ↑ / ↓ | Controller unclaimed OR claimed-idle |
| Begin (focused start) | A | Controller claimed-idle, focus on Begin Game |
| Begin (shortcut) | X / Menu / Play-Pause | Anyone not mid-claim |
| Open help | A | Controller claimed-idle, focus on Help |

**Important controller details:**
- Unclaimed controllers' A is wired through `ControllerManager.installJoinHandler` (a `pressedChangedHandler` on `buttonA`). It always claims the leftmost free slot (`intendedSlotIndex` falls back to `emptySlotIndices().first` when no intent has been pinned). After claim the handler is removed and the controller's A is read per-frame in `TitleScene.update`.
- `aWasPressed[id]` is updated unconditionally at the end of each frame so a held A across the unclaimed → claimed transition doesn't mis-fire on the first post-claim frame.
- In `didMove(to:)` all per-controller button state dicts (`aWasPressed`, `xWasPressed`, etc.) are seeded from the current held state — this prevents a held button across help → title or game-over → title transitions from firing a spurious rising edge.

**Keyboard:**
- Up/down: moveFocus. Left/right: cycleFocusedSelector.
- Space: tryStart.
- Enter / Keypad-Enter / A (when no keyboard player yet): `claimKeyboard()`; otherwise: confirmFocusedMenu.
- During keyboard player's pickColor: ◀▶ cycles candidate, Enter/A/Space confirm, **Esc / B** releases.
- During keyboard player's nameEditing: arrow keys (←/→ cursor, ↑/↓ char), letter / `.` / `-` / space directly type at cursor (including B-as-letter), Backspace deletes, Enter confirms, **Esc** releases.
- Claimed-idle: **Esc / B** releases the keyboard slot (mirrors the MFi controller's B "leave slot" binding). Esc with no keyboard player falls back to exiting Mac fullscreen.
- H opens help.

**iPad touch:**
- Tap on an empty slot tile (no touch player yet): claims for touch → enters pickColor.
- Tap on the touch player's *own* slot tile: releases.
- Horizontal swipe (≥30 pt) over a selector tile: cycles its value.
- During the touch player's nameEditing phase: the in-tile cycler touch button row (◀ ↑ ↓ ▶ ⏎ ✓) is rendered — ⏎ inserts the live char, ✓ confirms the name.
- Long-press is currently a no-op on the title scene (re-edits go through release + re-claim).
- The four overlay tap-catchers in `GameContainerView` are gated by `TouchOverlayState.shared` and only mount on iOS / Catalyst.

**Name entry — in-game character cycler (no native keyboards):**

There is no SwiftUI overlay and no system on-screen keyboard. All platforms use the in-tile cycler, plus hardware-keyboard typing as an additive shortcut wherever `GCKeyboard.coalesced != nil`.

- Alphabet: `A B C ... Z . - SPACE ⌫` (30 entries; backspace `⌫` at the end so reverse-cycling from `A` lands on it first).
- Buffer cap: 8 chars. At-cap commit of a regular char is silently a no-op.
- State is **per-slot** (`nameEditing: [Int: NameEditState]`) so multiple players can edit simultaneously.
- The live character is preserved across cursor moves and commits — three X presses on `⌫` delete three chars without re-cycling.

| Action | Controller / Siri Remote | Keyboard | Touch (own slot only) |
|---|---|---|---|
| Move cursor | D-pad ← / → | ← / → | Tap ◀ / ▶ |
| Cycle live char | D-pad ↑ / ↓ | ↑ / ↓ | Tap ↑ / ↓ |
| Insert live char (delete if `⌫`) | **X** | Letter / `.` / `-` / Space direct-types | Tap ⏎ |
| Confirm name | A / Y / Menu / Play-Pause | Enter | Tap ✓ |
| Release slot (cancel claim) | B | Esc | (release tile by tap on own slot) |
| Direct backspace (kbd) | — | Backspace deletes char before cursor | — |

Don't restore the SwiftUI overlay or `NameEntryCoordinator` without asking — they were deleted intentionally to unify the cross-platform UX.

**Game-over input model:**
- During the score-reveal phase (non-NORMAL survival): any controller button or any key plays the reveal animation, advancing the state.
- After reveal: **X / Menu / Play-Pause** (controller) / **R** (keyboard) replays — mirroring the title screen's universal "begin game" shortcut. *Every other* controller button (A, B, Y) and *every other* key returns to the title. Touch: tap-on-hint replays; tap-outside returns to title.

## Things to avoid

- **Don't** add a Podfile, Package.swift, Carthage config, or any third-party dependency manager. SpriteKit + AVFoundation + GameController cover everything.
- **Don't** restructure the project into multiple Swift packages or add a separate macOS AppKit target. One target, three destinations (iOS, Mac Catalyst, tvOS).
- **Don't** use `SKAction.playSoundFileNamed` for sound effects — those go through the synth in `Audio/`. Background music for menu scenes is the exception: it loads bundled files via `MusicPlayer.shared.play(resource:ext:)`.
- **Don't** introduce a HUD beyond what `specs.md` requires (no score display, no menus beyond Title/GameOver).
- **Don't** poll `microGamepad.buttonMenu` to start the game on tvOS — it's system-reserved (returns to home). Use `buttonX` (play/pause on second-gen+ Siri Remote).
