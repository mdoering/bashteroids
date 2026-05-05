import SpriteKit

final class TitleScene: SKScene {
    private let manager = ControllerManager.shared
    private let slotsLayer = SKNode()
    private var transitioning = false
    private var menuWasPressed: [ObjectIdentifier: Bool] = [:]

    override var canBecomeFirstResponder: Bool { true }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        becomeFirstResponder()

        let title = SKLabelNode(text: "BASHTEROIDS")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 64
        title.fontColor = .white
        title.position = CGPoint(x: size.width / 2, y: size.height * 0.72)
        addChild(title)

        let hint = SKLabelNode(text: "PRESS A TO JOIN  ·  START / SPACE TO BEGIN")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 18
        hint.fontColor = SKColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: size.width / 2, y: size.height * 0.20)
        addChild(hint)

        let hi = SKLabelNode(text: "HI  \(HighScore.current)")
        hi.fontName = "AvenirNext-Regular"
        hi.fontSize = 14
        hi.fontColor = SKColor(white: 0.40, alpha: 1)
        hi.position = CGPoint(x: size.width / 2, y: size.height * 0.08)
        addChild(hi)

        addChild(slotsLayer)
        renderSlots()

        manager.onSlotsChanged = { [weak self] in self?.renderSlots() }
        manager.onStartPressed = { [weak self] in self?.tryStart() }
        manager.setJoinEnabled(true)
    }

    override func willMove(from view: SKView) {
        manager.setJoinEnabled(false)
        manager.onSlotsChanged = nil
        manager.onStartPressed = nil
    }

    private func tryStart() {
        guard !transitioning, !manager.slots.isEmpty else { return }
        transitioning = true
        let next = GameScene(size: size)
        next.scaleMode = scaleMode
        view?.presentScene(next, transition: .fade(withDuration: 0.4))
    }

    override func update(_ currentTime: TimeInterval) {
        guard !transitioning else { return }
        for c in manager.connectedControllers {
            let pressed = c.extendedGamepad?.buttonMenu.isPressed ?? false
            let id = ObjectIdentifier(c)
            let was = menuWasPressed[id] ?? false
            if pressed && !was { tryStart(); break }
            menuWasPressed[id] = pressed
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardSpacebar, .keyboardReturnOrEnter:
                tryStart()
                return
            case .keyboardEscape:
                MacFullScreen.exitIfActive()
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    private func renderSlots() {
        slotsLayer.removeAllChildren()
        let count = ControllerManager.maxPlayers
        let tileWidth: CGFloat = 110
        let spacing: CGFloat = 24
        let totalWidth = CGFloat(count) * tileWidth + CGFloat(count - 1) * spacing
        let startX = (size.width - totalWidth) / 2 + tileWidth / 2
        let y = size.height * 0.46

        for i in 0..<count {
            let x = startX + CGFloat(i) * (tileWidth + spacing)
            let center = CGPoint(x: x, y: y)
            let claimed = i < manager.slots.count
            let color: SKColor = claimed
                ? manager.slots[i].color
                : SKColor(white: 0.25, alpha: 1)

            let tile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: 110), cornerRadius: 8)
            tile.position = center
            tile.strokeColor = color
            tile.fillColor = .clear
            tile.lineWidth = 2
            slotsLayer.addChild(tile)

            if claimed {
                let ship = Shapes.shipV(color: color, scale: 1.6)
                ship.position = center
                ship.zRotation = .pi / 2
                slotsLayer.addChild(ship)
            } else {
                let label = SKLabelNode(text: "P\(i + 1)")
                label.fontName = "AvenirNext-Regular"
                label.fontSize = 16
                label.fontColor = color
                label.position = CGPoint(x: x, y: y - 6)
                slotsLayer.addChild(label)
            }
        }
    }
}
