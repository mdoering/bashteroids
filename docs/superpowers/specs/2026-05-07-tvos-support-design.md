# tvOS Support — Design

Date: 2026-05-07

## Goal

Ship Bashteroids as a first-class tvOS app alongside the existing iPad and Mac Catalyst destinations. "First-class" means: builds for tvOS, runs fullscreen on Apple TV, plays with the bundled Siri Remote *or* MFi controllers, has a proper layered tvOS app icon with parallax, and presents native text-entry UI for the player-name flow.

No new gameplay. No regressions on iPad or Mac.

## Non-goals

- iPhone support (TARGETED_DEVICE_FAMILY stays "2,3", excluding "1").
- iCloud sync of player names / high scores across platforms.
- A separate tvOS-only HUD redesign — title-safe area handling is the only HUD change.
- Multi-target restructuring. One Xcode target, three destinations (iOS, Mac Catalyst, tvOS).

## Architecture summary

Single target gains a third destination. The existing folder layout (`App/`, `Scenes/`, `Entities/`, `Systems/`, `Input/`, `Audio/`, `Render/`, `Utils/`) is unchanged. New files are scoped to the smallest area that needs them, gated by `#if os(tvOS)` only when the API surface differs by platform.

The four areas of change:

1. **Build configuration** — extend `SUPPORTED_PLATFORMS`, deployment target, asset-catalog wiring.
2. **Source-level guards** — title-safe inset handling; everything else already compiles.
3. **Input** — add a `microGamepad` path for the Siri Remote; otherwise reuse the existing `ControllerManager`.
4. **Player-name entry** — SwiftUI overlay above the SpriteView, driven by an `ObservableObject` coordinator. tvOS-only path; iPad/Mac keep the inline keyboard editor.
5. **App icon** — new `Brand Assets.brandassets` with three layered images and two top-shelf images, rendered from `icon.svg`.

## Section 1 — Build configuration

`Bashteroids.xcodeproj/project.pbxproj`, both Debug and Release of the target's build configuration list:

- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx appletvos appletvsimulator"`
- `TVOS_DEPLOYMENT_TARGET = 17.0` (matches `IPHONEOS_DEPLOYMENT_TARGET`)
- `TARGETED_DEVICE_FAMILY = "2,3"` (iPad + tvOS; no iPhone)
- `SUPPORTS_MACCATALYST = YES` left alone
- `ASSETCATALOG_COMPILER_BRANDASSETS_NAME = "Brand Assets"` added with an `[sdk=appletvos*]` qualifier so iPad and Mac keep using `AppIcon`.

`Bashteroids/Info.plist`:

- Drop `LSRequiresIPhoneOS` (asserts iOS-only; would block tvOS)
- Drop `UIRequiresFullScreen` (UIKit-only key, ignored on tvOS)
- Keep the orientation arrays — tvOS ignores them, iPad still respects them
- Keep `GCSupportsControllerUserInteraction` and `GCSupportsMultipleControllers`

## Section 2 — Source-level platform guards

Audit results from grepping the codebase for platform-specific APIs:

- `BashteroidsApp.swift` — already has `#if targetEnvironment(macCatalyst)` / `#elseif os(iOS)` / `#else`. The `#else` branch is the tvOS path. **No change.**
- `GameContainerView.swift` — `MacFullScreen` is already gated `#if targetEnvironment(macCatalyst)` with a no-op stub for the `#else` branch. **No change.**
- `GameScene.handleKeyDown` — `case .escape: MacFullScreen.exitIfActive()` resolves to the no-op on tvOS. **No change.**
- `Audio/AudioEngine.swift` uses `#if os(iOS)` to gate `AVAudioSession.setCategory(.ambient, …)`. tvOS *does* ship `AVAudioSession` and benefits from the same `.ambient` category (so game audio mixes politely with whatever the user was watching). Widen the guard to `#if os(iOS) || os(tvOS)`.

One real change:

- **`GameScene.playBounds`** — tvOS reports a real `safeAreaInsets` (≈60pt top/bottom, 80pt left/right) corresponding to title-safe overscan. Today `playBounds` only subtracts `safeAreaInsets.top`. Update it to subtract all four insets so the playfield stays inside the title-safe rect. The HUD repositioning in `repositionHUD` should likewise use the full insets. Inset values are 0 on iPad and Mac, so this is a no-op on those destinations.

## Section 3 — Input

The Siri Remote is a `GCController` whose `extendedGamepad` is `nil` and whose `microGamepad` is non-nil. `ControllerManager` today only wires `extendedGamepad`, so the Siri Remote silently disconnects from gameplay. Add a parallel `microGamepad` registration path.

Mapping for `microGamepad`:

| Input | Action |
| --- | --- |
| dpad.left / dpad.right | turn |
| dpad.up | thrust |
| dpad.down | brake |
| buttonA (touch-surface click) | fire |
| buttonX / Menu | start / pause |

Configuration on the `microGamepad` profile when it connects:

- `reportsAbsoluteDpadValues = true` so the touch surface reports absolute position rather than delta. This makes the surface behave more like a 4-way d-pad than a relative trackpad.
- `allowsRotation = false` — keep the d-pad axes aligned with the device, regardless of remote orientation.

A Siri Remote slot is treated identically to any other controller slot: joins via "press start", gets a player color, persists its name. An MFi controller and the Siri Remote can be active at the same time (multi-player with the remote occupying one slot).

`KeyboardManager` and `KeyboardInputState` work unchanged on tvOS — `GCKeyboard.coalesced` resolves a connected USB or Bluetooth keyboard. A keyboard player still gets their own slot.

## Section 4 — Player-name entry on tvOS

The recent name-entry feature in `TitleScene` is keyboard-driven. tvOS users typically don't have a keyboard, so we present a SwiftUI overlay over the SpriteView for native text entry.

### Coordinator

A new `MainActor`-bound `ObservableObject`:

```swift
@MainActor
final class NameEntryCoordinator: ObservableObject {
    static let shared = NameEntryCoordinator()
    @Published private(set) var request: NameEntryRequest?

    func request(forSlot slot: Int, current: String?,
                 completion: @escaping (String?) -> Void) { … }
    func cancel() { … }
}

struct NameEntryRequest: Identifiable {
    let id = UUID()
    let slot: Int
    let current: String?
    let completion: (String?) -> Void
}
```

`completion(nil)` means "user cancelled, keep previous name". `completion("name")` means "use this".

### View layer

`GameContainerView` body becomes a `ZStack`:

```swift
ZStack {
    SpriteView(scene: …, options: [.ignoresSiblingOrder])
    if let req = coord.request {
        NameEntryOverlay(request: req)
            .transition(.opacity)
    }
}
.environmentObject(coord)
```

`NameEntryOverlay` is a tvOS-only SwiftUI view (file gated `#if os(tvOS)`):

- Dimmed background
- Focused `TextField("Name", text: $name)` — tvOS auto-presents the system on-screen keyboard for a focused text field
- "Done" and "Cancel" buttons; Done writes through `request.completion(name)`, Cancel writes `request.completion(nil)`
- Both call `NameEntryCoordinator.shared.request = nil` to dismiss

### TitleScene wiring

When a player joins on tvOS:

```swift
#if os(tvOS)
NameEntryCoordinator.shared.request(forSlot: slot.index,
                                    current: HighScore.name(forSlot: slot.index)) { name in
    if let name { HighScore.setName(name, forSlot: slot.index) }
    // proceed with join
}
#else
// existing inline keyboard editor path
#endif
```

Persistence and the per-slot UserDefaults key format stay identical — a name entered on tvOS round-trips with iPad/Mac if the same account is used later.

### Compile-time scope

- `NameEntryCoordinator` lives in `Input/NameEntryCoordinator.swift` — compiled on all platforms (no platform-specific API surface in the coordinator itself).
- `NameEntryOverlay` lives in `App/NameEntryOverlay.swift`, gated `#if os(tvOS)`.
- `GameContainerView` references the overlay only inside `#if os(tvOS)`.
- iPad and Mac never see a non-nil `request` — the inline editor calls `HighScore.setName(...)` directly without going through the coordinator.

## Section 5 — App icon (layered Brand Assets)

### Layer split from `icon.svg`

The source SVG has three obvious layer groups:

- **Back** — `<rect>` background fill + dim starfield `<g opacity="0.22">…</g>`
- **Middle** — asteroid `<path>` and the faint targeting circle
- **Front** — red ship and blue ship

Each layer is rendered against a transparent background at the required tvOS sizes.

### Asset catalog layout

```
Bashteroids/Assets.xcassets/
└── Brand Assets.brandassets/
    ├── Contents.json
    ├── App Icon - App Store.imagestack/
    │   ├── Contents.json
    │   ├── Back.imagestacklayer/
    │   │   ├── Contents.json
    │   │   └── Content.imageset/  (1280x768 PNG)
    │   ├── Middle.imagestacklayer/
    │   │   └── …
    │   └── Front.imagestacklayer/
    │       └── …
    ├── App Icon.imagestack/
    │   └── (same three-layer shape, 400x240)
    ├── Top Shelf Image.imageset/
    │   └── (1920x720 PNG, flat with wordmark)
    └── Top Shelf Image Wide.imageset/
        └── (2320x720 PNG, flat with wordmark)
```

Top-shelf images are flat (not layered) — that's what tvOS expects for the top shelf. They composite the three layers plus the "BASHTEROIDS" wordmark on the side.

### Rendering

A committed shell script `scripts/render-tv-icons.sh`:

- Splits `icon.svg` into three intermediate SVGs (back/middle/front) by stripping the other groups.
- Uses `rsvg-convert` (Homebrew: `librsvg`) to render each at 1280×768 and 400×240 against a transparent canvas.
- Composes the top-shelf images by using `rsvg-convert` to render a flattened SVG at 1920×720 / 2320×720, with a separate wordmark SVG overlaid via ImageMagick `composite`.
- Writes the PNGs into the `.brandassets` tree.

The generated PNGs are committed alongside the script so a fresh checkout builds without needing `librsvg` or ImageMagick installed. The script is documented in the script header — one-shot regeneration when the icon source changes.

## Section 6 — Build verification

CLAUDE.md gains a tvOS smoke build alongside the existing Catalyst one. Both must pass with zero warnings before claiming any tvOS-touching task complete.

```sh
xcodebuild -project Bashteroids.xcodeproj \
           -scheme Bashteroids \
           -destination 'platform=macOS,variant=Mac Catalyst' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO

xcodebuild -project Bashteroids.xcodeproj \
           -scheme Bashteroids \
           -destination 'generic/platform=tvOS' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

### Manual verification (called out, not blocking)

The headless build can't exercise actual Siri Remote / Apple TV runtime behavior. Manual verification steps for the human:

- Open in Xcode, run on Apple TV simulator with paired remote
- Confirm Siri Remote can join → turn → thrust → fire → start a game
- Connect a second MFi controller, confirm both slots are active simultaneously
- Trigger name entry on tvOS, confirm SwiftUI overlay appears with on-screen keyboard
- Confirm the focused app icon parallaxes correctly on the home screen

## Risks and open questions

- The Siri Remote's touch-surface "click" registers as `buttonA` on both first- and second-generation+ remotes via the `microGamepad` profile, so the mapping table works for either.
- Title-safe insets on tvOS at the user's "Zoom" accessibility setting can be larger than the default; relying on `safeAreaInsets` rather than hardcoded margins handles this automatically.
- `librsvg` and ImageMagick are not part of the codebase — the script will fail loudly if missing, but the committed PNGs make this a developer-only concern.

## Out of scope (explicit non-goals revisited)

- iPhone support
- iCloud sync
- HUD redesign for tvOS beyond title-safe handling
- Top-shelf "extended" content (dynamic top-shelf extension)
- Game Center / leaderboards on tvOS
