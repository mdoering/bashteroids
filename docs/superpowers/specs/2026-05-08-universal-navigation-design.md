# Universal UI Navigation (Feature F) — Design

Date: 2026-05-08

## Goal

Give every input device — keyboard, MFi extended controller, tvOS Siri Remote — the same way to navigate the title screen and act on its choices. Today the d-pad has dedicated axes (mode left/right, level up/down) and Help is keyboard-only. Feature F replaces this with one focus model, plus two adjacent UX wins folded in: per-controller slot picking and a recent-names ring in the player-name editor.

## Locked decisions (from brainstorm)

- Scope: **TitleScene only.** GameOver and HelpScene keep "any button dismisses".
- Focus topology: vertical movement traverses the menu items `{ Mode, Level, Help }`; horizontal movement cycles the focused selector's value (Mode/Level only); `A` / `Space` / `Enter` confirms.
- Input split:
  - **Vertical** d-pad / arrow keys → always moves global menu focus.
  - **Horizontal** d-pad / arrow keys → cycles the focused selector when the controller is *claimed* (or always for the keyboard); previews a slot when the controller is *unclaimed*.
- Visual focus signal: brightness shift. Focused item is full gold `(245, 194, 66)`; unfocused items render at ~40% alpha gold. No bracket changes.
- Default focus: `Level`.
- Back / cancel: `ESC` keyboard-only, only meaningful inside overlays (HelpScene, name editor). No controller "back" on the bare title — there's nothing to back out of.
- Disabled-state for `Mode = BATTLE` with fewer than 2 players: BATTLE is selectable but rendered in dim gold; Start press flashes the "BATTLE NEEDS 2+ PLAYERS" hint and refuses to begin.
- Slot picking (idea (a) from brainstorm): each unclaimed controller has its own latent slot-preview cursor driven by its horizontal d-pad. `A` claims the previewed slot.
- Name reuse (idea (b)): a global recent-names ring (last 8 unique names) persisted in `UserDefaults`. The name editor surfaces these as quick-pick suggestions navigable with vertical input.

## Affected surfaces

- `TitleScene` — focus state, rendering, key/d-pad routing.
- `ControllerManager` — per-controller "intended slot" state and a `claimSlot(_:)` API that takes an explicit index.
- `PlayerSlot` — no structural change; new initializer was added in the dummy-player work and is unaffected.
- New `Bashteroids/Utils/RecentNames.swift` — persistence helper for the names ring.
- Name-entry overlay (`NameEntryCoordinator`/`NameEntryOverlay` on tvOS, inline buffer on iPad/Mac) — surface recent-names suggestions; vertical d-pad / arrows cycle, `A` / `Enter` confirms.

## Focus state

Add to `TitleScene`:

```swift
private enum FocusItem: CaseIterable {
    case mode, level, help
}
private var focused: FocusItem = .level
```

`FocusItem.allCases` ordered top-to-bottom matches the visual layout: mode (top), level (middle), help (bottom). Vertical d-pad / arrows step through that array, wrapping at the ends.

`renderSelectors()` consults `focused` and applies brightness:

```swift
let activeColor = TitleScene.accentGold
let inactiveColor = TitleScene.accentGold.withAlphaComponent(0.4)

modeLabel.fontColor   = focused == .mode  ? activeColor : inactiveColor
levelLabel.fontColor  = focused == .level ? activeColor : inactiveColor
helpLabel.fontColor   = focused == .help  ? activeColor : inactiveColor

// brackets follow the same focused/unfocused rule
modeLeft.fontColor    = focused == .mode  ? activeColor : inactiveColor
modeRight.fontColor   = focused == .mode  ? activeColor : inactiveColor
levelLeft.fontColor   = focused == .level ? activeColor : inactiveColor
levelRight.fontColor  = focused == .level ? activeColor : inactiveColor
```

Special case for BATTLE-when-disabled: when `selectedMode == .battle && !battleAvailable`, the `modeLabel` color is *forced* to the inactive tint regardless of focus, so the disabled state always reads as "you can pick this but can't start with it".

## Input routing

`TitleScene.handleKeyDown` becomes:

```swift
switch code {
case .leftArrow:  cycleFocusedHorizontal(by: -1)
case .rightArrow: cycleFocusedHorizontal(by:  1)
case .upArrow:    moveFocus(by: -1)   // up = previous in FocusItem.allCases
case .downArrow:  moveFocus(by:  1)
case .spacebar, .returnOrEnter, .keypadEnter:
    confirmFocused()                  // start game OR cycle / activate the focused item
...
}
```

`confirmFocused()`:
- `.mode` → cycle mode forward (same as `cycleFocusedHorizontal(by: 1)`)
- `.level` → cycle level forward
- `.help` → `openHelp()`

Plus the existing `tryStart()` semantics for `Space`/`Enter`/`Play-Pause`: pressing those *always* tries to start the game, regardless of focus. The `Space`/`Enter` keys behave as "start" because that's the dominant intent on title — the focus-confirm path runs only when the focused item isn't a selector or is Help. Concretely:

```swift
case .spacebar, .returnOrEnter, .keypadEnter:
    if focused == .help { openHelp() }
    else { tryStart() }
```

Mode/Level confirm is therefore done with `←`/`→` only, not Space/Enter — matching the existing keyboard pattern where Space/Enter has always been "start".

For the controller path, `TitleScene.update(_:)` reads d-pad input per controller. The new logic:

```swift
for c in manager.connectedControllers {
    let id = ObjectIdentifier(c)
    let curr = readDpadEdge(c)
    let prev = dpadEdge[id] ?? (false, false, false, false)

    let isClaimed = manager.slot(for: c) != nil

    if curr.up    && !prev.up    { moveFocus(by: -1) }
    if curr.down  && !prev.down  { moveFocus(by:  1) }

    if curr.left  && !prev.left {
        if isClaimed { cycleFocusedHorizontal(by: -1) }
        else         { previewSlot(controller: c, by: -1) }
    }
    if curr.right && !prev.right {
        if isClaimed { cycleFocusedHorizontal(by:  1) }
        else         { previewSlot(controller: c, by:  1) }
    }

    dpadEdge[id] = curr
}
```

### Button bindings on title (per device)

| Input | Keyboard | Controller (unclaimed) | Controller (claimed) |
|---|---|---|---|
| Move focus ↑↓ | arrow keys | d-pad / left stick | d-pad / left stick |
| Cycle selector ←→ | arrow keys | — | d-pad / left stick |
| Slot preview ←→ | — | d-pad / left stick | — |
| Start game | `Space`, `Enter` *(unless focus = Help, then open help)* | — | `X`, Play-Pause, Menu |
| Confirm focused (cycle / open help) | `Space`/`Enter` only when focus = Help | `A` → claim previewed slot | `A` |
| Open help (shortcut, any focus) | `H` | — | — |
| Mac fullscreen exit | `ESC` | — | — |

For *claimed* controllers, `A` is currently unbound on title (the join handler is removed at claim time). Feature F repurposes it as "confirm focused": cycle Mode forward, cycle Level forward, or open Help. This is what makes Help reachable on a Siri Remote (claim slot via touchpad-click → d-pad to Help → click again to open). For *unclaimed* controllers, `A` continues to mean "claim a slot" — but it now claims the *previewed* slot for that specific controller, defaulting to leftmost if the controller hasn't moved its horizontal d-pad.

`X` / `Play-Pause` / `Menu` keep their existing "start game" semantics. There is no controller binding for "open help via shortcut" — claim-then-navigate is the path.

`ControllerManager` exposes:

```swift
func slot(for controller: GCController) -> PlayerSlot?  // existing
func intendedSlotIndex(for controller: GCController) -> Int   // new — returns leftmost empty by default
func setIntendedSlotIndex(_ idx: Int, for controller: GCController)  // new
@discardableResult
func claim(controller: GCController, atSlot index: Int) -> PlayerSlot?  // new
```

`previewSlot(controller:by:)` in `TitleScene`:

```swift
private func previewSlot(controller: GCController, by delta: Int) {
    let empty = emptySlotIndices()           // currently-vacant slot indices
    guard !empty.isEmpty else { return }
    let curr = manager.intendedSlotIndex(for: controller)
    let i = empty.firstIndex(of: curr) ?? 0
    let next = empty[(i + delta + empty.count) % empty.count]
    manager.setIntendedSlotIndex(next, for: controller)
    renderSlots()                            // redraw preview markers
}
```

When a controller's `A` fires, the existing `installJoinHandler` path consults `intendedSlotIndex` and calls `claim(controller:atSlot:)`.

## Slot preview rendering

`renderSlots()` already lays out the 4 tiles. Extend it: for each unclaimed controller, draw a faint colored "ready" outline (1px dashed, the would-be color for that controller's join slot, derived from `playerColors[index]`) on the tile that controller is currently previewing. With multiple unclaimed controllers all defaulting to the leftmost empty slot, the markers stack — one per controller, slightly offset (e.g., a tiny chevron labeled `1`/`2`/`3` for which controller). Acceptable UX for the rare 4-controller couch start.

When that controller claims, the preview disappears (it's on the tile that's now solidly outlined).

## Disabled BATTLE behavior

`renderSelectors()` enforces dimmed gold when `selectedMode == .battle && !battleAvailable`. The cycler is *not* gated — left/right always toggles the value:

```swift
private func cycleMode(by delta: Int) {
    selectedMode = (selectedMode == .survival) ? .battle : .survival
    renderSelectors()
}
```

`tryStart()` adds the gate:

```swift
if selectedMode == .battle && manager.slots.count < 2 {
    flashBattleHint()
    return
}
```

`flashBattleHint()` runs an `SKAction.sequence` on `battleHintLabel`: pulse alpha to 1.0, scale 1.15× for 0.15s, ease back. The hint is already visible whenever `!battleAvailable`, so the flash just calls attention to it.

## Recent names ring

New file: `Bashteroids/Utils/RecentNames.swift`.

```swift
enum RecentNames {
    private static let key = "recent_names"
    private static let limit = 8

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = all
        current.removeAll { $0 == trimmed }      // dedupe & promote
        current.insert(trimmed, at: 0)
        if current.count > limit { current = Array(current.prefix(limit)) }
        UserDefaults.standard.set(current, forKey: key)
    }
}
```

Call `RecentNames.record(name)` from both confirmation paths: keyboard `confirmName()` in `TitleScene` and the tvOS overlay `NameEntryCoordinator` callback.

### Editor surface

The inline (iPad/Mac) editor on `TitleScene` already shows the buffer with a `_` cursor in the player tile. Add a small column of recent-names suggestions to the right of the active tile (3-4 entries vertically). Vertical d-pad / arrow keys when name entry is active cycle through the suggestions. Pressing the suggestion (or just confirming with Enter / `A`) commits that name. Typing a character interrupts the suggestion preview and switches to typing-the-buffer mode (existing behavior unchanged).

The tvOS SwiftUI overlay (`NameEntryOverlay`) gets the same suggestion list rendered above the system text field. Focus order: text field → suggestion 1 → 2 → 3 → 4. Apple's focus engine handles the navigation natively for SwiftUI.

## Edge cases

- **Battle auto-revert when partner un-joins:** mid-flight if a 2nd controller disconnects after BATTLE was selected, Mode stays on BATTLE (no auto-revert) — but Start refuses with the flash. Player can press `←` / `→` to switch to SURVIVAL. Removing the auto-revert is intentional: it means feature F doesn't quietly mutate selections behind the player's back.
- **Help focused while name editor is open:** name editor is modal — focus moves are intercepted while a name entry is active, suggestions are the only navigable thing.
- **Start hotkey precedence:** `Space`/`Enter`/`Play-Pause` always trigger Start unless focus is on Help. This preserves the muscle memory from before feature F.
- **Empty join state on tvOS:** with no controllers claimed, the keyboard arrows still drive global focus. On tvOS without a keyboard, the player must claim a slot first (touchpad click) — then their d-pad takes over. There's no spectator-only path.

## Out of scope

- In-game pause menu — feature F doesn't introduce one.
- Focus-driven GameOver / Help dismissal — both keep "any button" semantics.
- Slot color customization beyond what slot you pick (color is still tied to slot index).
- Profile system — recent-names ring is intentionally lighter than profiles.
- Touch gestures on iPad / Catalyst (the previous UIKit removal already locked us out of `touchesBegan`-style interactions; nothing changes here).
