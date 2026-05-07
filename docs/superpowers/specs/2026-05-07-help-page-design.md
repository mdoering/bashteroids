# Help Page — Design

Date: 2026-05-07

## Goal

A help screen that lists controls (keyboard + controller), powerups, and enemies with short descriptions. Players access it via:

- A `?` button in the lower-right corner of the title screen (tap on iPad / click on Mac)
- The `H` key on a keyboard

Controller-only invocation is deferred to feature F (universal navigation). A teammate with a keyboard / mouse can open help on their behalf.

## Components

- New `HelpScene` (`Bashteroids/Scenes/HelpScene.swift`) — full-screen scene that replaces the title, dismissed back to a fresh `TitleScene`.
- `TitleScene` gains a help button (circle + "?" label) in the lower-right corner, hit-testable via `touchesBegan`. The `H` key in `handleKeyDown` also opens help.

## TitleScene additions

```swift
private var helpButton: SKShapeNode!
```

In `didMove(to:)`, add the help button after the other UI:

```swift
let btn = SKShapeNode(circleOfRadius: 22)
btn.position = CGPoint(x: size.width - 50, y: 50)
btn.strokeColor = SKColor(white: 0.55, alpha: 1)
btn.fillColor = .clear
btn.lineWidth = 1.5
addChild(btn)

let q = SKLabelNode(text: "?")
q.fontName = "AvenirNext-Bold"
q.fontSize = 22
q.fontColor = SKColor(white: 0.55, alpha: 1)
q.verticalAlignmentMode = .center
q.horizontalAlignmentMode = .center
btn.addChild(q)
self.helpButton = btn
```

Touch handling:

```swift
override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let t = touches.first else { return }
    let p = t.location(in: self)
    if helpButton.frame.contains(p) { openHelp() }
}

private func openHelp() {
    guard !transitioning else { return }
    transitioning = true
    let help = HelpScene(size: size)
    help.scaleMode = scaleMode
    view?.presentScene(help, transition: .fade(withDuration: 0.3))
}
```

In `handleKeyDown` (when no editor is active), `case .keyH: openHelp()`.

## HelpScene layout

Full-screen black background. Title "HELP" at top center. Two columns of content below; dismiss hint at the bottom.

```
                      ┌──── HELP ────┐

   CONTROLS                          POWERUPS
                                       Shield        Absorbs 1 hit. Stacks 2x.
   KEYBOARD                            Dual-canon    Faster fire, stacks to quad.
     Turn          ← / →               Boost         +43% / +79% max speed.
     Thrust        ↑                   Minelayer     Place mine, re-press to blow.
     Brake         ↓
     Fire          Space             ENEMIES
     Minelayer     M                   Asteroid      1 hit, drifts, wraps.
     Join          A                   UFO           1 hit, fires aimed bullets.
     Start         Space / Enter       Alien         2 hits, short laser.
                                       Snake         4 hits, homes on you.
   CONTROLLER                          Mine          Flashes 6 s, 140 px blast.
     Turn          Left stick / D-pad  Rock          Indestructible.
     Thrust        A / R-trigger       Wall (gray)   BATTLE: indestructible.
     Brake         B / R-stick down    Wall (orange) BATTLE: 5 hp / chunk.
     Fire          X / R-shoulder
     Minelayer     Y
     Join          A
     Start         Menu / X / ▶❙❙

         PRESS ANY BUTTON / SPACE / ESC TO RETURN
```

Render with one `SKLabelNode` per row, columns at fixed x offsets. Section headings in gold (`245, 194, 66`); item labels left-aligned in white; descriptions left-aligned in dim gray.

### Geometry

- Title at `y = height × 0.93`
- Left column anchor `x = width × 0.10`, right column anchor `x = width × 0.55`
- Section heading: 18 pt bold gold
- Item label: 14 pt regular white, left-aligned
- Item value/description: 14 pt regular gray, offset 130 px to the right of the item label
- Dismiss hint at `y = height × 0.05`, centered, dim gray

## Dismissal

- Keyboard: `ESC` or `SPACE` → return to title (other keys ignored, so accidentally hitting `H` again is a no-op)
- Controller: any button pressed (polled per frame, edge-triggered like other scenes)
- Tap anywhere in the scene → return to title

```swift
override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    returnToTitle()
}

private func handleKeyDown(_ code: GCKeyCode) {
    if code == .escape || code == .spacebar { returnToTitle() }
}

override func update(_ currentTime: TimeInterval) {
    guard !transitioning else { return }
    for c in manager.connectedControllers {
        let id = ObjectIdentifier(c)
        let pressed = anyButtonPressed(c)
        let was = prevPressed[id] ?? false
        if pressed && !was { returnToTitle(); break }
        prevPressed[id] = pressed
    }
}
```

`returnToTitle()` constructs a fresh `TitleScene` and fades to it.

## Files affected

- Create: `Bashteroids/Scenes/HelpScene.swift`
- Modify: `Bashteroids/Scenes/TitleScene.swift` — help button + `H` keypress + tap hit-test

No new types or protocols. Reuses existing `KeyboardManager.shared`, `ControllerManager.shared`.

## Out of scope

- Controller invocation of the help button (deferred to feature F: universal navigation).
- Multi-page help (everything fits on one screen).
- Tutorials / interactive walkthroughs.
- In-game help while a round is running. Help is title-only.
