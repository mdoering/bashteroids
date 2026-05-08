import SpriteKit
import GameController

final class TitleScene: SKScene {
    private static let accentGold = SKColor(red: 245/255, green: 194/255, blue: 66/255, alpha: 1)

    private let manager = ControllerManager.shared
    private let slotsLayer = SKNode()
    private var transitioning = false
    private var menuWasPressed: [ObjectIdentifier: Bool] = [:]
    private var xWasPressed: [ObjectIdentifier: Bool] = [:]
    private var aWasPressed: [ObjectIdentifier: Bool] = [:]
    private var activeNameSlot: Int? = nil
    private var nameBuffer: String = ""
    /// While name entry is active, which recent-names suggestion (0-based)
    /// is currently highlighted. -1 means "the buffer wins" — user has typed
    /// (or just opened the editor), suggestions are not the active selection.
    private var nameSuggestionIndex: Int = -1
    private var prevClaimedIndices: Set<Int> = []
    private var slotAWasPressed: [Int: Bool] = [:]
    private var selectedLevel: Int = GameSettings.lastPlayedLevel
    private var selectedMode: GameMode = GameSettings.lastMode
    private var selectedDensity: PowerUpDensity = GameSettings.sessionPowerUpDensity
    private var selectedAudio: AudioMode = GameSettings.audioMode

    private enum FocusItem: CaseIterable { case mode, level, density, help, audio }
    private var focused: FocusItem = .mode

    private var modeLabel: SKLabelNode!
    private var levelLabel: SKLabelNode!
    private var densityLabel: SKLabelNode!
    private var densityCaption: SKLabelNode!
    private var battleHintLabel: SKLabelNode!
    private var helpLabel: SKLabelNode!
    private var modeLeftArrow: SKLabelNode!
    private var modeRightArrow: SKLabelNode!
    private var levelLeftArrow: SKLabelNode!
    private var levelRightArrow: SKLabelNode!
    private var joinHintLabel: SKLabelNode!
    private var densityLeftArrow: SKLabelNode!
    private var densityRightArrow: SKLabelNode!
    private var audioLabel: SKLabelNode!
    private var audioCaption: SKLabelNode!
    private var audioLeftArrow: SKLabelNode!
    private var audioRightArrow: SKLabelNode!
    private var dpadEdge: [ObjectIdentifier: (left: Bool, right: Bool, up: Bool, down: Bool)] = [:]
    private var titleTapObserver: NSObjectProtocol?
    private var titleLongPressObserver: NSObjectProtocol?

    override func didMove(to view: SKView) {
        backgroundColor = .black

        TouchOverlayState.shared.setScene(.title)
        MusicPlayer.shared.play(resource: "rivers", ext: "m4a", volume: 0.6)
        titleTapObserver = NotificationCenter.default.addObserver(
            forName: .titleSceneTap, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let location = note.userInfo?["location"] as? CGPoint else { return }
            MainActor.assumeIsolated { self.handleTouchTap(at: location) }
        }
        titleLongPressObserver = NotificationCenter.default.addObserver(
            forName: .titleSceneLongPress, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let location = note.userInfo?["location"] as? CGPoint else { return }
            MainActor.assumeIsolated { self.handleTouchLongPress(at: location) }
        }

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
        self.joinHintLabel = hint

        let edgeMargin: CGFloat = 30
        let leaderboardX: CGFloat = edgeMargin
        let safeTopInset = view.safeAreaInsets.top
        let topAnchorY = size.height - safeTopInset - 60

        let nameX:  CGFloat = leaderboardX
        let levelX: CGFloat = leaderboardX + 90
        let scoreX: CGFloat = leaderboardX + 175
        let tableWidth = scoreX - nameX

        let heading = SKLabelNode(text: "HIGHSCORES")
        heading.fontName = "AvenirNext-Bold"
        heading.fontSize = 22
        heading.fontColor = TitleScene.accentGold
        heading.horizontalAlignmentMode = .left
        heading.verticalAlignmentMode = .top
        heading.position = CGPoint(x: leaderboardX, y: topAnchorY)
        addChild(heading)
        // Scale heading font up so its rendered width matches the table width below.
        if heading.frame.width > 0 {
            heading.fontSize *= tableWidth / heading.frame.width
        }

        let firstEntryColor  = SKColor(red: 231/255, green: 63/255,  blue: 150/255, alpha: 1)
        let otherEntryColor  = SKColor(red: 98/255,  green: 212/255, blue: 214/255, alpha: 1)
        let firstEntryY = topAnchorY - heading.frame.height - 16
        for (i, entry) in HighScore.top.enumerated() {
            let y = firstEntryY - CGFloat(24 * i)
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

        // Selectors anchored top-right with the same edgeMargin and topAnchorY
        // as the highscore column, so both blocks align at the top with
        // matching border spacing.
        let arrowGap: CGFloat = 14
        let valueHalfWidth: CGFloat = 60   // half of widest value ("SURVIVAL" / "LEVEL 9") at 26pt bold
        let selectorRightX = size.width - edgeMargin       // right edge of the > arrow
        let selectorCenterX = selectorRightX - 12 - arrowGap - valueHalfWidth   // center of the value label
        let modeY  = topAnchorY
        let levelY = topAnchorY - 50
        let densityY = levelY - 50
        let densityCaptionY = densityY - 28
        let battleHintY = densityCaptionY - 30

        let modeLeft = SKLabelNode(text: "<")
        modeLeft.fontName = "AvenirNext-Regular"
        modeLeft.fontSize = 22
        modeLeft.fontColor = TitleScene.accentGold
        modeLeft.verticalAlignmentMode = .top
        modeLeft.horizontalAlignmentMode = .right
        modeLeft.position = CGPoint(x: selectorCenterX - valueHalfWidth - arrowGap, y: modeY)
        addChild(modeLeft)
        self.modeLeftArrow = modeLeft

        let modeRight = SKLabelNode(text: ">")
        modeRight.fontName = "AvenirNext-Regular"
        modeRight.fontSize = 22
        modeRight.fontColor = TitleScene.accentGold
        modeRight.verticalAlignmentMode = .top
        modeRight.horizontalAlignmentMode = .right
        modeRight.position = CGPoint(x: selectorRightX, y: modeY)
        addChild(modeRight)
        self.modeRightArrow = modeRight

        let mode = SKLabelNode(text: "")
        mode.fontName = "AvenirNext-Bold"
        mode.fontSize = 26
        mode.verticalAlignmentMode = .top
        mode.position = CGPoint(x: selectorCenterX, y: modeY)
        addChild(mode)
        self.modeLabel = mode

        let levelLeft = SKLabelNode(text: "<")
        levelLeft.fontName = "AvenirNext-Regular"
        levelLeft.fontSize = 22
        levelLeft.fontColor = TitleScene.accentGold
        levelLeft.verticalAlignmentMode = .top
        levelLeft.horizontalAlignmentMode = .right
        levelLeft.position = CGPoint(x: selectorCenterX - valueHalfWidth - arrowGap, y: levelY)
        addChild(levelLeft)
        self.levelLeftArrow = levelLeft

        let levelRight = SKLabelNode(text: ">")
        levelRight.fontName = "AvenirNext-Regular"
        levelRight.fontSize = 22
        levelRight.fontColor = TitleScene.accentGold
        levelRight.verticalAlignmentMode = .top
        levelRight.horizontalAlignmentMode = .right
        levelRight.position = CGPoint(x: selectorRightX, y: levelY)
        addChild(levelRight)
        self.levelRightArrow = levelRight

        let level = SKLabelNode(text: "")
        level.fontName = "AvenirNext-Bold"
        level.fontSize = 26
        level.verticalAlignmentMode = .top
        level.position = CGPoint(x: selectorCenterX, y: levelY)
        addChild(level)
        self.levelLabel = level

        let densityLeft = SKLabelNode(text: "<")
        densityLeft.fontName = "AvenirNext-Regular"
        densityLeft.fontSize = 22
        densityLeft.fontColor = TitleScene.accentGold
        densityLeft.verticalAlignmentMode = .top
        densityLeft.horizontalAlignmentMode = .right
        densityLeft.position = CGPoint(x: selectorCenterX - valueHalfWidth - arrowGap, y: densityY)
        addChild(densityLeft)
        self.densityLeftArrow = densityLeft

        let densityRight = SKLabelNode(text: ">")
        densityRight.fontName = "AvenirNext-Regular"
        densityRight.fontSize = 22
        densityRight.fontColor = TitleScene.accentGold
        densityRight.verticalAlignmentMode = .top
        densityRight.horizontalAlignmentMode = .right
        densityRight.position = CGPoint(x: selectorRightX, y: densityY)
        addChild(densityRight)
        self.densityRightArrow = densityRight

        let densityValue = SKLabelNode(text: "")
        densityValue.fontName = "AvenirNext-Bold"
        densityValue.fontSize = 26
        densityValue.verticalAlignmentMode = .top
        densityValue.position = CGPoint(x: selectorCenterX, y: densityY)
        addChild(densityValue)
        self.densityLabel = densityValue

        let densityCap = SKLabelNode(text: "POWERUPS")
        densityCap.fontName = "AvenirNext-Regular"
        densityCap.fontSize = 12
        densityCap.fontColor = SKColor(white: 0.55, alpha: 1)
        densityCap.verticalAlignmentMode = .top
        densityCap.position = CGPoint(x: selectorCenterX, y: densityCaptionY)
        addChild(densityCap)
        self.densityCaption = densityCap

        let battleHint = SKLabelNode(text: "BATTLE NEEDS 2+ PLAYERS")
        battleHint.fontName = "AvenirNext-Regular"
        battleHint.fontSize = 12
        battleHint.fontColor = SKColor(red: 0.7, green: 0.4, blue: 0.4, alpha: 1)
        battleHint.verticalAlignmentMode = .top
        battleHint.position = CGPoint(x: selectorCenterX, y: battleHintY)
        battleHint.alpha = 0
        addChild(battleHint)
        self.battleHintLabel = battleHint

        let helpL = SKLabelNode(text: "[H] HELP")
        helpL.fontName = "AvenirNext-Bold"
        helpL.fontSize = 14
        helpL.fontColor = TitleScene.accentGold
        helpL.horizontalAlignmentMode = .right
        helpL.position = CGPoint(x: size.width - 30, y: 30)
        addChild(helpL)
        self.helpLabel = helpL

        // Audio selector — lower-left corner, mirroring the right-side
        // selectors but anchored to the left edge.
        let audioY = size.height * 0.10
        let audioSelectorLeftX = edgeMargin
        let audioSelectorCenterX = audioSelectorLeftX + 12 + arrowGap + valueHalfWidth

        let audioLeft = SKLabelNode(text: "<")
        audioLeft.fontName = "AvenirNext-Regular"
        audioLeft.fontSize = 22
        audioLeft.fontColor = TitleScene.accentGold
        audioLeft.verticalAlignmentMode = .top
        audioLeft.horizontalAlignmentMode = .left
        audioLeft.position = CGPoint(x: audioSelectorLeftX, y: audioY)
        addChild(audioLeft)
        self.audioLeftArrow = audioLeft

        let audioRight = SKLabelNode(text: ">")
        audioRight.fontName = "AvenirNext-Regular"
        audioRight.fontSize = 22
        audioRight.fontColor = TitleScene.accentGold
        audioRight.verticalAlignmentMode = .top
        audioRight.horizontalAlignmentMode = .left
        audioRight.position = CGPoint(x: audioSelectorCenterX + valueHalfWidth + arrowGap, y: audioY)
        addChild(audioRight)
        self.audioRightArrow = audioRight

        let audioValue = SKLabelNode(text: "")
        audioValue.fontName = "AvenirNext-Bold"
        audioValue.fontSize = 26
        audioValue.verticalAlignmentMode = .top
        audioValue.position = CGPoint(x: audioSelectorCenterX, y: audioY)
        addChild(audioValue)
        self.audioLabel = audioValue

        let audioCap = SKLabelNode(text: "AUDIO")
        audioCap.fontName = "AvenirNext-Regular"
        audioCap.fontSize = 12
        audioCap.fontColor = SKColor(white: 0.55, alpha: 1)
        audioCap.verticalAlignmentMode = .top
        audioCap.position = CGPoint(x: audioSelectorCenterX, y: audioY - 28)
        addChild(audioCap)
        self.audioCaption = audioCap

        renderSelectors()

        addChild(slotsLayer)
        renderSlots()

        manager.onSlotsChanged = { [weak self] in
            guard let self else { return }
            let currentIndices = Set(self.manager.slots.map { $0.index })
            let newlyAdded = currentIndices.subtracting(self.prevClaimedIndices).sorted()
            if let idx = newlyAdded.first {
                let newSlot = self.manager.slots.first(where: { $0.index == idx })
                // Touch players skip the editor — they have no keyboard to
                // type with and the inline editor would block game start.
                // They get the slot's last-stored name (or "P\(idx+1)" on
                // first launch); a name editor flow for touch players is
                // a follow-up.
                let isTouchSlot = newSlot?.touchInput != nil
                if !isTouchSlot {
                    let current = UserDefaults.standard.string(
                        forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
                    #if os(tvOS)
                    self.beginCoordinatorNameEntry(slot: idx, current: current)
                    #else
                    self.activeNameSlot = idx
                    self.nameBuffer = current
                    self.nameSuggestionIndex = -1
                    self.manager.setJoinEnabled(false)
                    #endif
                }
            }
            self.prevClaimedIndices = currentIndices
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
        if let obs = titleTapObserver {
            NotificationCenter.default.removeObserver(obs)
            titleTapObserver = nil
        }
        if let obs = titleLongPressObserver {
            NotificationCenter.default.removeObserver(obs)
            titleLongPressObserver = nil
        }
        TouchOverlayState.shared.setScene(.other)
        // Music is NOT stopped here — willMove(from:) on the old scene fires
        // *after* didMove(to:) on the new scene in SpriteKit transitions, so
        // stopping here would clobber the next scene's just-started track.
        // Each scene's didMove is responsible for setting the desired audio
        // state (TitleScene plays rivers, HelpScene plays help, GameScene
        // stops music outright).
    }

    /// Hit-test the slot tile rects against a SwiftUI-forwarded tap location
    /// (already in scene coords). On a hit on an empty tile, claim it for
    /// the touch player.
    private func handleTouchTap(at point: CGPoint) {
        guard !manager.hasTouchPlayer else { return }
        if let i = slotTileIndex(at: point), manager.emptySlotIndices().contains(i) {
            manager.claimTouch(atSlot: i)
        }
    }

    /// Long-press on a claimed touch slot opens the SwiftUI name editor
    /// overlay so the touch player can edit their name with the on-screen
    /// keyboard. Long-presses elsewhere (empty tiles, off-tile area) are
    /// no-ops.
    private func handleTouchLongPress(at point: CGPoint) {
        guard activeNameSlot == nil,
              let i = slotTileIndex(at: point),
              let slot = manager.slots.first(where: { $0.index == i }),
              slot.touchInput != nil else { return }
        let current = UserDefaults.standard.string(
            forKey: "player_name_\(i)") ?? "P\(i + 1)"
        beginCoordinatorNameEntry(slot: i, current: current)
    }

    /// Returns the slot tile index whose rect contains `point`, or nil.
    private func slotTileIndex(at point: CGPoint) -> Int? {
        let count = ControllerManager.maxPlayers
        let tileWidth: CGFloat = 110
        let spacing: CGFloat = 24
        let totalWidth = CGFloat(count) * tileWidth + CGFloat(count - 1) * spacing
        let startX = (size.width - totalWidth) / 2 + tileWidth / 2
        let y = size.height * 0.46
        for i in 0..<count {
            let cx = startX + CGFloat(i) * (tileWidth + spacing)
            let rect = CGRect(x: cx - tileWidth / 2, y: y - tileWidth / 2,
                              width: tileWidth, height: tileWidth)
            if rect.contains(point) { return i }
        }
        return nil
    }

    private func tryStart() {
        guard !transitioning, activeNameSlot == nil else { return }
        if manager.slots.isEmpty {
            flashJoinHint()
            return
        }
        if selectedMode == .battle && manager.slots.count < 2 {
            flashBattleHint()
            return
        }
        transitioning = true
        GameSettings.lastPlayedLevel = selectedLevel
        GameSettings.lastMode = selectedMode
        GameSettings.sessionPowerUpDensity = selectedDensity
        let next = GameScene(size: size, level: selectedLevel, mode: selectedMode,
                             density: selectedDensity)
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

            // Claimed controllers: A = "confirm focused" (cycle / open help).
            // Unclaimed controllers' A is still handled by the join handler in
            // ControllerManager and consults intendedSlotIndex(for:). aWasPressed
            // is updated unconditionally so a held A-press across the
            // unclaimed→claimed transition doesn't mis-fire on the first frame
            // post-claim.
            let aPressed = c.extendedGamepad?.buttonA.isPressed
                ?? c.microGamepad?.buttonA.isPressed
                ?? false
            let aWas = aWasPressed[id] ?? false
            if aPressed && !aWas
                && manager.slot(for: c) != nil
                && !nameEntryActive
            {
                confirmFocused()
            }
            aWasPressed[id] = aPressed
        }
    }

    private func handleKeyDown(_ code: GCKeyCode) {
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
        case .keyA, .returnOrEnter, .keypadEnter:
            // Claim the keyboard slot, or re-open the name editor for an
            // already-claimed keyboard player. Enter is intentionally NOT
            // a "start game" key — only Space starts.
            if !manager.hasKeyboardPlayer,
               manager.slots.count < ControllerManager.maxPlayers {
                manager.claimKeyboard()
            } else if let kbSlotIndex = manager.slots.firstIndex(where: { $0.keyboard != nil }) {
                let current = UserDefaults.standard.string(
                    forKey: "player_name_\(kbSlotIndex)") ?? "P\(kbSlotIndex + 1)"
                activeNameSlot = kbSlotIndex
                nameBuffer = current
                nameSuggestionIndex = -1
                manager.setJoinEnabled(false)
                renderSlots()
            }
        case .spacebar:
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
        RecentNames.record(name)
        activeNameSlot = nil
        nameBuffer = ""
        nameSuggestionIndex = -1
        let atMax = manager.slots.count >= ControllerManager.maxPlayers
        manager.setJoinEnabled(!atMax)
        renderSlots()
    }

    /// Open the SwiftUI NameEntryOverlay for the given slot. Used on tvOS for
    /// every join, and on iOS for touch slots when the player long-presses
    /// their tile to edit (the inline-keyboard editor handles non-touch
    /// joins on iPad/Mac).
    private func beginCoordinatorNameEntry(slot idx: Int, current: String) {
        manager.setJoinEnabled(false)
        renderSlots()
        NameEntryCoordinator.shared.requestName(forSlot: idx, current: current) { [weak self] entered in
            guard let self else { return }
            let trimmed = entered?.trimmingCharacters(in: .whitespaces) ?? ""
            let final = trimmed.isEmpty ? current : trimmed
            UserDefaults.standard.set(final, forKey: "player_name_\(idx)")
            RecentNames.record(final)
            let atMax = self.manager.slots.count >= ControllerManager.maxPlayers
            self.manager.setJoinEnabled(!atMax)
            self.renderSlots()
        }
    }

    private func renderSlots() {
        slotsLayer.removeAllChildren()
        let count = ControllerManager.maxPlayers
        let tileWidth: CGFloat = 110
        let spacing: CGFloat = 24
        let totalWidth = CGFloat(count) * tileWidth + CGFloat(count - 1) * spacing
        let startX = (size.width - totalWidth) / 2 + tileWidth / 2
        let y = size.height * 0.46
        let slotByIndex = Dictionary(uniqueKeysWithValues: manager.slots.map { ($0.index, $0) })

        for i in 0..<count {
            let x = startX + CGFloat(i) * (tileWidth + spacing)
            let center = CGPoint(x: x, y: y)
            let slot = slotByIndex[i]
            let claimed = slot != nil
            let color: SKColor = slot?.color ?? SKColor(white: 0.25, alpha: 1)

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

        // Slot-preview markers: one chevron per connected unclaimed controller,
        // sitting on the slot tile that controller would claim if it pressed A.
        // Multiple unclaimed controllers on the same tile stack vertically.
        let unclaimed = manager.connectedControllers.filter { manager.slot(for: $0) == nil }
        var markersOnSlot: [Int: Int] = [:]
        for (controllerIdx, c) in unclaimed.enumerated() {
            let slotIdx = manager.intendedSlotIndex(for: c)
            let placed = markersOnSlot[slotIdx, default: 0]
            markersOnSlot[slotIdx] = placed + 1

            let tileX = startX + CGFloat(slotIdx) * (tileWidth + spacing)
            let markerY = y - 50 - CGFloat(placed) * 14
            let color = ControllerManager.playerColors[slotIdx]

            let marker = SKLabelNode(text: "▲ \(controllerIdx + 1)")
            marker.fontName = "AvenirNext-Bold"
            marker.fontSize = 11
            marker.fontColor = color
            marker.position = CGPoint(x: tileX, y: markerY)
            slotsLayer.addChild(marker)
        }

        if let activeIdx = activeNameSlot {
            let recents = Array(RecentNames.all.prefix(4))
            if !recents.isEmpty {
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
        }
    }

    private func renderSelectors() {
        let active   = TitleScene.accentGold
        let inactive = TitleScene.accentGold.withAlphaComponent(0.4)

        modeLabel.text  = selectedMode == .survival ? "SURVIVAL" : "BATTLE"
        modeLabel.fontColor = focused == .mode ? active : inactive

        levelLabel.text = "LEVEL \(selectedLevel)"
        levelLabel.fontColor = focused == .level ? active : inactive

        densityLabel.text = selectedDensity.label
        densityLabel.fontColor = focused == .density ? active : inactive

        audioLabel.text = selectedAudio.label
        audioLabel.fontColor = focused == .audio ? active : inactive

        helpLabel.fontColor = focused == .help ? active : inactive

        modeLeftArrow.fontColor     = focused == .mode    ? active : inactive
        modeRightArrow.fontColor    = focused == .mode    ? active : inactive
        levelLeftArrow.fontColor    = focused == .level   ? active : inactive
        levelRightArrow.fontColor   = focused == .level   ? active : inactive
        densityLeftArrow.fontColor  = focused == .density ? active : inactive
        densityRightArrow.fontColor = focused == .density ? active : inactive
        audioLeftArrow.fontColor    = focused == .audio   ? active : inactive
        audioRightArrow.fontColor   = focused == .audio   ? active : inactive

        // Hint stays hidden by default; flashBattleHint() shows it briefly
        // when the player tries to start BATTLE without enough slots claimed.
    }

    private func cycleMode(by delta: Int) {
        selectedMode = (selectedMode == .survival) ? .battle : .survival
        renderSelectors()
    }

    private func flashJoinHint() {
        joinHintLabel.removeAllActions()
        joinHintLabel.alpha = 1
        let pulse = SKAction.sequence([
            .group([
                .scale(to: 1.08, duration: 0.14),
                .colorize(with: .white, colorBlendFactor: 1.0, duration: 0.14)
            ]),
            .group([
                .scale(to: 1.0, duration: 0.32),
                .colorize(withColorBlendFactor: 0.0, duration: 0.32)
            ])
        ])
        joinHintLabel.run(pulse)
    }

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
            ]),
            .wait(forDuration: 1.2),
            .fadeOut(withDuration: 0.4),
        ])
        battleHintLabel.run(pulse)
    }

    private func moveFocus(by delta: Int) {
        let items = FocusItem.allCases
        let i = items.firstIndex(of: focused) ?? 0
        let next = (i + delta + items.count) % items.count
        focused = items[next]
        renderSelectors()
    }

    private func cycleFocusedHorizontal(by delta: Int) {
        switch focused {
        case .mode:    cycleMode(by: delta)
        case .level:   cycleLevel(by: delta)
        case .density: cycleDensity(by: delta)
        case .audio:   cycleAudio(by: delta)
        case .help:    break
        }
    }

    private func previewSlot(controller: GCController, by delta: Int) {
        let empty = manager.emptySlotIndices()
        guard !empty.isEmpty else { return }
        let curr = manager.intendedSlotIndex(for: controller)
        let i = empty.firstIndex(of: curr) ?? 0
        let next = empty[(i + delta + empty.count) % empty.count]
        manager.setIntendedSlotIndex(next, for: controller)
        renderSlots()
    }

    private func confirmFocused() {
        switch focused {
        case .mode:    cycleMode(by: 1)
        case .level:   cycleLevel(by: 1)
        case .density: cycleDensity(by: 1)
        case .audio:   cycleAudio(by: 1)
        case .help:    openHelp()
        }
    }

    private func cycleAudio(by delta: Int) {
        let cases = AudioMode.allCases
        guard let i = cases.firstIndex(of: selectedAudio) else { return }
        let next = max(0, min(cases.count - 1, i + delta))
        if next != i {
            selectedAudio = cases[next]
            GameSettings.audioMode = selectedAudio
            // React immediately: switch the title music on/off so the
            // selector feels live.
            if selectedAudio == .music {
                MusicPlayer.shared.play(resource: "rivers", ext: "m4a", volume: 0.6)
            } else {
                MusicPlayer.shared.stop()
            }
            renderSelectors()
        }
    }

    private func cycleDensity(by delta: Int) {
        let cases = PowerUpDensity.allCases
        guard let i = cases.firstIndex(of: selectedDensity) else { return }
        let next = max(0, min(cases.count - 1, i + delta))
        if next != i {
            selectedDensity = cases[next]
            GameSettings.sessionPowerUpDensity = selectedDensity
            renderSelectors()
        }
    }

    private func cycleLevel(by delta: Int) {
        var next = selectedLevel + delta
        if next < 1 { next = 9 }
        if next > 9 { next = 1 }
        selectedLevel = next
        renderSelectors()
    }
}
