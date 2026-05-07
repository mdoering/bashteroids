# Feature F (Universal UI Navigation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace TitleScene's per-axis bindings with a single focus model that works identically on keyboard, MFi extended controller, and tvOS Siri Remote — and fold in two adjacent UX wins: per-controller slot picking and a recent-names ring in the name editor.

**Architecture:** A `FocusItem` enum (`mode | level | help`) drives a single focus cursor on TitleScene. Vertical input always moves focus; horizontal input cycles the focused selector value (claimed) or previews a slot (unclaimed). `ControllerManager` gains a per-controller "intended slot" map so each unclaimed controller can pick which empty slot it's about to claim. A new `RecentNames` utility persists the last 8 confirmed names; the editor surfaces them as suggestions.

**Tech Stack:** Swift 5 + SpriteKit, single Xcode target (iOS / Mac Catalyst / tvOS), `UserDefaults` for persistence. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-08-universal-navigation-design.md`

---

## File Structure

- **Create:** `Bashteroids/Utils/RecentNames.swift` — recent-names persistence helper
- **Modify:** `Bashteroids/Input/ControllerManager.swift` — `intendedSlotIndex(for:)`, `setIntendedSlotIndex(_:for:)`, `claim(controller:atSlot:)`, disconnect cleanup
- **Modify:** `Bashteroids/Scenes/TitleScene.swift` — `FocusItem` state, brightness-based render, focus-aware key/d-pad routing, slot preview markers, BATTLE flash, inline recent-names suggestion column
- **Modify:** `Bashteroids/App/NameEntryOverlay.swift` (tvOS only) — recent-names suggestion buttons in the SwiftUI overlay

The `Bashteroids/` folder is `PBXFileSystemSynchronizedRootGroup`, so new `.swift` files are auto-included — no `project.pbxproj` edits.

---

### Task 1: RecentNames ring helper

**Files:**
- Create: `Bashteroids/Utils/RecentNames.swift`
- Modify: `Bashteroids/Scenes/TitleScene.swift` (in `confirmName()` and the tvOS callback inside `beginCoordinatorNameEntry(slot:current:)`)

- [ ] **Step 1: Create RecentNames.swift**

```swift
import Foundation

/// Last 8 unique player names confirmed on title, most-recent first.
/// Persisted in UserDefaults so it survives app restarts.
enum RecentNames {
    private static let key = "recent_names"
    private static let limit = 8

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Record a confirmed name. Trims whitespace, dedupes (promoting the
    /// existing entry to the front), trims to `limit` entries.
    static func record(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = all
        current.removeAll { $0 == trimmed }
        current.insert(trimmed, at: 0)
        if current.count > limit { current = Array(current.prefix(limit)) }
        UserDefaults.standard.set(current, forKey: key)
    }
}
```

- [ ] **Step 2: Wire into the keyboard `confirmName()` path**

In `Bashteroids/Scenes/TitleScene.swift`, find `private func confirmName()`. Right after the `UserDefaults.standard.set(name, forKey: "player_name_\(idx)")` line, add:

```swift
        RecentNames.record(name)
```

- [ ] **Step 3: Wire into the tvOS overlay confirmation callback**

In the same file, find `beginCoordinatorNameEntry(slot:current:)`. Inside the `requestName` completion closure, after `UserDefaults.standard.set(final, forKey: "player_name_\(idx)")`, add:

```swift
            RecentNames.record(final)
```

- [ ] **Step 4: Build all three platforms**

```sh
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
           -destination 'generic/platform=iOS' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
           -destination 'platform=macOS,variant=Mac Catalyst' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
           -destination 'generic/platform=tvOS' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

Each must end with `** BUILD SUCCEEDED **` and zero warnings.

- [ ] **Step 5: Commit**

```bash
git add Bashteroids/Utils/RecentNames.swift Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(names): record confirmed player names into a recent-names ring"
```

---

### Task 2: ControllerManager — intended-slot state + claim API

**Files:**
- Modify: `Bashteroids/Input/ControllerManager.swift`

The existing `claim(controller:)` always picks the next empty index by `slots.count`. We need an explicit-slot variant for the "preview which slot you're about to claim" UX. Plus a per-controller intended-slot dictionary that survives disconnects (cleared on disconnect).

- [ ] **Step 1: Add intended-slot state and accessor methods**

In `Bashteroids/Input/ControllerManager.swift`, near the existing `private var joinEnabled = false` line, add:

```swift
    /// For unclaimed controllers, which empty slot index this controller will
    /// claim when its A button fires. Defaults to the leftmost empty slot
    /// when not set.
    private var intendedSlot: [ObjectIdentifier: Int] = [:]
```

Then add three public methods anywhere in the class (next to `slot(for:)` is natural):

```swift
    func intendedSlotIndex(for controller: GCController) -> Int {
        let id = ObjectIdentifier(controller)
        if let idx = intendedSlot[id], emptySlotIndices().contains(idx) {
            return idx
        }
        return emptySlotIndices().first ?? 0
    }

    func setIntendedSlotIndex(_ idx: Int, for controller: GCController) {
        let id = ObjectIdentifier(controller)
        intendedSlot[id] = idx
    }

    /// Indices in 0..<maxPlayers that aren't currently claimed.
    func emptySlotIndices() -> [Int] {
        let claimed = Set(slots.map { $0.index })
        return (0..<Self.maxPlayers).filter { !claimed.contains($0) }
    }
```

- [ ] **Step 2: Add an explicit-slot claim variant**

After the existing `private func claim(controller:)`, add:

```swift
    @discardableResult
    private func claim(controller: GCController, atSlot index: Int) -> PlayerSlot? {
        guard slot(for: controller) == nil else { return nil }
        guard emptySlotIndices().contains(index) else { return nil }
        let slot = PlayerSlot(
            index: index,
            color: Self.playerColors[index],
            controller: controller
        )
        slots.append(slot)
        slots.sort { $0.index < $1.index }   // keep iteration order stable
        intendedSlot.removeValue(forKey: ObjectIdentifier(controller))
        installJoinHandler(controller)
        onSlotsChanged?()
        return slot
    }
```

Note: `slots.sort` is needed because filling a non-leftmost empty slot would otherwise leave `slots` out of index order, breaking iteration assumptions in TitleScene.renderSlots().

- [ ] **Step 3: Repoint the existing A-button handler at the explicit-slot variant**

In `installJoinHandler(_:)`, both branches (extendedGamepad and microGamepad) call `self.claim(controller: controller)`. Replace each with:

```swift
                    self.claim(controller: controller,
                               atSlot: self.intendedSlotIndex(for: controller))
```

- [ ] **Step 4: Clean up intended-slot state on disconnect**

In `handleDisconnect(_:)`, add the cleanup line right after `slots.removeAll { $0.controller === controller }`:

```swift
        intendedSlot.removeValue(forKey: ObjectIdentifier(controller))
```

- [ ] **Step 5: Remove the now-unused old `claim(controller:)` method**

The old single-argument `claim(controller:)` is no longer reached. Delete it from `ControllerManager.swift` to avoid bit-rot.

- [ ] **Step 6: Build all three platforms** (same commands as Task 1 Step 4)

- [ ] **Step 7: Commit**

```bash
git add Bashteroids/Input/ControllerManager.swift
git commit -m "feat(controllers): per-controller intended slot and explicit-slot claim API"
```

---

### Task 3: Slot preview markers in TitleScene.renderSlots

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift` — extend `renderSlots()`

The 4 slot tiles render today; for each unclaimed *connected* controller we now overlay a small "ready" marker on the slot it's currently previewing, colored by the slot's would-be player color. Multiple unclaimed controllers previewing the same slot stack their markers with a per-controller index label (`1`/`2`/`3`).

- [ ] **Step 1: Extend renderSlots() to draw preview markers**

In `Bashteroids/Scenes/TitleScene.swift`, find the end of `renderSlots()`'s for-loop (right before its closing `}`). After the existing tile rendering loop, add:

```swift
        // Slot-preview markers: one chevron per connected unclaimed controller,
        // sitting on the slot tile that controller would claim if it pressed A.
        let unclaimed = manager.connectedControllers.filter { manager.slot(for: $0) == nil }
        var markersOnSlot: [Int: Int] = [:]   // slot index → count placed so far
        let tileWidth: CGFloat = 110
        let spacing: CGFloat = 24
        let totalWidth = CGFloat(ControllerManager.maxPlayers) * tileWidth
                       + CGFloat(ControllerManager.maxPlayers - 1) * spacing
        let startX = (size.width - totalWidth) / 2 + tileWidth / 2
        let y = size.height * 0.46

        for (controllerIdx, c) in unclaimed.enumerated() {
            let slotIdx = manager.intendedSlotIndex(for: c)
            let placed = markersOnSlot[slotIdx, default: 0]
            markersOnSlot[slotIdx] = placed + 1

            let tileX = startX + CGFloat(slotIdx) * (tileWidth + spacing)
            let markerY = y - 50 - CGFloat(placed) * 14   // stack below tile
            let color = ControllerManager.playerColors[slotIdx]

            let marker = SKLabelNode(text: "▲ \(controllerIdx + 1)")
            marker.fontName = "AvenirNext-Bold"
            marker.fontSize = 11
            marker.fontColor = color
            marker.position = CGPoint(x: tileX, y: markerY)
            slotsLayer.addChild(marker)
        }
```

- [ ] **Step 2: Re-render slot markers when controllers connect/disconnect**

In `didMove(to:)`, the existing `manager.onSlotsChanged = { [weak self] in ... }` already calls `renderSlots()` so claimed/unclaimed transitions repaint. No change required if the preview update from Task 6 also calls `renderSlots()`. (Verified in Task 6.)

- [ ] **Step 3: Build all three platforms**

- [ ] **Step 4: Commit**

```bash
git add Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(title): slot preview markers for unclaimed controllers"
```

---

### Task 4: Focus state + brightness-based rendering

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift`

Add `FocusItem`, `focused`, and update `renderSelectors()` to colour items based on focus. No input wiring yet — that lands in Task 5/6/7. Visually, after this task, the title shows Level (default focus) in bright gold and Mode/Help in dim gold.

- [ ] **Step 1: Add the FocusItem enum and focused property**

In `Bashteroids/Scenes/TitleScene.swift`, near the top of the class alongside `selectedLevel` and `selectedMode`, add:

```swift
    private enum FocusItem: CaseIterable { case mode, level, help }
    private var focused: FocusItem = .level
```

- [ ] **Step 2: Promote helpHint to a stored property**

Find the local `let helpHint = SKLabelNode(text: "[H] HELP")` block in `didMove(to:)`. The label is currently a local; we need to store it for the renderer to update its color. Add a new property next to `battleHintLabel`:

```swift
    private var helpLabel: SKLabelNode!
```

In `didMove(to:)`, replace the existing `let helpHint = ...` block with:

```swift
        let helpL = SKLabelNode(text: "[H] HELP")
        helpL.fontName = "AvenirNext-Bold"
        helpL.fontSize = 14
        helpL.fontColor = TitleScene.accentGold
        helpL.horizontalAlignmentMode = .right
        helpL.position = CGPoint(x: size.width - 30, y: 30)
        addChild(helpL)
        self.helpLabel = helpL
```

(Layout unchanged from today — Help stays in the lower-right corner. The focus-traversal order is logical even with the visual jump from Level to Help; the brightness shift makes "Help is focused" unambiguous.)

- [ ] **Step 3: Promote selector arrows to stored properties**

Add to the property list:

```swift
    private var modeLeftArrow: SKLabelNode!
    private var modeRightArrow: SKLabelNode!
    private var levelLeftArrow: SKLabelNode!
    private var levelRightArrow: SKLabelNode!
```

In `didMove(to:)` where the four `<` `>` arrows are created (`let modeLeft = ...`, etc.), assign each to the new property at the end of its block:

```swift
        self.modeLeftArrow = modeLeft
        // ... and similarly for modeRight, levelLeft, levelRight
```

- [ ] **Step 4: Update renderSelectors() to apply brightness based on focus**

Replace `renderSelectors()`'s body with:

```swift
    private func renderSelectors() {
        let battleAvailable = manager.slots.count >= 2
        let active   = TitleScene.accentGold
        let inactive = TitleScene.accentGold.withAlphaComponent(0.4)

        modeLabel.text  = selectedMode == .survival ? "SURVIVAL" : "BATTLE"
        modeLabel.fontColor = focused == .mode ? active : inactive
        if selectedMode == .battle && !battleAvailable {
            modeLabel.fontColor = inactive   // forced dim regardless of focus
        }

        levelLabel.text = "LEVEL \(selectedLevel)"
        levelLabel.fontColor = focused == .level ? active : inactive

        helpLabel.fontColor = focused == .help ? active : inactive

        modeLeftArrow.fontColor   = focused == .mode  ? active : inactive
        modeRightArrow.fontColor  = focused == .mode  ? active : inactive
        levelLeftArrow.fontColor  = focused == .level ? active : inactive
        levelRightArrow.fontColor = focused == .level ? active : inactive

        battleHintLabel.alpha = battleAvailable ? 0 : 1
    }
```

(The auto-revert `if selectedMode == .battle && !battleAvailable { selectedMode = .survival }` is removed — Task 8 handles BATTLE-with-too-few-players via the start-time flash instead.)

- [ ] **Step 5: Build all three platforms**

- [ ] **Step 6: Commit**

```bash
git add Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(title): focus state + brightness-based render"
```

---

### Task 5: Keyboard focus routing

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift` — `handleKeyDown`

Replace the per-axis cycling with focus-aware routing. ↑↓ moves focus, ←→ cycles the focused selector's value, Space/Enter starts (or opens help if focused on Help). H continues to open help directly. M and the existing arrow shortcuts are dropped.

- [ ] **Step 1: Add the focus mover and confirm helpers**

In `Bashteroids/Scenes/TitleScene.swift`, anywhere private (next to `cycleMode` is natural), add:

```swift
    private func moveFocus(by delta: Int) {
        let items = FocusItem.allCases
        let i = items.firstIndex(of: focused) ?? 0
        let next = (i + delta + items.count) % items.count
        focused = items[next]
        renderSelectors()
    }

    private func cycleFocusedHorizontal(by delta: Int) {
        switch focused {
        case .mode:  cycleMode(by: delta)
        case .level: cycleLevel(by: delta)
        case .help:  break    // help has no value to cycle
        }
    }

    private func confirmFocused() {
        switch focused {
        case .mode:  cycleMode(by: 1)
        case .level: cycleLevel(by: 1)
        case .help:  openHelp()
        }
    }
```

- [ ] **Step 2: Replace handleKeyDown's non-name-entry switch**

In `handleKeyDown(_:)`, find the block beginning `if activeNameSlot == nil {` and the trailing `switch code` block. Replace the whole non-name-entry portion with:

```swift
        if activeNameSlot == nil {
            switch code {
            case .upArrow:    moveFocus(by: -1); return
            case .downArrow:  moveFocus(by:  1); return
            case .leftArrow:  cycleFocusedHorizontal(by: -1); return
            case .rightArrow: cycleFocusedHorizontal(by:  1); return
            case .keyH:       openHelp(); return
            #if DEBUG
            case .keyD:       manager.claimDummy(); return
            #endif
            default: break
            }
        }

        switch code {
        case .keyA:
            // existing keyboard-claim / re-edit-name handler stays exactly as before
            if !manager.hasKeyboardPlayer,
               manager.slots.count < ControllerManager.maxPlayers {
                manager.claimKeyboard()
            } else if let kbSlotIndex = manager.slots.firstIndex(where: { $0.keyboard != nil }) {
                let current = UserDefaults.standard.string(
                    forKey: "player_name_\(kbSlotIndex)") ?? "P\(kbSlotIndex + 1)"
                activeNameSlot = kbSlotIndex
                nameBuffer = current
                manager.setJoinEnabled(false)
                renderSlots()
            }
        case .spacebar, .returnOrEnter, .keypadEnter:
            if focused == .help && activeNameSlot == nil {
                openHelp()
            } else {
                tryStart()
            }
        case .escape:
            MacFullScreen.exitIfActive()
        default:
            break
        }
```

This drops `keyM`, replaces upArrow/downArrow's old level-cycling with focus moves, and reuses leftArrow/rightArrow for cycling the *focused* selector instead of just Mode.

- [ ] **Step 3: Build all three platforms**

- [ ] **Step 4: Commit**

```bash
git add Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(title): keyboard focus-based navigation (↑↓ focus, ←→ cycle, Space/Enter start)"
```

---

### Task 6: Controller d-pad routing — claimed cycles, unclaimed previews

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift` — the `update(_:)` method's d-pad section

Replace the existing `cycleMode`-on-left/right and `cycleLevel`-on-up/down with focus-aware routing. Vertical always moves focus; horizontal cycles the focused selector for *claimed* controllers and previews a slot for *unclaimed*.

- [ ] **Step 1: Replace the existing d-pad switch in update()**

Find the for-loop in `update(_:)` that processes `manager.connectedControllers` for d-pad input. The existing block looks like:

```swift
            if !nameEntryActive {
                if curr.left  && !prev.left  { cycleMode(by: -1) }
                if curr.right && !prev.right { cycleMode(by:  1) }
                if curr.up    && !prev.up    { cycleLevel(by:  1) }
                if curr.down  && !prev.down  { cycleLevel(by: -1) }
            }
            dpadEdge[id] = curr
```

Replace with:

```swift
            if !nameEntryActive {
                let isClaimed = manager.slot(for: c) != nil

                if curr.up    && !prev.up    { moveFocus(by: -1) }
                if curr.down  && !prev.down  { moveFocus(by:  1) }

                if curr.left && !prev.left {
                    if isClaimed { cycleFocusedHorizontal(by: -1) }
                    else         { previewSlot(controller: c, by: -1) }
                }
                if curr.right && !prev.right {
                    if isClaimed { cycleFocusedHorizontal(by:  1) }
                    else         { previewSlot(controller: c, by:  1) }
                }
            }
            dpadEdge[id] = curr
```

- [ ] **Step 2: Add the previewSlot helper**

Anywhere private in TitleScene:

```swift
    private func previewSlot(controller: GCController, by delta: Int) {
        let empty = manager.emptySlotIndices()
        guard !empty.isEmpty else { return }
        let curr = manager.intendedSlotIndex(for: controller)
        let i = empty.firstIndex(of: curr) ?? 0
        let next = empty[(i + delta + empty.count) % empty.count]
        manager.setIntendedSlotIndex(next, for: controller)
        renderSlots()    // redraw preview markers from Task 3
    }
```

- [ ] **Step 3: Build all three platforms**

- [ ] **Step 4: Commit**

```bash
git add Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(title): controller d-pad — claimed cycles focus, unclaimed previews slot"
```

---

### Task 7: Claimed controller A as "confirm focused"

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift` — add A-press polling for claimed controllers

Currently, when a controller claims a slot, its A-button handler is removed in `installJoinHandler` (no further A behavior). Feature F repurposes A on claimed controllers to "confirm focused": cycle Mode/Level forward or open Help. We poll edge-triggered in `update(_:)` rather than wiring `pressedChangedHandler`, matching the existing pattern for `xWasPressed`/`menuWasPressed`.

- [ ] **Step 1: Add an A-press edge tracker**

In `Bashteroids/Scenes/TitleScene.swift`, near the existing `private var xWasPressed: [ObjectIdentifier: Bool] = [:]`, add:

```swift
    private var aWasPressed: [ObjectIdentifier: Bool] = [:]
```

- [ ] **Step 2: Poll A in update() for claimed controllers**

In the for-loop in `update(_:)` (the same loop that already polls `buttonX`), after the existing `xWasPressed[id] = xPressed` line, add:

```swift
            // Claimed controllers: A = "confirm focused" (cycle / open help).
            // Unclaimed controllers' A is still handled by the join handler in
            // ControllerManager and consults intendedSlotIndex(for:).
            if manager.slot(for: c) != nil && !nameEntryActive {
                let aPressed = c.extendedGamepad?.buttonA.isPressed
                    ?? c.microGamepad?.buttonA.isPressed
                    ?? false
                let aWas = aWasPressed[id] ?? false
                if aPressed && !aWas { confirmFocused() }
                aWasPressed[id] = aPressed
            } else {
                aWasPressed[id] = false   // reset so claim → A-confirm doesn't fire on the same press
            }
```

The `aWasPressed[id] = false` reset on transitions (claimed → unclaimed or vice-versa) prevents a single A press that just claimed a slot from instantly firing `confirmFocused()` on the next frame.

- [ ] **Step 3: Build all three platforms**

- [ ] **Step 4: Commit**

```bash
git add Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(title): claimed-controller A confirms focused item (cycle / open help)"
```

---

### Task 8: BATTLE always selectable + start-time flash

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift` — `cycleMode`, `tryStart`, add `flashBattleHint`

The Mode cycler is now unguarded. Start-time validation moves into `tryStart` and triggers a hint flash if BATTLE is selected with too few players.

- [ ] **Step 1: Unguard cycleMode**

Replace the body of `cycleMode(by:)` with:

```swift
    private func cycleMode(by delta: Int) {
        selectedMode = (selectedMode == .survival) ? .battle : .survival
        renderSelectors()
    }
```

(Removes the `battleAvailable` guard.)

- [ ] **Step 2: Add flashBattleHint**

Anywhere private in TitleScene:

```swift
    private func flashBattleHint() {
        battleHintLabel.removeAllActions()
        battleHintLabel.alpha = 1
        let pulse = SKAction.sequence([
            .group([
                .scale(to: 1.15, duration: 0.12),
                .colorize(with: SKColor(red: 1.0, green: 0.65, blue: 0.65, alpha: 1),
                          colorBlendFactor: 1.0, duration: 0.12)
            ]),
            .group([
                .scale(to: 1.0,  duration: 0.18),
                .colorize(with: SKColor(red: 0.7, green: 0.4, blue: 0.4, alpha: 1),
                          colorBlendFactor: 0.0, duration: 0.18)
            ])
        ])
        battleHintLabel.run(pulse)
    }
```

- [ ] **Step 3: Update tryStart to flash and refuse**

In `tryStart()`, replace the existing battle gate:

```swift
        if selectedMode == .battle && manager.slots.count < 2 {
            return
        }
```

with:

```swift
        if selectedMode == .battle && manager.slots.count < 2 {
            flashBattleHint()
            return
        }
```

- [ ] **Step 4: Build all three platforms**

- [ ] **Step 5: Commit**

```bash
git add Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(title): BATTLE always selectable; start refuses with hint flash if <2 players"
```

---

### Task 9: Inline name editor — recent-names suggestions (iPad / Mac)

**Files:**
- Modify: `Bashteroids/Scenes/TitleScene.swift` — extend `renderSlots()` and `handleKeyDown` for the name-entry path

When a slot's name editor is active on iPad / Mac, show a vertical list of up-to-4 recent names beside the active slot tile. ↑↓ during name entry cycles the highlighted suggestion. A / Enter / Space confirms the highlighted suggestion. Typing any character switches into "typing-new-name" mode (existing behavior); the suggestion list dims and stops responding to ↑↓ until the next character or confirmation.

- [ ] **Step 1: Add suggestion-state properties**

Near `nameBuffer` in TitleScene:

```swift
    /// While name entry is active, which recent-names suggestion (0-based)
    /// is currently highlighted. -1 means "the buffer wins" (user has typed,
    /// suggestions are not the active selection).
    private var nameSuggestionIndex: Int = -1
```

- [ ] **Step 2: Render suggestions in renderSlots()**

In `renderSlots()`, after the existing per-slot rendering loop, add:

```swift
        if let activeIdx = activeNameSlot {
            let recents = RecentNames.all.prefix(4)
            guard !recents.isEmpty else { return }
            let tileX = startX + CGFloat(activeIdx) * (tileWidth + spacing)
            let baseX = tileX + tileWidth / 2 + 16    // right of the active tile
            let baseY = y                              // align with tile top

            let header = SKLabelNode(text: "RECENT")
            header.fontName = "AvenirNext-Bold"
            header.fontSize = 11
            header.fontColor = SKColor(white: 0.45, alpha: 1)
            header.horizontalAlignmentMode = .left
            header.verticalAlignmentMode = .top
            header.position = CGPoint(x: baseX, y: baseY + 24)
            slotsLayer.addChild(header)

            for (i, name) in recents.enumerated() {
                let isHighlighted = i == nameSuggestionIndex
                let lbl = SKLabelNode(text: name)
                lbl.fontName = "AvenirNext-Regular"
                lbl.fontSize = 14
                lbl.fontColor = isHighlighted
                    ? TitleScene.accentGold
                    : SKColor(white: 0.65, alpha: 1)
                lbl.horizontalAlignmentMode = .left
                lbl.verticalAlignmentMode = .top
                lbl.position = CGPoint(x: baseX, y: baseY - CGFloat(i * 18))
                slotsLayer.addChild(lbl)
            }
        }
```

- [ ] **Step 3: Wire ↑↓ + confirm during name entry**

In `handleKeyDown(_:)`, find the `if activeNameSlot != nil { ... }` early-return block. Replace its switch with:

```swift
        if activeNameSlot != nil {
            switch code {
            case .returnOrEnter, .keypadEnter:
                let suggestions = Array(RecentNames.all.prefix(4))
                if nameSuggestionIndex >= 0, nameSuggestionIndex < suggestions.count {
                    nameBuffer = suggestions[nameSuggestionIndex]
                }
                confirmName()
            case .deleteOrBackspace:
                if !nameBuffer.isEmpty { nameBuffer.removeLast() }
                nameSuggestionIndex = -1
                renderSlots()
            case .upArrow:
                let count = min(4, RecentNames.all.count)
                guard count > 0 else { break }
                nameSuggestionIndex = max(0, (nameSuggestionIndex < 0 ? 0 : nameSuggestionIndex - 1))
                renderSlots()
            case .downArrow:
                let count = min(4, RecentNames.all.count)
                guard count > 0 else { break }
                nameSuggestionIndex = nameSuggestionIndex < 0
                    ? 0
                    : min(count - 1, nameSuggestionIndex + 1)
                renderSlots()
            default:
                if let ch = TitleScene.charFor(keyCode: code), nameBuffer.count < 8 {
                    nameBuffer.append(ch)
                    nameSuggestionIndex = -1
                    renderSlots()
                }
            }
            return
        }
```

- [ ] **Step 4: Reset nameSuggestionIndex when entry begins/ends**

In `confirmName()`, at the existing `nameBuffer = ""` line, add directly after:

```swift
        nameSuggestionIndex = -1
```

In the keyA-handler's `activeNameSlot = kbSlotIndex` block (where the editor opens), add right after `nameBuffer = current`:

```swift
        nameSuggestionIndex = -1
```

- [ ] **Step 5: Build all three platforms**

- [ ] **Step 6: Commit**

```bash
git add Bashteroids/Scenes/TitleScene.swift
git commit -m "feat(title): recent-names suggestions in inline name editor"
```

---

### Task 10: tvOS overlay — recent-names suggestions

**Files:**
- Modify: `Bashteroids/App/NameEntryOverlay.swift`

Add up to 4 recent-name buttons under the text field. SwiftUI's focus engine on tvOS handles navigation between them and the text field natively — no manual focus management needed.

- [ ] **Step 1: Add the suggestions list under the text field**

In `Bashteroids/App/NameEntryOverlay.swift`, replace the body's `VStack(spacing: 40) { ... }` block with:

```swift
            VStack(spacing: 30) {
                Text("PLAYER \((coordinator.request?.slot ?? 0) + 1) NAME")
                    .font(.system(size: 36, weight: .bold))
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

                let recents = Array(RecentNames.all.prefix(4))
                if !recents.isEmpty {
                    VStack(spacing: 8) {
                        Text("RECENT")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.gray)
                        ForEach(recents, id: \.self) { recent in
                            Button(recent) {
                                name = recent
                                submit()
                            }
                            .font(.system(size: 28))
                        }
                    }
                }

                HStack(spacing: 24) {
                    Button("Cancel") { coordinator.cancel() }
                    Button("Done") { submit() }
                }
                .font(.system(size: 28, weight: .semibold))
            }
            .padding(60)
```

The `Button(recent)` with `name = recent; submit()` lets the player click a previous name on Siri Remote and have it commit immediately.

- [ ] **Step 2: Build tvOS specifically**

```sh
xcodebuild -project Bashteroids.xcodeproj -scheme Bashteroids \
           -destination 'generic/platform=tvOS' \
           -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
```

(iOS / Catalyst builds also remain green since the file is `#if os(tvOS)` gated.)

- [ ] **Step 3: Commit**

```bash
git add Bashteroids/App/NameEntryOverlay.swift
git commit -m "feat(title): recent-names suggestions in tvOS name-entry overlay"
```

---

## Notes for the implementer

- **Build verification per task** is non-negotiable for this codebase; CLAUDE.md mandates iOS / Mac Catalyst / tvOS all build clean before claiming any non-trivial change complete.
- **No tests in this codebase.** Verification is the build plus the manual checks called out in CLAUDE.md (Siri Remote join → start, second MFi controller, name-entry overlay, focus parallax).
- **Manual verification checklist after Task 7** (the input wiring stack is complete by then):
  - Keyboard: ↑↓ moves focus; ←→ cycles focused selector; Space/Enter starts (or opens help when focus=Help); H still works.
  - MFi controller (claimed): same d-pad behaviour. A confirms focused (cycle/open help). X still starts.
  - MFi controller (unclaimed): ←→ moves the slot-preview marker; A claims the previewed slot. ↑↓ still moves global focus.
  - Siri Remote: claim via touchpad-click → focus reachable to Help → click again opens HelpScene.
- **Manual verification after Task 10:** open the name-entry overlay on tvOS sim/device; the system on-screen keyboard appears and recent-name buttons are focusable below it.
- **Don't forget the existing `D`-key debug shortcut** (claim dummy player, DEBUG only) — Task 5 retains it inside the `#if DEBUG` branch.
