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
    private var selectedLevel: Int = GameSettings.lastPlayedLevel
    private var selectedMode: GameMode = GameSettings.lastMode

    private var modeLabel: SKLabelNode!
    private var levelLabel: SKLabelNode!
    private var battleHintLabel: SKLabelNode!
    private var dpadEdge: [ObjectIdentifier: (left: Bool, right: Bool, up: Bool, down: Bool)] = [:]

    override func didMove(to view: SKView) {
        backgroundColor = .black

        // Poster background — aspect-fill so the landscape image covers the
        // whole screen on any aspect ratio (iPad 4:3 crops sides slightly,
        // 16:9 displays fit exactly).
        let posterTexture = SKTexture(imageNamed: "Splash")
        let imgSize = posterTexture.size()
        let scale = max(size.width / imgSize.width, size.height / imgSize.height)
        let poster = SKSpriteNode(texture: posterTexture)
        poster.size = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        poster.position = CGPoint(x: size.width / 2, y: size.height / 2)
        poster.zPosition = -1
        addChild(poster)

        let hint = SKLabelNode(text: "PRESS A TO JOIN  ·  START / SPACE TO BEGIN")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 18
        hint.fontColor = SKColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: size.width / 2, y: size.height * 0.04)
        addChild(hint)

        let leaderboardX: CGFloat = 30
        let safeTopInset = view.safeAreaInsets.top
        let leaderboardTopY = size.height - safeTopInset - 80

        let heading = SKLabelNode(text: "HIGHSCORES")
        heading.fontName = "AvenirNext-Bold"
        heading.fontSize = 22
        heading.fontColor = SKColor(red: 245/255, green: 194/255, blue: 66/255, alpha: 1)
        heading.horizontalAlignmentMode = .left
        heading.verticalAlignmentMode = .top
        heading.position = CGPoint(x: leaderboardX, y: leaderboardTopY)
        addChild(heading)

        let firstEntryColor  = SKColor(red: 231/255, green: 63/255,  blue: 150/255, alpha: 1)
        let otherEntryColor  = SKColor(red: 98/255,  green: 212/255, blue: 214/255, alpha: 1)
        let nameX:  CGFloat = leaderboardX
        let levelX: CGFloat = leaderboardX + 90
        let scoreX: CGFloat = leaderboardX + 175
        let firstEntryGap: CGFloat = 40
        for (i, entry) in HighScore.top.enumerated() {
            let y = leaderboardTopY - firstEntryGap - CGFloat(24 * i)
            let color = i == 0 ? firstEntryColor : otherEntryColor

            let nameLabel = SKLabelNode(text: entry.name)
            nameLabel.fontName = "AvenirNext-Regular"
            nameLabel.fontSize = 14
            nameLabel.fontColor = color
            nameLabel.horizontalAlignmentMode = .left
            nameLabel.verticalAlignmentMode = .top
            nameLabel.position = CGPoint(x: nameX, y: y)
            addChild(nameLabel)

            let levelLabel = SKLabelNode(text: entry.level.map { "L\($0)" } ?? "")
            levelLabel.fontName = "AvenirNext-Regular"
            levelLabel.fontSize = 14
            levelLabel.fontColor = color
            levelLabel.horizontalAlignmentMode = .left
            levelLabel.verticalAlignmentMode = .top
            levelLabel.position = CGPoint(x: levelX, y: y)
            addChild(levelLabel)

            let scoreLabel = SKLabelNode(text: "\(entry.score)")
            scoreLabel.fontName = "AvenirNext-Regular"
            scoreLabel.fontSize = 14
            scoreLabel.fontColor = color
            scoreLabel.horizontalAlignmentMode = .right
            scoreLabel.verticalAlignmentMode = .top
            scoreLabel.position = CGPoint(x: scoreX, y: y)
            addChild(scoreLabel)
        }

        // Selectors anchored top-right, proportional to screen size.
        let selectorX = size.width * 0.93
        let modeY     = size.height * 0.92
        let levelY    = size.height * 0.84
        let battleHintY = size.height * 0.78

        let modeLeft = SKLabelNode(text: "<")
        modeLeft.fontName = "AvenirNext-Regular"
        modeLeft.fontSize = 22
        modeLeft.fontColor = SKColor(white: 0.55, alpha: 1)
        modeLeft.position = CGPoint(x: selectorX - 40, y: modeY)
        addChild(modeLeft)

        let modeRight = SKLabelNode(text: ">")
        modeRight.fontName = "AvenirNext-Regular"
        modeRight.fontSize = 22
        modeRight.fontColor = SKColor(white: 0.55, alpha: 1)
        modeRight.position = CGPoint(x: selectorX + 40, y: modeY)
        addChild(modeRight)

        let mode = SKLabelNode(text: "")
        mode.fontName = "AvenirNext-Bold"
        mode.fontSize = 26
        mode.position = CGPoint(x: selectorX, y: modeY)
        addChild(mode)
        self.modeLabel = mode

        let modeCaption = SKLabelNode(text: "MODE")
        modeCaption.fontName = "AvenirNext-Regular"
        modeCaption.fontSize = 12
        modeCaption.fontColor = SKColor(white: 0.45, alpha: 1)
        modeCaption.position = CGPoint(x: selectorX, y: modeY - 24)
        addChild(modeCaption)

        let levelLeft = SKLabelNode(text: "<")
        levelLeft.fontName = "AvenirNext-Regular"
        levelLeft.fontSize = 22
        levelLeft.fontColor = SKColor(white: 0.55, alpha: 1)
        levelLeft.position = CGPoint(x: selectorX - 40, y: levelY)
        addChild(levelLeft)

        let levelRight = SKLabelNode(text: ">")
        levelRight.fontName = "AvenirNext-Regular"
        levelRight.fontSize = 22
        levelRight.fontColor = SKColor(white: 0.55, alpha: 1)
        levelRight.position = CGPoint(x: selectorX + 40, y: levelY)
        addChild(levelRight)

        let level = SKLabelNode(text: "")
        level.fontName = "AvenirNext-Bold"
        level.fontSize = 26
        level.position = CGPoint(x: selectorX, y: levelY)
        addChild(level)
        self.levelLabel = level

        let levelCaption = SKLabelNode(text: "LEVEL")
        levelCaption.fontName = "AvenirNext-Regular"
        levelCaption.fontSize = 12
        levelCaption.fontColor = SKColor(white: 0.45, alpha: 1)
        levelCaption.position = CGPoint(x: selectorX, y: levelY - 24)
        addChild(levelCaption)

        let battleHint = SKLabelNode(text: "BATTLE NEEDS 2+ PLAYERS")
        battleHint.fontName = "AvenirNext-Regular"
        battleHint.fontSize = 12
        battleHint.fontColor = SKColor(red: 0.7, green: 0.4, blue: 0.4, alpha: 1)
        battleHint.position = CGPoint(x: selectorX, y: battleHintY)
        battleHint.alpha = 0
        addChild(battleHint)
        self.battleHintLabel = battleHint

        let helpHint = SKLabelNode(text: "[H] HELP")
        helpHint.fontName = "AvenirNext-Regular"
        helpHint.fontSize = 14
        helpHint.fontColor = SKColor(white: 0.55, alpha: 1)
        helpHint.horizontalAlignmentMode = .right
        helpHint.position = CGPoint(x: size.width - 30, y: 30)
        addChild(helpHint)

        renderSelectors()

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
            self.renderSelectors()
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
        if selectedMode == .battle && manager.slots.count < 2 {
            return
        }
        transitioning = true
        GameSettings.lastPlayedLevel = selectedLevel
        GameSettings.lastMode = selectedMode
        let next = GameScene(size: size, level: selectedLevel, mode: selectedMode)
        next.scaleMode = scaleMode
        view?.presentScene(next, transition: .fade(withDuration: 0.4))
    }

    private func openHelp() {
        guard !transitioning, activeNameSlot == nil else { return }
        transitioning = true
        let help = HelpScene(size: size)
        help.scaleMode = scaleMode
        view?.presentScene(help, transition: .fade(withDuration: 0.3))
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
            // Name entry active. A rising edge of any controller's buttonA
            // confirms the current entry — gives controller-only setups a
            // way out of name entry without a keyboard.
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

        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)

            // D-pad selector input. Treat extendedGamepad and microGamepad
            // d-pads identically. Edge-trigger so a held d-pad doesn't spin.
            let dx: Float
            let dy: Float
            if let gp = c.extendedGamepad {
                dx = gp.dpad.xAxis.value
                dy = gp.dpad.yAxis.value
            } else if let mg = c.microGamepad {
                dx = mg.dpad.xAxis.value
                dy = mg.dpad.yAxis.value
            } else {
                dx = 0; dy = 0
            }
            let prev = dpadEdge[id] ?? (false, false, false, false)
            let curr = (left:  dx < -0.5,
                        right: dx >  0.5,
                        up:    dy >  0.5,
                        down:  dy < -0.5)
            let nameEntryActive: Bool = {
                if activeNameSlot != nil { return true }
                #if os(tvOS)
                if NameEntryCoordinator.shared.request != nil { return true }
                #endif
                return false
            }()
            if !nameEntryActive {
                if curr.left  && !prev.left  { cycleMode(by: -1) }
                if curr.right && !prev.right { cycleMode(by:  1) }
                if curr.up    && !prev.up    { cycleLevel(by:  1) }
                if curr.down  && !prev.down  { cycleLevel(by: -1) }
            }
            dpadEdge[id] = curr

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

        if activeNameSlot == nil {
            switch code {
            case .keyM:      cycleMode(by: 1); return
            case .upArrow:   cycleLevel(by: 1); return
            case .downArrow: cycleLevel(by: -1); return
            default: break
            }
        }

        switch code {
        case .keyA:
            if !manager.hasKeyboardPlayer,
               manager.slots.count < ControllerManager.maxPlayers {
                manager.claimKeyboard()
            } else if let kbSlotIndex = manager.slots.firstIndex(where: { $0.keyboard != nil }) {
                // Re-open name editor for the keyboard slot.
                let current = UserDefaults.standard.string(
                    forKey: "player_name_\(kbSlotIndex)") ?? "P\(kbSlotIndex + 1)"
                activeNameSlot = kbSlotIndex
                nameBuffer = current
                manager.setJoinEnabled(false)
                renderSlots()
            }
        case .keyH:
            openHelp()
        case .spacebar, .returnOrEnter, .keypadEnter:
            tryStart()
        case .escape:
            MacFullScreen.exitIfActive()
        default:
            break
        }
    }


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

    private func renderSelectors() {
        let battleAvailable = manager.slots.count >= 2

        if selectedMode == .battle && !battleAvailable {
            selectedMode = .survival
        }

        modeLabel.text = selectedMode == .survival ? "SURVIVAL" : "BATTLE"
        modeLabel.fontColor = selectedMode == .survival
            ? SKColor.white
            : SKColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1)

        if !battleAvailable {
            modeLabel.fontColor = SKColor(white: 0.6, alpha: 1)
        }

        levelLabel.text = "L \(selectedLevel)"
        levelLabel.fontColor = .white

        battleHintLabel.alpha = battleAvailable ? 0 : 1
    }

    private func cycleMode(by delta: Int) {
        let battleAvailable = manager.slots.count >= 2
        if !battleAvailable { return }
        selectedMode = (selectedMode == .survival) ? .battle : .survival
        renderSelectors()
    }

    private func cycleLevel(by delta: Int) {
        var next = selectedLevel + delta
        if next < 1 { next = 9 }
        if next > 9 { next = 1 }
        selectedLevel = next
        renderSelectors()
    }
}
