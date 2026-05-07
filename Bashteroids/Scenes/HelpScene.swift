import SpriteKit
import GameController
import UIKit

final class HelpScene: SKScene {
    private let manager = ControllerManager.shared
    private var transitioning = false
    private var prevPressed: [ObjectIdentifier: Bool] = [:]

    private let goldColor   = SKColor(red: 245/255, green: 194/255, blue: 66/255, alpha: 1)
    private let labelColor  = SKColor.white
    private let valueColor  = SKColor(white: 0.65, alpha: 1)
    private let dimColor    = SKColor(white: 0.45, alpha: 1)

    override func didMove(to view: SKView) {
        backgroundColor = .black

        let title = SKLabelNode(text: "HELP")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 28
        title.fontColor = goldColor
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.93)
        addChild(title)

        let leftX  = size.width * 0.10
        let rightX = size.width * 0.55
        let topY   = size.height * 0.85

        renderControls(originX: leftX, topY: topY)
        renderPowerups(originX: rightX, topY: topY)
        renderEnemies(originX: rightX, topY: topY - 240)

        let hint = SKLabelNode(text: "PRESS ANY BUTTON / SPACE / ESC TO RETURN")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 14
        hint.fontColor = dimColor
        hint.position = CGPoint(x: size.width / 2, y: size.height * 0.05)
        addChild(hint)

        KeyboardManager.shared.onKeyDown = { [weak self] code in
            self?.handleKeyDown(code)
        }
    }

    override func willMove(from view: SKView) {
        KeyboardManager.shared.onKeyDown = nil
    }

    private func renderControls(originX: CGFloat, topY: CGFloat) {
        var y = topY
        addHeading("CONTROLS", x: originX, y: y); y -= 28

        addHeading("KEYBOARD", x: originX, y: y, small: true); y -= 22
        for (label, value) in [
            ("Turn",      "\u{2190} / \u{2192}"),
            ("Thrust",    "\u{2191}"),
            ("Brake",     "\u{2193}"),
            ("Fire",      "Space"),
            ("Minelayer", "M"),
            ("Join",      "A"),
            ("Start",     "Space / Enter")
        ] {
            addRow(label: label, value: value, x: originX, y: y); y -= 18
        }

        y -= 10
        addHeading("CONTROLLER", x: originX, y: y, small: true); y -= 22
        for (label, value) in [
            ("Turn",      "Left stick / D-pad"),
            ("Thrust",    "A / R-trigger"),
            ("Brake",     "B / R-stick down"),
            ("Fire",      "X / R-shoulder"),
            ("Minelayer", "Y"),
            ("Join",      "A"),
            ("Start",     "Menu / X / Play-Pause")
        ] {
            addRow(label: label, value: value, x: originX, y: y); y -= 18
        }
    }

    private func renderPowerups(originX: CGFloat, topY: CGFloat) {
        var y = topY
        addHeading("POWERUPS", x: originX, y: y); y -= 28

        for (label, value) in [
            ("Shield",     "Absorbs 1 hit. Stacks 2x."),
            ("Dual-canon", "Faster fire, stacks to quad."),
            ("Boost",      "+43% / +79% max speed."),
            ("Minelayer",  "Place mine, re-press to blow.")
        ] {
            addRow(label: label, value: value, x: originX, y: y); y -= 22
        }
    }

    private func renderEnemies(originX: CGFloat, topY: CGFloat) {
        var y = topY
        addHeading("ENEMIES", x: originX, y: y); y -= 28

        for (label, value) in [
            ("Asteroid",     "1 hit, drifts, wraps."),
            ("UFO",          "1 hit, fires aimed bullets."),
            ("Alien",        "2 hits, short laser."),
            ("Snake",        "4 hits, homes on you."),
            ("Mine",         "Flashes 6 s, 140 px blast."),
            ("Rock",         "Indestructible."),
            ("Wall (gray)",  "BATTLE: indestructible."),
            ("Wall (orange)","BATTLE: 5 hp / chunk.")
        ] {
            addRow(label: label, value: value, x: originX, y: y); y -= 18
        }
    }

    private func addHeading(_ text: String, x: CGFloat, y: CGFloat, small: Bool = false) {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = small ? 14 : 18
        label.fontColor = goldColor
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: x, y: y)
        addChild(label)
    }

    private func addRow(label: String, value: String, x: CGFloat, y: CGFloat) {
        let lbl = SKLabelNode(text: label)
        lbl.fontName = "AvenirNext-Regular"
        lbl.fontSize = 14
        lbl.fontColor = labelColor
        lbl.horizontalAlignmentMode = .left
        lbl.verticalAlignmentMode = .top
        lbl.position = CGPoint(x: x, y: y)
        addChild(lbl)

        let val = SKLabelNode(text: value)
        val.fontName = "AvenirNext-Regular"
        val.fontSize = 14
        val.fontColor = valueColor
        val.horizontalAlignmentMode = .left
        val.verticalAlignmentMode = .top
        val.position = CGPoint(x: x + 130, y: y)
        addChild(val)
    }

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

    private func anyButtonPressed(_ c: GCController) -> Bool {
        if let gp = c.extendedGamepad {
            return gp.buttonA.isPressed || gp.buttonB.isPressed
                || gp.buttonX.isPressed || gp.buttonY.isPressed
                || gp.buttonMenu.isPressed
        }
        if let mg = c.microGamepad {
            return mg.buttonA.isPressed || mg.buttonX.isPressed
        }
        return false
    }

    private func returnToTitle() {
        guard !transitioning else { return }
        transitioning = true
        let next = TitleScene(size: size)
        next.scaleMode = scaleMode
        view?.presentScene(next, transition: .fade(withDuration: 0.3))
    }
}
