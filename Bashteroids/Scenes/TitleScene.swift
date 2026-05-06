import SpriteKit
import GameController

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

    override func didMove(to view: SKView) {
        backgroundColor = .black

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

        let leaderboardX: CGFloat = 30
        let safeTopInset = view.safeAreaInsets.top
        let leaderboardTopY = size.height - safeTopInset - 80

        let heading = SKLabelNode(text: "HIGHSCORES")
        heading.fontName = "AvenirNext-Bold"
        heading.fontSize = 16
        heading.fontColor = ControllerManager.playerColors[0]
        heading.horizontalAlignmentMode = .left
        heading.verticalAlignmentMode = .top
        heading.position = CGPoint(x: leaderboardX, y: leaderboardTopY)
        addChild(heading)

        for (i, entry) in HighScore.top.enumerated() {
            let levelTag = entry.level.map { " L\($0)" } ?? ""
            let row = SKLabelNode(text: "\(entry.name)\(levelTag): \(entry.score)")
            row.fontName = "AvenirNext-Regular"
            row.fontSize = 14
            row.fontColor = ControllerManager.playerColors[1]
            row.horizontalAlignmentMode = .left
            row.verticalAlignmentMode = .top
            row.position = CGPoint(x: leaderboardX,
                                   y: leaderboardTopY - CGFloat(24 * (i + 1)))
            addChild(row)
        }

        let icon = makeIconNode()
        icon.position = CGPoint(x: size.width - 80, y: size.height - 90)
        addChild(icon)

        #if DEBUG
        let dbg = SKLabelNode(text: "[DEBUG] START LEVEL: \(DebugSettings.startLevel)")
        dbg.fontName = "AvenirNext-Regular"
        dbg.fontSize = 12
        dbg.fontColor = SKColor(white: 0.5, alpha: 1)
        dbg.horizontalAlignmentMode = .right
        dbg.position = CGPoint(x: size.width - 20, y: size.height - 150)
        dbg.name = "debug-start-level"
        addChild(dbg)
        #endif

        addChild(slotsLayer)
        renderSlots()

        manager.onSlotsChanged = { [weak self] in
            guard let self else { return }
            let newCount = self.manager.slots.count
            if newCount > self.prevSlotCount {
                let idx = newCount - 1
                let current = UserDefaults.standard.string(
                    forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
                #if os(tvOS)
                self.beginCoordinatorNameEntry(slot: idx, current: current)
                #else
                self.activeNameSlot = idx
                self.nameBuffer = current
                self.manager.setJoinEnabled(false)
                #endif
            }
            self.prevSlotCount = newCount
            self.renderSlots()
        }
        manager.onStartPressed = { [weak self] in self?.tryStart() }
        manager.setJoinEnabled(true)

        KeyboardManager.shared.onKeyDown = { [weak self] code in
            self?.handleKeyDown(code)
        }
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

        let nameEntryActive: Bool
        #if os(tvOS)
        nameEntryActive = NameEntryCoordinator.shared.request != nil
        #else
        nameEntryActive = activeNameSlot != nil
        #endif

        if !nameEntryActive {
            for (i, slot) in manager.slots.enumerated() {
                let pressed = slot.controller?.extendedGamepad?.buttonA.isPressed
                    ?? slot.controller?.microGamepad?.buttonA.isPressed
                    ?? false
                let was = slotAWasPressed[i] ?? false
                if pressed && !was {
                    let current = UserDefaults.standard.string(
                        forKey: "player_name_\(i)") ?? "P\(i + 1)"
                    #if os(tvOS)
                    beginCoordinatorNameEntry(slot: i, current: current)
                    #else
                    activeNameSlot = i
                    nameBuffer = current
                    manager.setJoinEnabled(false)
                    renderSlots()
                    #endif
                    break
                }
                slotAWasPressed[i] = pressed
            }
        } else {
            for (i, slot) in manager.slots.enumerated() {
                slotAWasPressed[i] = slot.controller?.extendedGamepad?.buttonA.isPressed
                    ?? slot.controller?.microGamepad?.buttonA.isPressed
                    ?? false
            }
        }

        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)

            // Menu button: Siri Remote's Menu is system-reserved (returns to
            // home screen). Only poll it for MFi controllers.
            let menuPressed = c.extendedGamepad?.buttonMenu.isPressed ?? false
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
    }

    private func handleKeyDown(_ code: GCKeyCode) {
        if activeNameSlot != nil {
            switch code {
            case .returnOrEnter, .keypadEnter:
                confirmName()
            case .deleteOrBackspace:
                if !nameBuffer.isEmpty { nameBuffer.removeLast(); renderSlots() }
            default:
                if let ch = TitleScene.charFor(keyCode: code), nameBuffer.count < 8 {
                    nameBuffer.append(ch)
                    renderSlots()
                }
            }
            return
        }

        #if DEBUG
        if let digit = TitleScene.digit(for: code) {
            DebugSettings.startLevel = max(1, digit)
            if let label = childNode(withName: "debug-start-level") as? SKLabelNode {
                label.text = "[DEBUG] START LEVEL: \(DebugSettings.startLevel)"
            }
            return
        }
        #endif

        switch code {
        case .keyA:
            if !manager.hasKeyboardPlayer,
               manager.slots.count < ControllerManager.maxPlayers {
                manager.claimKeyboard()
            }
        case .spacebar, .returnOrEnter, .keypadEnter:
            tryStart()
        case .escape:
            MacFullScreen.exitIfActive()
        default:
            break
        }
    }

    #if DEBUG
    private static func digit(for code: GCKeyCode) -> Int? {
        switch code {
        case .zero:  return 0
        case .one:   return 1
        case .two:   return 2
        case .three: return 3
        case .four:  return 4
        case .five:  return 5
        case .six:   return 6
        case .seven: return 7
        case .eight: return 8
        case .nine:  return 9
        default:     return nil
        }
    }
    #endif

    private static func charFor(keyCode code: GCKeyCode) -> Character? {
        switch code {
        case .keyA: return "A"
        case .keyB: return "B"
        case .keyC: return "C"
        case .keyD: return "D"
        case .keyE: return "E"
        case .keyF: return "F"
        case .keyG: return "G"
        case .keyH: return "H"
        case .keyI: return "I"
        case .keyJ: return "J"
        case .keyK: return "K"
        case .keyL: return "L"
        case .keyM: return "M"
        case .keyN: return "N"
        case .keyO: return "O"
        case .keyP: return "P"
        case .keyQ: return "Q"
        case .keyR: return "R"
        case .keyS: return "S"
        case .keyT: return "T"
        case .keyU: return "U"
        case .keyV: return "V"
        case .keyW: return "W"
        case .keyX: return "X"
        case .keyY: return "Y"
        case .keyZ: return "Z"
        case .zero: return "0"
        case .one: return "1"
        case .two: return "2"
        case .three: return "3"
        case .four: return "4"
        case .five: return "5"
        case .six: return "6"
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .spacebar: return " "
        default: return nil
        }
    }

    private func confirmName() {
        guard let idx = activeNameSlot else { return }
        let trimmed = nameBuffer.trimmingCharacters(in: .whitespaces)
        let previous = UserDefaults.standard.string(forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
        let name = trimmed.isEmpty ? previous : trimmed
        UserDefaults.standard.set(name, forKey: "player_name_\(idx)")
        activeNameSlot = nil
        nameBuffer = ""
        let atMax = manager.slots.count >= ControllerManager.maxPlayers
        manager.setJoinEnabled(!atMax)
        renderSlots()
    }

    #if os(tvOS)
    private func beginCoordinatorNameEntry(slot idx: Int, current: String) {
        manager.setJoinEnabled(false)
        renderSlots()
        NameEntryCoordinator.shared.requestName(forSlot: idx, current: current) { [weak self] entered in
            guard let self else { return }
            let trimmed = entered?.trimmingCharacters(in: .whitespaces) ?? ""
            let final = trimmed.isEmpty ? current : trimmed
            UserDefaults.standard.set(final, forKey: "player_name_\(idx)")
            let atMax = self.manager.slots.count >= ControllerManager.maxPlayers
            self.manager.setJoinEnabled(!atMax)
            self.renderSlots()
        }
    }
    #endif

    private func makeIconNode() -> SKNode {
        let container = SKNode()

        let rock = Shapes.asteroid(radius: 13, seed: 42)
        rock.position = CGPoint(x: -22, y: 24)
        container.addChild(rock)

        let red = Shapes.shipV(color: ControllerManager.playerColors[0], scale: 1.3)
        red.position = CGPoint(x: -20, y: -22)
        red.zRotation = -2.01
        container.addChild(red)

        let blue = Shapes.shipV(color: ControllerManager.playerColors[1], scale: 1.3)
        blue.position = CGPoint(x: 22, y: -5)
        blue.zRotation = 0.37
        container.addChild(blue)

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
