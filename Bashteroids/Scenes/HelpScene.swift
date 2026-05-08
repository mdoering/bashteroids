import SpriteKit
import GameController

final class HelpScene: SKScene {
    private let manager = ControllerManager.shared
    private var transitioning = false
    private var prevPressed: [ObjectIdentifier: Bool] = [:]

    private let goldColor   = SKColor(red: 245/255, green: 194/255, blue: 66/255, alpha: 1)
    private let labelColor  = SKColor.white
    private let valueColor  = SKColor(white: 0.65, alpha: 1)

    private enum Glyph {
        case shield, twinLaser, boost, minelayer, torpedo
        case asteroid, ufo, alien, snake, mine, rock, wallStrong, wallWeak
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black

        TouchOverlayState.shared.setScene(.other)
        MusicPlayer.shared.play(resource: "help", ext: "m4a")

        let bgTexture = SKTexture(imageNamed: "HelpBackground")
        let bgImgSize = bgTexture.size()
        let bgScale = max(size.width / bgImgSize.width, size.height / bgImgSize.height)
        let bg = SKSpriteNode(texture: bgTexture)
        bg.size = CGSize(width: bgImgSize.width * bgScale, height: bgImgSize.height * bgScale)
        bg.position = CGPoint(x: size.width / 2, y: size.height / 2)
        bg.zPosition = -1
        addChild(bg)

        let title = SKLabelNode(text: "HELP")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 28
        title.fontColor = goldColor
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.88)
        addChild(title)

        let centerX = size.width / 2
        let iconOffset:  CGFloat = 28
        let labelOffset: CGFloat = 60
        let valueOffset: CGFloat = 200
        let leftIconX   = centerX - iconOffset
        let leftLabelX  = centerX - labelOffset
        let leftValueX  = centerX - valueOffset
        let rightIconX  = centerX + iconOffset
        let rightLabelX = centerX + labelOffset
        let rightValueX = centerX + valueOffset

        // Top row: input controls. Bottom row: reference cards with icons.
        // 2-row vertical gap between the two rows.
        let topRowY = size.height * 0.78
        let bottomRowY = topRowY - (30 + 7 * 22) - (2 * 22)

        renderControllerSection(labelX: leftLabelX,  valueX: leftValueX,  topY: topRowY)
        renderKeyboardSection(  labelX: rightLabelX, valueX: rightValueX, topY: topRowY)
        renderPowerupsSection(  labelX: leftLabelX,  valueX: leftValueX,  iconX: leftIconX,  topY: bottomRowY)
        renderEnemiesSection(   labelX: rightLabelX, valueX: rightValueX, iconX: rightIconX, topY: bottomRowY)

        let credits = SKLabelNode(text: "Designed by Markus Döring, with creative inspiration from Toni Möglich.")
        credits.fontName = "AvenirNext-Regular"
        credits.fontSize = 16
        credits.fontColor = SKColor(white: 0.45, alpha: 1)
        credits.position = CGPoint(x: size.width / 2, y: size.height * 0.04)
        addChild(credits)

        KeyboardManager.shared.onKeyDown = { [weak self] code in
            self?.handleKeyDown(code)
        }
    }

    private func renderControllerSection(labelX: CGFloat, valueX: CGFloat, topY: CGFloat) {
        var y = topY
        addHeading("CONTROLLER", x: labelX, y: y, alignment: .right); y -= 30
        for (label, value) in [
            ("Turn",      "Left stick / D-pad"),
            ("Thrust",    "A / R-trigger"),
            ("Brake",     "B / R-stick down"),
            ("Fire",      "X / R-shoulder"),
            ("Minelayer", "Y"),
            ("Join",      "A"),
            ("Start",     "Menu / X / Play-Pause")
        ] {
            addLeftRow(label: label, value: value, labelX: labelX, valueX: valueX, y: y)
            y -= 22
        }
    }

    private func renderKeyboardSection(labelX: CGFloat, valueX: CGFloat, topY: CGFloat) {
        var y = topY
        addHeading("KEYBOARD", x: labelX, y: y, alignment: .left); y -= 30
        for (label, value) in [
            ("Turn",      "\u{2190} / \u{2192}"),
            ("Thrust",    "\u{2191}"),
            ("Brake",     "\u{2193}"),
            ("Fire",      "Space"),
            ("Minelayer", "M"),
            ("Join",      "A"),
            ("Start",     "Space / Enter")
        ] {
            addRightRow(label: label, value: value, labelX: labelX, valueX: valueX, y: y)
            y -= 22
        }
    }

    private func renderPowerupsSection(labelX: CGFloat, valueX: CGFloat, iconX: CGFloat, topY: CGFloat) {
        var y = topY
        addHeading("POWERUPS", x: labelX, y: y, alignment: .right); y -= 30
        let rows: [(Glyph, String, String)] = [
            (.shield,    "Shield",     "Absorbs 1 hit. Stacks 2x."),
            (.twinLaser, "Twin Laser", "Faster fire, stacks to quad."),
            (.boost,     "Boost",      "+50% / +100% max speed."),
            (.minelayer, "Minelayer",  "Place mine, re-press to blow."),
            (.torpedo,   "Torpedo",    "Lock & launch homing missile.")
        ]
        for (glyph, label, value) in rows {
            addLeftRow(label: label, value: value, labelX: labelX, valueX: valueX, y: y)
            placeGlyph(glyph, x: iconX, y: y - 10)
            y -= 24
        }
    }

    private func renderEnemiesSection(labelX: CGFloat, valueX: CGFloat, iconX: CGFloat, topY: CGFloat) {
        var y = topY
        addHeading("ENEMIES", x: labelX, y: y, alignment: .left); y -= 30
        let rows: [(Glyph, String, String)] = [
            (.asteroid,   "Asteroid",      "1 hit, drifts, wraps."),
            (.ufo,        "UFO",           "1 hit, fires aimed bullets."),
            (.alien,      "Alien",         "2 hits, short laser."),
            (.snake,      "Snake",         "4 hits, homes on you."),
            (.mine,       "Mine",          "Flashes 6 s, 140 px blast."),
            (.rock,       "Rock",          "Indestructible."),
            (.wallStrong, "Wall (gray)",   "BATTLE: indestructible."),
            (.wallWeak,   "Wall (orange)", "BATTLE: 5 hp / chunk.")
        ]
        for (glyph, label, value) in rows {
            addRightRow(label: label, value: value, labelX: labelX, valueX: valueX, y: y)
            placeGlyph(glyph, x: iconX, y: y - 10)
            y -= 24
        }
    }

    private func addHeading(_ text: String, x: CGFloat, y: CGFloat, alignment: SKLabelHorizontalAlignmentMode) {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 20
        label.fontColor = goldColor
        label.horizontalAlignmentMode = alignment
        label.verticalAlignmentMode = .top
        label.position = CGPoint(x: x, y: y)
        addChild(label)
    }

    private func addLeftRow(label: String, value: String, labelX: CGFloat, valueX: CGFloat, y: CGFloat) {
        let val = SKLabelNode(text: value)
        val.fontName = "AvenirNext-Regular"
        val.fontSize = 16
        val.fontColor = valueColor
        val.horizontalAlignmentMode = .right
        val.verticalAlignmentMode = .top
        val.position = CGPoint(x: valueX, y: y)
        addChild(val)

        let lbl = SKLabelNode(text: label)
        lbl.fontName = "AvenirNext-Regular"
        lbl.fontSize = 16
        lbl.fontColor = labelColor
        lbl.horizontalAlignmentMode = .right
        lbl.verticalAlignmentMode = .top
        lbl.position = CGPoint(x: labelX, y: y)
        addChild(lbl)
    }

    private func addRightRow(label: String, value: String, labelX: CGFloat, valueX: CGFloat, y: CGFloat) {
        let lbl = SKLabelNode(text: label)
        lbl.fontName = "AvenirNext-Regular"
        lbl.fontSize = 16
        lbl.fontColor = labelColor
        lbl.horizontalAlignmentMode = .left
        lbl.verticalAlignmentMode = .top
        lbl.position = CGPoint(x: labelX, y: y)
        addChild(lbl)

        let val = SKLabelNode(text: value)
        val.fontName = "AvenirNext-Regular"
        val.fontSize = 16
        val.fontColor = valueColor
        val.horizontalAlignmentMode = .left
        val.verticalAlignmentMode = .top
        val.position = CGPoint(x: valueX, y: y)
        addChild(val)
    }

    private func placeGlyph(_ kind: Glyph, x: CGFloat, y: CGFloat) {
        let node = makeGlyphNode(kind)
        node.position = CGPoint(x: x, y: y)
        addChild(node)
    }

    private func makeGlyphNode(_ kind: Glyph) -> SKNode {
        switch kind {
        case .shield:
            let n = Shapes.powerUp(kind: .shield)
            n.setScale(0.85)
            return n
        case .twinLaser:
            return Shapes.powerUp(kind: .twinLaser)
        case .boost:
            return Shapes.powerUp(kind: .boost)
        case .minelayer:
            return Shapes.powerUp(kind: .minelayer)
        case .torpedo:
            return Shapes.powerUp(kind: .torpedo)
        case .asteroid:
            return Shapes.asteroid(radius: 11, seed: 1)
        case .ufo:
            let n = Shapes.ufo()
            n.setScale(0.7)
            return n
        case .alien:
            let n = Shapes.alienMonster()
            n.setScale(0.7)
            return n
        case .snake:
            return makeSnakeHead()
        case .mine:
            let n = Shapes.mine()
            n.setScale(0.55)
            return n
        case .rock:
            return Shapes.rock(radius: 11, seed: 1)
        case .wallStrong:
            return makeWallChip(color: SKColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 1))
        case .wallWeak:
            return makeWallChip(color: SKColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 1))
        }
    }

    private func makeSnakeHead() -> SKShapeNode {
        let snakeCyan = SKColor(red: 0.10, green: 0.95, blue: 0.95, alpha: 1)
        let hl: CGFloat = 11
        let hw: CGFloat = 7
        let inset: CGFloat = 3
        let path = CGMutablePath()
        path.move(to:    CGPoint(x: -hl,         y:  hw - inset))
        path.addLine(to: CGPoint(x: -hl + inset, y:  hw))
        path.addLine(to: CGPoint(x:  hl - inset, y:  hw))
        path.addLine(to: CGPoint(x:  hl,         y:  hw - inset))
        path.addLine(to: CGPoint(x:  hl,         y: -hw + inset))
        path.addLine(to: CGPoint(x:  hl - inset, y: -hw))
        path.addLine(to: CGPoint(x: -hl + inset, y: -hw))
        path.addLine(to: CGPoint(x: -hl,         y: -hw + inset))
        path.closeSubpath()

        let head = SKShapeNode(path: path)
        head.strokeColor = snakeCyan
        head.fillColor   = .clear
        head.lineWidth   = 1.5
        head.lineJoin    = .miter
        head.isAntialiased = true

        // Two slit eyes — same shape pattern as in-game Snake.
        for sign: CGFloat in [1, -1] {
            let eyePath = CGMutablePath()
            let yMid: CGFloat = sign * 3
            eyePath.move(to: CGPoint(x: 1, y: yMid - sign * 1.0))
            eyePath.addLine(to: CGPoint(x: 5, y: yMid + sign * 1.2))
            eyePath.addLine(to: CGPoint(x: 7, y: yMid + sign * 0.4))
            eyePath.addLine(to: CGPoint(x: 3, y: yMid - sign * 1.6))
            eyePath.closeSubpath()
            let eye = SKShapeNode(path: eyePath)
            eye.strokeColor = snakeCyan
            eye.fillColor   = snakeCyan
            eye.lineWidth   = 1
            head.addChild(eye)
        }

        return head
    }

    private func makeWallChip(color: SKColor) -> SKShapeNode {
        let path = CGMutablePath()
        path.addRect(CGRect(x: -11, y: -4, width: 22, height: 8))
        let n = SKShapeNode(path: path)
        n.strokeColor = color
        n.fillColor   = .clear
        n.lineWidth   = 1.5
        n.lineJoin    = .miter
        n.isAntialiased = true
        return n
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
