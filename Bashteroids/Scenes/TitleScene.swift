import SpriteKit

final class TitleScene: SKScene {
    private let manager = ControllerManager.shared
    private let slotsLayer = SKNode()
    private var transitioning = false
    private var menuWasPressed: [ObjectIdentifier: Bool] = [:]
    private var xWasPressed: [ObjectIdentifier: Bool] = [:]
    private var activeNameSlot: Int? = nil
    private var nameBuffer: String = ""
    private var prevSlotCount: Int = 0
    private var slotAWasPressed: [Int: Bool] = [:]

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

        let icon = makeIconNode()
        icon.position = CGPoint(x: size.width - 80, y: size.height - 58)
        addChild(icon)

        addChild(slotsLayer)
        renderSlots()

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
        manager.onStartPressed = { [weak self] in self?.tryStart() }
        manager.setJoinEnabled(true)
    }

    override func willMove(from view: SKView) {
        manager.setJoinEnabled(false)
        manager.onSlotsChanged = nil
        manager.onStartPressed = nil
    }

    private func tryStart() {
        guard !transitioning, !manager.slots.isEmpty, activeNameSlot == nil else { return }
        transitioning = true
        let next = GameScene(size: size)
        next.scaleMode = scaleMode
        view?.presentScene(next, transition: .fade(withDuration: 0.4))
    }

    override func update(_ currentTime: TimeInterval) {
        guard !transitioning else { return }

        if activeNameSlot == nil {
            for (i, slot) in manager.slots.enumerated() {
                let pressed = slot.controller?.extendedGamepad?.buttonA.isPressed ?? false
                let was = slotAWasPressed[i] ?? false
                if pressed && !was {
                    activeNameSlot = i
                    nameBuffer = UserDefaults.standard.string(
                        forKey: "player_name_\(i)") ?? "P\(i + 1)"
                    manager.setJoinEnabled(false)
                    renderSlots()
                    break
                }
                slotAWasPressed[i] = pressed
            }
        } else {
            for (i, slot) in manager.slots.enumerated() {
                slotAWasPressed[i] = slot.controller?.extendedGamepad?.buttonA.isPressed ?? false
            }
        }

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
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }

            if activeNameSlot != nil {
                switch key.keyCode {
                case .keyboardReturnOrEnter:
                    confirmName()
                case .keyboardDeleteOrBackspace:
                    if !nameBuffer.isEmpty { nameBuffer.removeLast(); renderSlots() }
                default:
                    let chars = key.characters ?? ""
                    if chars.count == 1,
                       let scalar = chars.unicodeScalars.first,
                       CharacterSet.alphanumerics.union(.init(charactersIn: " ")).contains(scalar),
                       nameBuffer.count < 8 {
                        nameBuffer += chars.uppercased()
                        renderSlots()
                    }
                }
                return
            }

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

    private func confirmName() {
        guard let idx = activeNameSlot else { return }
        let trimmed = nameBuffer.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? "P\(idx + 1)" : trimmed
        UserDefaults.standard.set(name, forKey: "player_name_\(idx)")
        activeNameSlot = nil
        nameBuffer = ""
        let atMax = manager.slots.count >= ControllerManager.maxPlayers
        manager.setJoinEnabled(!atMax)
        renderSlots()
    }

    private func makeIconNode() -> SKNode {
        let container = SKNode()

        let red = Shapes.shipV(color: ControllerManager.playerColors[0], scale: 1.2)
        red.position = CGPoint(x: -22, y: -7)
        red.zRotation = 0.14
        container.addChild(red)

        let blue = Shapes.shipV(color: ControllerManager.playerColors[1], scale: 1.2)
        blue.position = CGPoint(x: 22, y: 5)
        blue.zRotation = 2.90
        container.addChild(blue)

        let rock = Shapes.asteroid(radius: 12, seed: 42)
        rock.position = CGPoint(x: -32, y: 34)
        container.addChild(rock)

        return container
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

            let storedName = UserDefaults.standard.string(forKey: "player_name_\(i)") ?? "P\(i + 1)"
            let displayText: String
            if activeNameSlot == i {
                displayText = nameBuffer + "_"
            } else if claimed {
                displayText = storedName
            } else {
                displayText = ""
            }
            if !displayText.isEmpty {
                let nameLabel = SKLabelNode(text: displayText)
                nameLabel.fontName = "AvenirNext-Regular"
                nameLabel.fontSize = 14
                nameLabel.fontColor = color
                nameLabel.position = CGPoint(x: x, y: y - 69)
                slotsLayer.addChild(nameLabel)
            }
        }
    }
}
