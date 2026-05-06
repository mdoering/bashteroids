# tvOS Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Bashteroids as a first-class tvOS destination alongside iPad and Mac Catalyst, with Siri Remote support, native text entry on tvOS, and a layered Brand Assets app icon.

**Architecture:** Single Xcode target gains a third destination (`appletvos appletvsimulator`). Source-level changes are scoped narrowly: title-safe inset fix, a parallel `microGamepad` input path, a SwiftUI overlay for native text entry on tvOS only, and a new `Brand Assets.brandassets` asset entry. No multi-target restructuring.

**Tech Stack:** Swift 5, SpriteKit, SwiftUI, GameController.framework, AVFoundation, Xcode 26, `rsvg-convert` + ImageMagick for the icon-rendering script (one-time dev tooling; resulting PNGs are committed).

**Spec:** `docs/superpowers/specs/2026-05-07-tvos-support-design.md`

---

## File Structure

**Modified files:**
- `Bashteroids.xcodeproj/project.pbxproj` — extend `SUPPORTED_PLATFORMS`, add `TVOS_DEPLOYMENT_TARGET`, set `TARGETED_DEVICE_FAMILY = "2,3"`, add tvOS-only `ASSETCATALOG_COMPILER_BRANDASSETS_NAME`.
- `Bashteroids/Info.plist` — drop `LSRequiresIPhoneOS` and `UIRequiresFullScreen`.
- `Bashteroids/Audio/AudioEngine.swift` — widen `#if os(iOS)` to `#if os(iOS) || os(tvOS)`.
- `Bashteroids/Scenes/GameScene.swift` — `playBounds` uses all four safe-area insets.
- `Bashteroids/Input/ControllerManager.swift` — extend `installJoinHandler` to wire `microGamepad` when `extendedGamepad` is nil.
- `Bashteroids/Input/PlayerSlot.swift` — extend `snapshot()` and `installFireHandler()` for `microGamepad` controllers.
- `Bashteroids/App/GameContainerView.swift` — wrap the `SpriteView` in a `ZStack` with the name-entry overlay on tvOS.
- `Bashteroids/Scenes/TitleScene.swift` — on tvOS, route name entry through the coordinator instead of the inline keyboard editor.
- `CLAUDE.md` — add the tvOS smoke-build command and a manual verification checklist.

**New files:**
- `Bashteroids/Input/NameEntryCoordinator.swift` — `MainActor`-bound `ObservableObject` bridging scene → SwiftUI overlay (compiled on all platforms; the overlay path is just a no-op on iPad/Mac).
- `Bashteroids/App/NameEntryOverlay.swift` — tvOS-only SwiftUI view with a focused `TextField` (file body wrapped in `#if os(tvOS)`).
- `scripts/render-tv-icons.sh` — committed shell script that splits `icon.svg` into back/middle/front layers and renders the eight required PNGs.
- `Bashteroids/Assets.xcassets/Brand Assets.brandassets/` — new asset entry, with two `.imagestack` subdirs (each containing three `.imagestacklayer` subdirs and `Content.imageset`s) plus two `.imageset` top-shelf entries. Eight PNGs total, plus the `Contents.json` for each folder.

---

## Task 1: Build configuration

**Files:**
- Modify: `Bashteroids.xcodeproj/project.pbxproj`
- Modify: `Bashteroids/Info.plist`

This is task #1 because nothing else can be built against the tvOS SDK until the build system knows tvOS exists.

- [ ] **Step 1: Read project.pbxproj to find current build settings**

Run: `grep -n "SUPPORTED_PLATFORMS\|TARGETED_DEVICE_FAMILY\|IPHONEOS_DEPLOYMENT_TARGET" Bashteroids.xcodeproj/project.pbxproj`

You will see four configurations: the project-level Debug + Release (which hold `IPHONEOS_DEPLOYMENT_TARGET`, `MACOSX_DEPLOYMENT_TARGET`, `TARGETED_DEVICE_FAMILY = 2`) and the target-level Debug + Release (which hold `SUPPORTED_PLATFORMS` and another `TARGETED_DEVICE_FAMILY = 2`).

- [ ] **Step 2: Add `TVOS_DEPLOYMENT_TARGET` to the project-level Debug config**

Edit the project-level Debug config (the one that contains `MACOSX_DEPLOYMENT_TARGET = 15.0;`). Add `TVOS_DEPLOYMENT_TARGET = 17.0;` immediately after `MACOSX_DEPLOYMENT_TARGET`:

```diff
 				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
 				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
 				MACOSX_DEPLOYMENT_TARGET = 15.0;
+				TVOS_DEPLOYMENT_TARGET = 17.0;
 				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
```

Use the `Edit` tool with enough surrounding context to disambiguate Debug from Release (Debug has `MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;` immediately after the inserted line; Release has `MTL_ENABLE_DEBUG_INFO = NO;`).

- [ ] **Step 3: Add `TVOS_DEPLOYMENT_TARGET` to the project-level Release config**

Same insertion in the Release config — disambiguate by the trailing `MTL_ENABLE_DEBUG_INFO = NO;`:

```diff
 				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
 				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
 				MACOSX_DEPLOYMENT_TARGET = 15.0;
+				TVOS_DEPLOYMENT_TARGET = 17.0;
 				MTL_ENABLE_DEBUG_INFO = NO;
```

- [ ] **Step 4: Update `TARGETED_DEVICE_FAMILY` from `2` to `"2,3"` in both project-level configs**

There are two occurrences in the project-level configs (Debug + Release). Use `replace_all` only if both occurrences match exactly the same string. Otherwise use two separate edits with unique surrounding context. The change in each:

```diff
-				TARGETED_DEVICE_FAMILY = 2;
+				TARGETED_DEVICE_FAMILY = "2,3";
```

There are two more occurrences of `TARGETED_DEVICE_FAMILY = 2;` in the target-level configs — those are addressed in Step 6 below.

- [ ] **Step 5: Extend `SUPPORTED_PLATFORMS` in both target-level configs**

In each of the two target-level configs (the ones containing `SUPPORTS_MACCATALYST = YES`), change:

```diff
-				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
+				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx appletvos appletvsimulator";
```

Both occurrences are identical strings, so `replace_all` is safe.

- [ ] **Step 6: Update `TARGETED_DEVICE_FAMILY` in both target-level configs**

Same change as Step 4 but in the target-level configs:

```diff
-				TARGETED_DEVICE_FAMILY = 2;
+				TARGETED_DEVICE_FAMILY = "2,3";
```

After Steps 4 and 6, all four occurrences of `TARGETED_DEVICE_FAMILY = 2;` should be `TARGETED_DEVICE_FAMILY = "2,3";`. Verify with:

`grep "TARGETED_DEVICE_FAMILY" Bashteroids.xcodeproj/project.pbxproj`

Expected: four lines, each `TARGETED_DEVICE_FAMILY = "2,3";`.

- [ ] **Step 7: Add tvOS-only Brand Assets setting to both target-level configs**

In each target-level config, immediately after `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;`, add:

```diff
 				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
+				"ASSETCATALOG_COMPILER_BRANDASSETS_NAME[sdk=appletvos*]" = "Brand Assets";
 				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
```

The `[sdk=appletvos*]` qualifier means this only applies when building for tvOS. iPad and Mac builds keep using `AppIcon`. The asset itself is created in Task 5 — for now this just declares the setting. Until the asset exists, an `actool` warning may appear on tvOS builds; that's expected and goes away in Task 5.

- [ ] **Step 8: Drop `LSRequiresIPhoneOS` and `UIRequiresFullScreen` from Info.plist**

Edit `Bashteroids/Info.plist`. Remove both keys and their values:

```diff
-	<key>LSRequiresIPhoneOS</key>
-	<true/>
 	<key>UILaunchScreen</key>
 	<dict>
 		<key>UIColorName</key>
 		<string></string>
 	</dict>
-	<key>UIRequiresFullScreen</key>
-	<true/>
 	<key>UISupportedInterfaceOrientations</key>
```

`LSRequiresIPhoneOS` would block tvOS launch; `UIRequiresFullScreen` is a UIKit-only key and irrelevant on tvOS. Orientation arrays stay (tvOS ignores them; iPad still respects them).

- [ ] **Step 9: Smoke-build all three destinations**

Run all three:

```bash
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

Expected: each ends with `** BUILD SUCCEEDED **`. The tvOS build will likely fail at this point with errors in `AudioEngine.swift` (missing `AVAudioSession` configuration) or pass with warnings. If the tvOS build fails, that's expected — Task 2 fixes it. Capture the failure for the next task. iOS and Catalyst builds **must** succeed cleanly.

- [ ] **Step 10: Commit**

```bash
git add Bashteroids.xcodeproj/project.pbxproj Bashteroids/Info.plist
git commit -m "chore(build): add tvOS to SUPPORTED_PLATFORMS

Adds tvOS 17.0 deployment target, expands TARGETED_DEVICE_FAMILY
to iPad+tvOS, declares the Brand Assets icon for tvOS only, and
removes the iPhone-only Info.plist keys that would block tvOS
launch."
```

---

## Task 2: Source-level platform guards

**Files:**
- Modify: `Bashteroids/Audio/AudioEngine.swift`
- Modify: `Bashteroids/Scenes/GameScene.swift`

- [ ] **Step 1: Widen the AudioEngine session guard to include tvOS**

In `Bashteroids/Audio/AudioEngine.swift`, the `configureSession` method currently has:

```swift
    private func configureSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioEngine: session configure failed: \(error)")
        }
        #endif
    }
```

Change `#if os(iOS)` to `#if os(iOS) || os(tvOS)`:

```swift
    private func configureSession() {
        #if os(iOS) || os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioEngine: session configure failed: \(error)")
        }
        #endif
    }
```

`AVAudioSession` exists on tvOS, and the `.ambient` category lets game audio mix politely with whatever the user was watching.

- [ ] **Step 2: Make `playBounds` respect all four safe-area insets**

In `Bashteroids/Scenes/GameScene.swift`, replace the existing `topSafeInset`/`playBounds` block (around line 41–47):

```swift
    private var topSafeInset: CGFloat { view?.safeAreaInsets.top ?? 0 }

    var playBounds: CGRect {
        CGRect(x: 0, y: 0,
               width: size.width,
               height: size.height - topSafeInset - Self.hudHeight)
    }
```

With:

```swift
    private var safeInsets: UIEdgeInsets { view?.safeAreaInsets ?? .zero }

    var playBounds: CGRect {
        let insets = safeInsets
        return CGRect(
            x: insets.left,
            y: insets.bottom,
            width: size.width - insets.left - insets.right,
            height: size.height - insets.top - insets.bottom - Self.hudHeight
        )
    }
```

This keeps the playfield inside the title-safe rect on tvOS (~60pt top/bottom, ~80pt left/right). On iPad and Mac the unused insets are 0 (or 21pt for the bottom home indicator on iPad, which is title-safe behavior we want anyway).

- [ ] **Step 3: Update `repositionHUD` and any other uses of `topSafeInset`**

Run: `grep -n "topSafeInset" Bashteroids/Scenes/GameScene.swift`

For each remaining reference, change `topSafeInset` to `safeInsets.top`. If `topSafeInset` no longer has any callers after Step 2, delete the (now removed) property — the replacement above already drops it.

Also check `Bashteroids/Scenes/GameScene+Debug.swift`:

`grep -n "topSafeInset\|safeAreaInsets" Bashteroids/Scenes/GameScene+Debug.swift`

If anything there references `topSafeInset`, update it to `safeInsets.top` (or `view?.safeAreaInsets.top ?? 0` if `safeInsets` isn't accessible).

- [ ] **Step 4: Smoke-build all three destinations**

```bash
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

Expected: all three end with `** BUILD SUCCEEDED **` and **zero warnings**. If tvOS still fails with a Swift compile error, read the full output and fix the smallest thing that addresses it before moving on. The most likely remaining issue is something using `UIScreen` or another iPhone-only API; if so, gate it with `#if os(iOS)` or use the equivalent tvOS API.

- [ ] **Step 5: Commit**

```bash
git add Bashteroids/Audio/AudioEngine.swift Bashteroids/Scenes/GameScene.swift Bashteroids/Scenes/GameScene+Debug.swift
git commit -m "fix: respect title-safe insets on all sides; enable AVAudioSession on tvOS

Play bounds now subtract all four safe-area insets so gameplay
stays inside tvOS overscan margins. Audio session category is
configured on tvOS the same way as iOS so game audio mixes
politely."
```

---

## Task 3: Siri Remote microGamepad input

**Files:**
- Modify: `Bashteroids/Input/ControllerManager.swift`
- Modify: `Bashteroids/Input/PlayerSlot.swift`

- [ ] **Step 1: Configure the `microGamepad` profile when a Siri Remote connects**

In `Bashteroids/Input/ControllerManager.swift`, add a call to a new `configureMicroGamepad(_:)` helper inside `wireSystemHandlers`. Replace the existing body:

```swift
    private func wireSystemHandlers(_ controller: GCController) {
        // Menu/Start is polled per-frame by TitleScene/GameOverScene rather
        // than wired through pressedChangedHandler. The handler-based path
        // turned out to be unreliable across fullscreen transitions.
    }
```

with:

```swift
    private func wireSystemHandlers(_ controller: GCController) {
        // Menu/Start is polled per-frame by TitleScene/GameOverScene rather
        // than wired through pressedChangedHandler. The handler-based path
        // turned out to be unreliable across fullscreen transitions.
        configureMicroGamepad(controller)
    }

    private func configureMicroGamepad(_ controller: GCController) {
        guard let mg = controller.microGamepad else { return }
        mg.reportsAbsoluteDpadValues = true
        mg.allowsRotation = false
    }
```

`reportsAbsoluteDpadValues` makes the touch surface report absolute position rather than relative deltas — much closer to a 4-way d-pad. `allowsRotation` keeps axes aligned with the device regardless of how the user holds the remote.

- [ ] **Step 2: Wire the join handler for `microGamepad`-only controllers**

In the same file, replace the `installJoinHandler` body:

```swift
    private func installJoinHandler(_ controller: GCController) {
        guard let gp = controller.extendedGamepad else { return }
        if joinEnabled && slot(for: controller) == nil {
            gp.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed, let self else { return }
                self.claim(controller: controller)
            }
        } else {
            gp.buttonA.pressedChangedHandler = nil
        }
    }
```

with:

```swift
    private func installJoinHandler(_ controller: GCController) {
        if let gp = controller.extendedGamepad {
            if joinEnabled && slot(for: controller) == nil {
                gp.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                    guard pressed, let self else { return }
                    self.claim(controller: controller)
                }
            } else {
                gp.buttonA.pressedChangedHandler = nil
            }
            return
        }

        if let mg = controller.microGamepad {
            if joinEnabled && slot(for: controller) == nil {
                mg.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                    guard pressed, let self else { return }
                    self.claim(controller: controller)
                }
            } else {
                mg.buttonA.pressedChangedHandler = nil
            }
        }
    }
```

A controller has either `extendedGamepad` (MFi) **or** `microGamepad` (Siri Remote) — never both meaningfully — so the `if/return / if` shape covers both cases without double-wiring.

- [ ] **Step 3: Add `microGamepad` snapshot path to `PlayerSlot`**

In `Bashteroids/Input/PlayerSlot.swift`, replace the `snapshot()` method:

```swift
    func snapshot() -> PlayerInput {
        if let kb = keyboard { return kb.snapshot() }

        let edge = firePressedEdge
        firePressedEdge = false

        guard let gp = controller?.extendedGamepad else {
            return PlayerInput(turn: 0, thrust: false, brake: false, firePressedThisFrame: edge)
        }

        var turn = CGFloat(gp.leftThumbstick.xAxis.value)
        if abs(turn) < 0.15 {
            turn = CGFloat(gp.dpad.xAxis.value)
        }
        turn = max(-1, min(1, turn))

        let stickY = CGFloat(gp.rightThumbstick.yAxis.value)
        let thrust = gp.buttonA.isPressed || gp.rightTrigger.value > 0.2 || stickY > 0.2
        let brake  = gp.buttonB.isPressed || stickY < -0.2

        return PlayerInput(turn: turn, thrust: thrust, brake: brake, firePressedThisFrame: edge)
    }
```

with:

```swift
    func snapshot() -> PlayerInput {
        if let kb = keyboard { return kb.snapshot() }

        let edge = firePressedEdge
        firePressedEdge = false

        if let gp = controller?.extendedGamepad {
            var turn = CGFloat(gp.leftThumbstick.xAxis.value)
            if abs(turn) < 0.15 {
                turn = CGFloat(gp.dpad.xAxis.value)
            }
            turn = max(-1, min(1, turn))

            let stickY = CGFloat(gp.rightThumbstick.yAxis.value)
            let thrust = gp.buttonA.isPressed || gp.rightTrigger.value > 0.2 || stickY > 0.2
            let brake  = gp.buttonB.isPressed || stickY < -0.2

            return PlayerInput(turn: turn, thrust: thrust, brake: brake, firePressedThisFrame: edge)
        }

        if let mg = controller?.microGamepad {
            let turn = max(-1, min(1, CGFloat(mg.dpad.xAxis.value)))
            let thrust = mg.dpad.yAxis.value > 0.2
            let brake  = mg.dpad.yAxis.value < -0.2
            return PlayerInput(turn: turn, thrust: thrust, brake: brake, firePressedThisFrame: edge)
        }

        return PlayerInput(turn: 0, thrust: false, brake: false, firePressedThisFrame: edge)
    }
```

The Siri Remote has no thumbsticks, no triggers, no `buttonB`. Turning maps to the d-pad x-axis; thrust/brake map to d-pad y-axis. Fire is handled via the edge-triggered handler (next step).

- [ ] **Step 4: Wire fire handler for `microGamepad`**

In the same file, replace `installFireHandler()`:

```swift
    private func installFireHandler() {
        guard let gp = controller?.extendedGamepad else { return }
        let handler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.firePressedEdge = true }
        }
        gp.buttonX.pressedChangedHandler = handler
        gp.rightShoulder.pressedChangedHandler = handler
        gp.leftTrigger.pressedChangedHandler = handler
    }
```

with:

```swift
    private func installFireHandler() {
        let handler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.firePressedEdge = true }
        }
        if let gp = controller?.extendedGamepad {
            gp.buttonX.pressedChangedHandler = handler
            gp.rightShoulder.pressedChangedHandler = handler
            gp.leftTrigger.pressedChangedHandler = handler
            return
        }
        if let mg = controller?.microGamepad {
            // Siri Remote: the touch-surface click is buttonA. We use it for
            // both join (during title) and fire (in-game). Join already runs
            // through ControllerManager; the same press also sets the edge
            // here, which is harmless before the slot is committed and
            // correct once it is.
            mg.buttonA.pressedChangedHandler = handler
        }
    }
```

And `removeFireHandler()`:

```swift
    private func removeFireHandler() {
        guard let gp = controller?.extendedGamepad else { return }
        gp.buttonX.pressedChangedHandler = nil
        gp.rightShoulder.pressedChangedHandler = nil
        gp.leftTrigger.pressedChangedHandler = nil
    }
```

becomes:

```swift
    private func removeFireHandler() {
        if let gp = controller?.extendedGamepad {
            gp.buttonX.pressedChangedHandler = nil
            gp.rightShoulder.pressedChangedHandler = nil
            gp.leftTrigger.pressedChangedHandler = nil
            return
        }
        if let mg = controller?.microGamepad {
            mg.buttonA.pressedChangedHandler = nil
        }
    }
```

Note: there is intentional overlap between the join handler (set by `ControllerManager.installJoinHandler` on the Siri Remote's `mg.buttonA`) and the fire handler (set by `PlayerSlot.installFireHandler` on the same button). When `claim(controller:)` runs from the join press, it constructs a `PlayerSlot`, whose `init` calls `installFireHandler()` which overwrites the join handler with the fire handler. From that point onward `buttonA` fires bullets. That's the correct lifecycle.

- [ ] **Step 5: Update the start/menu polling in TitleScene to also check microGamepad**

In `Bashteroids/Scenes/TitleScene.swift`, the `update(_:)` method polls `extendedGamepad?.buttonMenu` and `extendedGamepad?.buttonX`. Add fallbacks for `microGamepad`. Replace this block:

```swift
        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)

            let menuPressed = c.extendedGamepad?.buttonMenu.isPressed ?? false
            let menuWas = menuWasPressed[id] ?? false
            if menuPressed && !menuWas { tryStart(); break }
            menuWasPressed[id] = menuPressed

            let xPressed = c.extendedGamepad?.buttonX.isPressed ?? false
            let xWas = xWasPressed[id] ?? false
            if xPressed && !xWas { tryStart(); break }
            xWasPressed[id] = xPressed
        }
```

with:

```swift
        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)

            let menuPressed = c.extendedGamepad?.buttonMenu.isPressed
                ?? c.microGamepad?.buttonMenu.isPressed
                ?? false
            let menuWas = menuWasPressed[id] ?? false
            if menuPressed && !menuWas { tryStart(); break }
            menuWasPressed[id] = menuPressed

            let xPressed = c.extendedGamepad?.buttonX.isPressed
                ?? c.microGamepad?.buttonX.isPressed
                ?? false
            let xWas = xWasPressed[id] ?? false
            if xPressed && !xWas { tryStart(); break }
            xWasPressed[id] = xPressed
        }
```

`microGamepad.buttonMenu` is the Siri Remote's Menu button; `microGamepad.buttonX` is the play/pause button on the second-gen+ Siri Remote (returns `nil`/`false` on the first-gen). Either lets the user start the game once they've joined.

Also update the per-slot "press A to begin name entry" loop higher in `update(_:)` to read from `microGamepad?.buttonA` as a fallback. Replace:

```swift
                let pressed = slot.controller?.extendedGamepad?.buttonA.isPressed ?? false
```

with (both occurrences in the same method):

```swift
                let pressed = slot.controller?.extendedGamepad?.buttonA.isPressed
                    ?? slot.controller?.microGamepad?.buttonA.isPressed
                    ?? false
```

- [ ] **Step 6: Smoke-build all three destinations**

```bash
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

Expected: all three `** BUILD SUCCEEDED **` with zero warnings.

- [ ] **Step 7: Commit**

```bash
git add Bashteroids/Input/ControllerManager.swift Bashteroids/Input/PlayerSlot.swift Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(input): support Siri Remote via microGamepad profile

Siri Remote claims a player slot like any MFi controller: d-pad
turns and thrusts/brakes, touch-surface click fires, Menu starts.
allowsRotation is disabled and reportsAbsoluteDpadValues is on
so the touch surface acts as a 4-way d-pad rather than a tilted
analog axis."
```

---

## Task 4: Name-entry coordinator and tvOS overlay

**Files:**
- Create: `Bashteroids/Input/NameEntryCoordinator.swift`
- Create: `Bashteroids/App/NameEntryOverlay.swift`
- Modify: `Bashteroids/App/GameContainerView.swift`
- Modify: `Bashteroids/Scenes/TitleScene.swift`

The name-entry inline editor uses keyboard input. Apple TV users typically don't have one. This task adds a SwiftUI overlay (focused `TextField` with the system on-screen keyboard) that's only shown on tvOS, driven by an `ObservableObject` coordinator.

- [ ] **Step 1: Create `NameEntryCoordinator.swift`**

Create the file with:

```swift
import Foundation
import Combine

@MainActor
final class NameEntryCoordinator: ObservableObject {
    static let shared = NameEntryCoordinator()

    struct Request: Identifiable {
        let id = UUID()
        let slot: Int
        let current: String
        let completion: (String?) -> Void
    }

    @Published private(set) var request: Request?

    func requestName(forSlot slot: Int, current: String,
                     completion: @escaping (String?) -> Void) {
        request = Request(slot: slot, current: current, completion: completion)
    }

    func submit(_ name: String) {
        let req = request
        request = nil
        req?.completion(name)
    }

    func cancel() {
        let req = request
        request = nil
        req?.completion(nil)
    }
}
```

The coordinator compiles on all platforms — only the *use* of it is platform-gated (the overlay view is tvOS-only; iPad/Mac never call `requestName(...)`).

- [ ] **Step 2: Create `NameEntryOverlay.swift`**

Create the file with:

```swift
#if os(tvOS)
import SwiftUI

struct NameEntryOverlay: View {
    @ObservedObject var coordinator: NameEntryCoordinator
    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 40) {
                Text("PLAYER \((coordinator.request?.slot ?? 0) + 1) NAME")
                    .font(.system(size: 36, weight: .bold, design: .default))
                    .foregroundStyle(.white)

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .focused($focused)
                    .onSubmit { submit() }

                HStack(spacing: 24) {
                    Button("Cancel") { coordinator.cancel() }
                    Button("Done") { submit() }
                }
                .font(.system(size: 28, weight: .semibold))
            }
            .padding(60)
        }
        .onAppear {
            name = coordinator.request?.current ?? ""
            focused = true
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let final = trimmed.isEmpty ? (coordinator.request?.current ?? "") : trimmed
        coordinator.submit(String(final.prefix(8)))
    }
}
#endif
```

The eight-character cap matches the inline editor's behavior. Trimming-to-empty falls back to the current name, also matching the inline editor.

- [ ] **Step 3: Wire the overlay into `GameContainerView`**

In `Bashteroids/App/GameContainerView.swift`, replace the existing `body`:

```swift
struct GameContainerView: View {
    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: makeScene(size: proxy.size),
                preferredFramesPerSecond: 60,
                options: [.ignoresSiblingOrder]
            )
        }
        .background(.black)
        .onAppear { MacFullScreen.enterIfNeeded() }
    }
```

with:

```swift
struct GameContainerView: View {
    @StateObject private var nameEntry = NameEntryCoordinator.shared

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                SpriteView(
                    scene: makeScene(size: proxy.size),
                    preferredFramesPerSecond: 60,
                    options: [.ignoresSiblingOrder]
                )
            }
            .background(.black)

            #if os(tvOS)
            if nameEntry.request != nil {
                NameEntryOverlay(coordinator: nameEntry)
            }
            #endif
        }
        .onAppear { MacFullScreen.enterIfNeeded() }
    }
```

`@StateObject private var nameEntry = NameEntryCoordinator.shared` binds the singleton to SwiftUI's lifecycle; `@Published` changes on `request` automatically re-render the `ZStack`.

- [ ] **Step 4: Route name entry through the coordinator on tvOS in `TitleScene`**

In `Bashteroids/Scenes/TitleScene.swift`, locate the `manager.onSlotsChanged` closure (around lines 76–88). Replace the entire closure body:

```swift
        manager.onSlotsChanged = { [weak self] in
            guard let self else { return }
            let newCount = self.manager.slots.count
            if newCount > self.prevSlotCount {
                let idx = newCount - 1
                self.activeNameSlot = idx
                self.nameBuffer = UserDefaults.standard.string(
                    forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
                self.manager.setJoinEnabled(false)
            }
            self.prevSlotCount = newCount
            self.renderSlots()
        }
```

with:

```swift
        manager.onSlotsChanged = { [weak self] in
            guard let self else { return }
            let newCount = self.manager.slots.count
            if newCount > self.prevSlotCount {
                let idx = newCount - 1
                let current = UserDefaults.standard.string(
                    forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
                #if os(tvOS)
                self.manager.setJoinEnabled(false)
                NameEntryCoordinator.shared.requestName(forSlot: idx, current: current) { [weak self] name in
                    guard let self else { return }
                    let final = name?.trimmingCharacters(in: .whitespaces).nonEmpty ?? current
                    UserDefaults.standard.set(final, forKey: "player_name_\(idx)")
                    let atMax = self.manager.slots.count >= ControllerManager.maxPlayers
                    self.manager.setJoinEnabled(!atMax)
                    self.renderSlots()
                }
                #else
                self.activeNameSlot = idx
                self.nameBuffer = current
                self.manager.setJoinEnabled(false)
                #endif
            }
            self.prevSlotCount = newCount
            self.renderSlots()
        }
```

- [ ] **Step 5: Add the `nonEmpty` helper used in Step 4**

Append to the bottom of `TitleScene.swift` (or to a `Utils/StringExtensions.swift` if you'd prefer; this plan keeps it inline to avoid creating extra files):

```swift
private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
```

- [ ] **Step 6: Smoke-build all three destinations**

```bash
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

Expected: all three `** BUILD SUCCEEDED **` with zero warnings.

- [ ] **Step 7: Commit**

```bash
git add Bashteroids/Input/NameEntryCoordinator.swift \
        Bashteroids/App/NameEntryOverlay.swift \
        Bashteroids/App/GameContainerView.swift \
        Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(tvos): native text-entry overlay for player names

When a player joins on tvOS the title scene routes name entry
through a NameEntryCoordinator, which surfaces a SwiftUI overlay
above the SpriteView with a focused TextField — tvOS auto-presents
the on-screen keyboard. iPad and Mac keep the existing inline
keyboard editor path."
```

---

## Task 5: App icon Brand Assets (layered + top-shelf)

**Files:**
- Create: `scripts/render-tv-icons.sh`
- Create: `Bashteroids/Assets.xcassets/Brand Assets.brandassets/` and all subdirs/files (eight PNGs + many `Contents.json`)

This task generates a layered tvOS app icon by splitting `icon.svg` into back/middle/front, plus two flat top-shelf images with a wordmark. Requires `librsvg` and `imagemagick` (one-time install).

- [ ] **Step 1: Install rendering tools**

```bash
brew install librsvg imagemagick
```

If Homebrew is not installed, install it first per `https://brew.sh/`. The PNGs are committed after generation, so this is a one-time per-machine cost.

Verify:

```bash
which rsvg-convert magick
```

Expected: both resolve to a Homebrew path.

- [ ] **Step 2: Create the `scripts/render-tv-icons.sh` script**

Create the directory if needed and write the script. Make it executable.

```bash
mkdir -p scripts
```

Write `scripts/render-tv-icons.sh` with the following content:

```bash
#!/usr/bin/env bash
# Renders the tvOS Brand Assets icon set from icon.svg.
# Splits the source SVG into back / middle / front layers and
# generates the eight PNGs the asset catalog needs. Run once
# whenever icon.svg changes; the output PNGs are committed.
#
# Requires: rsvg-convert (brew install librsvg)
#           magick      (brew install imagemagick)

set -euo pipefail

cd "$(dirname "$0")/.."

ASSET_ROOT="Bashteroids/Assets.xcassets/Brand Assets.brandassets"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Source layer SVGs share viewBox 0 0 200 200 (matches icon.svg).
# We render each at 768x768 then pad to 1280x768 (or 240x240 → 400x240).

cat > "$TMP/back.svg" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="100%" height="100%" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <rect x="0" y="0" width="200" height="200" style="fill:#030508;"/>
  <g opacity="0.55">
    <circle cx="24" cy="22" r="1" fill="#fff"/>
    <circle cx="30" cy="168" r="0.8" fill="#fff"/>
    <circle cx="12" cy="95" r="0.8" fill="#fff"/>
    <circle cx="180" cy="170" r="1" fill="#fff"/>
    <circle cx="186" cy="115" r="0.7" fill="#fff"/>
    <circle cx="95" cy="186" r="0.8" fill="#fff"/>
    <circle cx="85" cy="99" r="0.7" fill="#fff"/>
    <circle cx="22" cy="140" r="0.6" fill="#fff"/>
  </g>
</svg>
EOF

cat > "$TMP/middle.svg" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="100%" height="100%" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <g>
    <path d="M37,43l10,-20l20,-2l18,12l2,22l-14,16l-26,-4l-10,-24Z"
          fill="none" stroke="#fff" stroke-width="2.5"/>
    <circle cx="65" cy="43" r="8" fill="none" stroke="#fff" stroke-opacity="0.45" stroke-width="1.5"/>
  </g>
</svg>
EOF

cat > "$TMP/front.svg" <<'EOF'
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg width="100%" height="100%" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
  <g>
    <path d="M88.493,130.731l-30.07,29.543l2.705,-11.903l-4.532,-11.111l-10.258,-6.616l42.154,0.087Z"
          fill="none" stroke="#f33" stroke-width="2.8" stroke-linecap="round"/>
  </g>
  <g>
    <path d="M125.818,97.634l42.144,0.921l-10.413,6.369l-4.796,11l2.42,11.964l-29.355,-30.254Z"
          fill="none" stroke="#4af" stroke-width="2.8" stroke-linecap="round"/>
    <path d="M110.47,90.797l3.544,1.577"
          fill="none" stroke="#4af" stroke-width="2.8" stroke-linecap="round"/>
  </g>
</svg>
EOF

render_layered() {
    local layer="$1"   # back|middle|front
    local outdir="$2"  # asset directory
    local large_w="$3" # 1280
    local large_h="$4" # 768
    local small_w="$5" # 400
    local small_h="$6" # 240

    local large_imgset="$ASSET_ROOT/App Icon - App Store.imagestack/${layer^}.imagestacklayer/Content.imageset"
    local small_imgset="$ASSET_ROOT/App Icon.imagestack/${layer^}.imagestacklayer/Content.imageset"

    # Render the source square at the icon's height, then pad to wide canvas.
    rsvg-convert -h "$large_h" "$TMP/$layer.svg" -o "$TMP/${layer}-large.png"
    magick "$TMP/${layer}-large.png" -background none -gravity center \
        -extent "${large_w}x${large_h}" "$large_imgset/${layer}.png"

    rsvg-convert -h "$small_h" "$TMP/$layer.svg" -o "$TMP/${layer}-small.png"
    magick "$TMP/${layer}-small.png" -background none -gravity center \
        -extent "${small_w}x${small_h}" "$small_imgset/${layer}.png"
}

render_layered back   "$ASSET_ROOT" 1280 768 400 240
render_layered middle "$ASSET_ROOT" 1280 768 400 240
render_layered front  "$ASSET_ROOT" 1280 768 400 240

# Top-shelf flat composite: icon (square) on the left, wordmark on the right.
render_topshelf() {
    local out="$1"
    local w="$2"
    local h="$3"

    # Render each layer at top-shelf height, composite, then add wordmark.
    rsvg-convert -h "$h" "$TMP/back.svg"   -o "$TMP/ts-back.png"
    rsvg-convert -h "$h" "$TMP/middle.svg" -o "$TMP/ts-middle.png"
    rsvg-convert -h "$h" "$TMP/front.svg"  -o "$TMP/ts-front.png"

    magick -size "${w}x${h}" xc:"#030508" \
        "$TMP/ts-back.png"   -gravity West -geometry +60+0 -composite \
        "$TMP/ts-middle.png" -gravity West -geometry +60+0 -composite \
        "$TMP/ts-front.png"  -gravity West -geometry +60+0 -composite \
        -font "Helvetica-Bold" -pointsize 110 -fill white \
        -gravity West -annotate +800+0 "BASHTEROIDS" \
        "$out"
}

render_topshelf "$ASSET_ROOT/Top Shelf Image.imageset/topshelf.png"      1920 720
render_topshelf "$ASSET_ROOT/Top Shelf Image Wide.imageset/topshelf.png" 2320 720

echo "Rendered Brand Assets PNGs."
```

Then make it executable:

```bash
chmod +x scripts/render-tv-icons.sh
```

- [ ] **Step 3: Create the asset catalog directory tree and `Contents.json` files**

Create every directory the script writes into:

```bash
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets"
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets/App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset"
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets/App Icon - App Store.imagestack/Middle.imagestacklayer/Content.imageset"
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset"
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets/App Icon.imagestack/Back.imagestacklayer/Content.imageset"
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets/App Icon.imagestack/Middle.imagestacklayer/Content.imageset"
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets/App Icon.imagestack/Front.imagestacklayer/Content.imageset"
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets/Top Shelf Image.imageset"
mkdir -p "Bashteroids/Assets.xcassets/Brand Assets.brandassets/Top Shelf Image Wide.imageset"
```

Write each of the following `Contents.json` files. All paths are under `Bashteroids/Assets.xcassets/Brand Assets.brandassets/`.

`Contents.json` (root of brandassets):

```json
{
  "assets" : [
    {
      "filename" : "App Icon.imagestack",
      "idiom" : "tv",
      "role" : "primary-app-icon",
      "size" : "400x240"
    },
    {
      "filename" : "App Icon - App Store.imagestack",
      "idiom" : "tv",
      "role" : "primary-app-icon",
      "size" : "1280x768"
    },
    {
      "filename" : "Top Shelf Image.imageset",
      "idiom" : "tv",
      "role" : "top-shelf-image",
      "size" : "1920x720"
    },
    {
      "filename" : "Top Shelf Image Wide.imageset",
      "idiom" : "tv",
      "role" : "top-shelf-image-wide",
      "size" : "2320x720"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`App Icon - App Store.imagestack/Contents.json` (and identical content in `App Icon.imagestack/Contents.json`):

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "layers" : [
    { "filename" : "Front.imagestacklayer" },
    { "filename" : "Middle.imagestacklayer" },
    { "filename" : "Back.imagestacklayer" }
  ]
}
```

For each of the six `*.imagestacklayer/Contents.json` files (Back/Middle/Front in each of the two imagestacks):

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

For each `Content.imageset/Contents.json` inside the App Icon - App Store imagestack (large), where `<layer>` is `back`, `middle`, or `front`:

```json
{
  "images" : [
    {
      "filename" : "<layer>.png",
      "idiom" : "tv-marketing"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

For each `Content.imageset/Contents.json` inside the small App Icon imagestack (same `<layer>` values):

```json
{
  "images" : [
    {
      "filename" : "<layer>.png",
      "idiom" : "tv"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`Top Shelf Image.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "topshelf.png",
      "idiom" : "tv"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`Top Shelf Image Wide.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "topshelf.png",
      "idiom" : "tv"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 4: Run the rendering script**

```bash
./scripts/render-tv-icons.sh
```

Expected output: `Rendered Brand Assets PNGs.` and exit code 0. Inspect the PNGs:

```bash
find "Bashteroids/Assets.xcassets/Brand Assets.brandassets" -name '*.png' | sort
```

Expected: 8 PNG files (back/middle/front × small/large + topshelf × 2).

Open one to eyeball it (optional but recommended):

```bash
open "Bashteroids/Assets.xcassets/Brand Assets.brandassets/App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/front.png"
```

You should see the two ships on a transparent canvas.

- [ ] **Step 5: Smoke-build all three destinations**

```bash
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

Expected: all three `** BUILD SUCCEEDED **` with zero warnings. The tvOS build's `actool` step should now find the Brand Assets and the warning from Task 1 (if any) should be gone.

- [ ] **Step 6: Commit**

```bash
git add scripts/render-tv-icons.sh \
        "Bashteroids/Assets.xcassets/Brand Assets.brandassets"
git commit -m "feat(tvos): layered Brand Assets app icon + top-shelf images

Adds the tvOS app icon as a three-layer parallax stack (back =
starfield, middle = asteroid, front = ships) at the two required
sizes, plus standard and wide top-shelf images with the
BASHTEROIDS wordmark. Generated by scripts/render-tv-icons.sh
from icon.svg; both the script and the rendered PNGs are
committed so a fresh checkout builds without librsvg installed."
```

---

## Task 6: Documentation and final verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the build verification section in CLAUDE.md**

Replace the current "Build verification" block in `CLAUDE.md`:

```markdown
## Build verification

Quick smoke test (no simulator runtime needed):

```sh
xcodebuild -project Bashteroids.xcodeproj \
           -scheme Bashteroids \
           -destination 'platform=macOS,variant=Mac Catalyst' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Should end with `** BUILD SUCCEEDED **` and zero warnings. Run this after any non-trivial change before claiming work is complete.
```

with:

````markdown
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

- Siri Remote can join → turn → thrust → fire → start a game
- A second MFi controller can join alongside the Siri Remote
- Player-name entry pops the SwiftUI overlay with a focused text field and the system on-screen keyboard
- The focused app icon parallaxes correctly on the home screen
````

- [ ] **Step 2: Update the "Deferred work" section to remove the tvOS bullet**

In `CLAUDE.md`, remove the entire "tvOS support" bullet from "Deferred work" (it begins with `- **tvOS support.**`). The section should still list any other deferred items; if tvOS was the only one, replace the whole "Deferred work" section content with `_(none)_` or remove the section entirely if you prefer.

- [ ] **Step 3: Run all three smoke builds one more time**

```bash
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

Expected: all three end with `** BUILD SUCCEEDED **`. Zero warnings.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: tvOS smoke-build command + remove from deferred work

CLAUDE.md now lists the tvOS xcodebuild command alongside iOS
and Catalyst, and calls out the manual runtime checks (Siri
Remote join flow, name-entry overlay) that the headless build
can't cover."
```

- [ ] **Step 5: Hand off for manual verification**

Tell the user the headless gate is green and list the manual checks (from CLAUDE.md, repeated above). They run those on the tvOS simulator or hardware before considering tvOS support truly shipped.
