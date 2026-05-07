# Polish Pack — Design

Date: 2026-05-07

## Goal

Five small, independent fixes from `improvements.md`:

1. Recolor the minelayer powerup so it doesn't look like the evil mine.
2. Crop the 1-px gray stripe off the right edge of `poster.png`.
3. Allow the keyboard player to re-edit their name.
4. Allow controllers to confirm name entry (which currently requires a keyboard, blocking the mode/level selectors on controller-only setups).
5. Render the highscore list as aligned name / level / score columns.

## 1. Minelayer color

`Shapes.minelayerPowerUp()` and `Ship.makeMinelayerMarker()` both stroke their paths with `SKColor(white: 0.7, alpha: 1)` (warm gray). This reads identically to the white mine entity — players can't tell at a glance whether a glow is the powerup or the hazard.

Change both to `SKColor(red: 0.85, green: 0.30, blue: 0.75, alpha: 1)` — magenta. Distinct from shield (cyan), dual-canon (yellow), boost (orange), and the white mine.

## 2. Poster border crop

`graphics/poster.png` is 1786×2526 with a 1-pixel-wide gray stripe `(116, 115, 115)` running down the rightmost column at `x = 1785`. Crop 1 px off the right: `magick poster.png -crop 1785x2526+0+0 poster.png`. Apply to both copies (`graphics/poster.png` and `Bashteroids/Assets.xcassets/Splash.imageset/poster.png`).

The Splash.imageset is the runtime-loaded copy — the visible artifact players see is sourced there.

## 3. Keyboard player re-edit name

In `TitleScene.handleKeyDown(.keyA)`, the current logic only claims a keyboard player on first press; subsequent presses do nothing for a keyboard-claimed slot.

Extend the case so that when a keyboard player is already joined AND no editor is currently active, pressing `A` reopens the name editor for that keyboard slot (mirrors the per-slot controller-A polling that already works for controller players).

```swift
case .keyA:
    if !manager.hasKeyboardPlayer,
       manager.slots.count < ControllerManager.maxPlayers {
        manager.claimKeyboard()
    } else if activeNameSlot == nil,
              let kbSlotIndex = manager.slots.firstIndex(where: { $0.keyboard != nil }) {
        let current = UserDefaults.standard.string(forKey: "player_name_\(kbSlotIndex)")
            ?? "P\(kbSlotIndex + 1)"
        activeNameSlot = kbSlotIndex
        nameBuffer = current
        manager.setJoinEnabled(false)
        renderSlots()
    }
```

## 4. Controller A confirms name entry

In `TitleScene.update`, the per-slot loop currently has two branches: `if !nameEntryActive` (poll for re-edit triggers) and `else` (just bookkeeping). The `else` branch ignores controller buttonA.

Change the else branch so a rising edge of any controller's buttonA calls `confirmName()` (the existing keyboard-Enter path). Now controller-only players can finish name entry without typing.

```swift
} else {
    for (i, slot) in manager.slots.enumerated() {
        let pressed = slot.controller?.extendedGamepad?.buttonA.isPressed
            ?? slot.controller?.microGamepad?.buttonA.isPressed
            ?? false
        let was = slotAWasPressed[i] ?? false
        if pressed && !was {
            confirmName()
        }
        slotAWasPressed[i] = pressed
    }
}
```

`confirmName()` already preserves the previous-stored name when the buffer is empty, so a controller player who joins and immediately presses A keeps their default `P1` / `P2` / etc. name without any editing.

## 5. Highscore columns

Currently each entry is a single label: `"\(name)\(levelTag): \(score)"`. Three problems:
- Name length pushes the level / score visually around between rows.
- The colon glyph is decorative and doesn't help readability.
- No way to sort or scan visually by score / level.

**Fix:** split each row into three labels at fixed x offsets, all sharing the same y. The same layout applies to the header (which becomes "HIGHSCORES" still as a single label, anchored to the leftmost column — column captions are not added).

| Column | Anchor | x offset (relative to `leaderboardX`) |
| --- | --- | --- |
| Name | `.left` | `+ 0` |
| Level | `.left` | `+ 130` |
| Score | `.right` | `+ 260` |

Same font / size / color rules as today (heading gold, first row magenta, others cyan).

## Files affected

- Modify: `Bashteroids/Render/Shapes.swift` (minelayer color)
- Modify: `Bashteroids/Entities/Ship.swift` (minelayer marker color)
- Modify: `graphics/poster.png` (cropped)
- Modify: `Bashteroids/Assets.xcassets/Splash.imageset/poster.png` (cropped)
- Modify: `Bashteroids/Scenes/TitleScene.swift` (keyboard re-edit, controller-A confirm, highscore columns)

## Out of scope

- Confirming name with a button OTHER than A (Y, Menu, etc.) — A is consistent with the join-and-edit metaphor.
- Highscore column captions ("NAME / LEVEL / SCORE" header row).
- Persisting custom column widths.
- Touch input on iPad for re-editing names.
