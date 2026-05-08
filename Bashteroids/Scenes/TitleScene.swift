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
    private var bWasPressed: [ObjectIdentifier: Bool] = [:]
    private var yWasPressed: [ObjectIdentifier: Bool] = [:]
    private var activeNameSlot: Int? = nil
    private var nameBuffer: String = ""
    /// Cycler cursor — position 0...nameBuffer.count where the live char floats.
    private var cyclerCursor: Int = 0
    /// Cycler live-character index (0..28). 0 = 'A', 26 = '.', 27 = '-',
    /// 28 = SPACE. The backspace sentinel is index 29 — the last entry.
    private var cyclerCharIndex: Int = 0
    /// 30-entry alphabet: A-Z (0-25), period (26), hyphen (27), space (28),
    /// backspace sentinel (29). The backspace entry is at the end so
    /// reverse-cycling from index 0 lands on it first, per the user's spec.
    private static let cyclerAlphabet: [Character] = {
        var arr: [Character] = []
        for scalar in UnicodeScalar("A").value...UnicodeScalar("Z").value {
            arr.append(Character(UnicodeScalar(scalar)!))
        }
        arr.append(".")
        arr.append("-")
        arr.append(" ")
        arr.append("\u{232B}")  // ⌫ ERASE TO THE LEFT
        return arr
    }()
    private static let cyclerBackspaceIndex: Int = 29
    private static let cyclerAlphabetCount: Int = 30
    private var prevClaimedIndices: Set<Int> = []
    private var slotAWasPressed: [Int: Bool] = [:]
    private var selectedLevel: Int = GameSettings.lastPlayedLevel
    private var selectedMode: GameMode = GameSettings.lastMode
    private var selectedDensity: PowerUpDensity = GameSettings.sessionPowerUpDensity
    private var selectedAudio: AudioMode = GameSettings.audioMode

    private enum FocusItem: CaseIterable {
        case slot0, slot1, slot2, slot3
        case mode, level, density, audio, help, start
    }
    private var focused: FocusItem = .slot0
    /// Remembers the slot column the user last visited, so up-arrowing back
    /// from the selector column lands on the same slot rather than always 0.
    private var lastSlotFocusIndex: Int = 0
    /// When true, left/right cycles the focused selector's value instead of
    /// navigating focus. Toggled by A/Enter on a selector. Slot tiles, help,
    /// and start are not "editable" — they ignore this flag.
    private var editingSelector: Bool = false

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
    private var titleSwipeObserver: NSObjectProtocol?

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
        titleSwipeObserver = NotificationCenter.default.addObserver(
            forName: .titleSceneSwipe, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let location = note.userInfo?["location"] as? CGPoint,
                  let direction = note.userInfo?["direction"] as? Int else { return }
            MainActor.assumeIsolated { self.handleTouchSwipe(at: location, direction: direction) }
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

        let hasHardwareKeyboard = GCKeyboard.coalesced != nil
        let beginText = hasHardwareKeyboard ? "[SPACE] BEGIN GAME" : "BEGIN GAME"
        let hint = SKLabelNode(text: beginText)
        hint.fontName = "AvenirNext-Bold"
        hint.fontSize = 18
        hint.fontColor = .white
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

        // Audio selector — bottom of the right-side selector column,
        // below the (mostly invisible) battle hint, mirroring the other
        // right-aligned selectors.
        let audioY = battleHintY - 50

        let audioLeft = SKLabelNode(text: "<")
        audioLeft.fontName = "AvenirNext-Regular"
        audioLeft.fontSize = 22
        audioLeft.fontColor = TitleScene.accentGold
        audioLeft.verticalAlignmentMode = .top
        audioLeft.horizontalAlignmentMode = .right
        audioLeft.position = CGPoint(x: selectorCenterX - valueHalfWidth - arrowGap, y: audioY)
        addChild(audioLeft)
        self.audioLeftArrow = audioLeft

        let audioRight = SKLabelNode(text: ">")
        audioRight.fontName = "AvenirNext-Regular"
        audioRight.fontSize = 22
        audioRight.fontColor = TitleScene.accentGold
        audioRight.verticalAlignmentMode = .top
        audioRight.horizontalAlignmentMode = .right
        audioRight.position = CGPoint(x: selectorRightX, y: audioY)
        addChild(audioRight)
        self.audioRightArrow = audioRight

        let audioValue = SKLabelNode(text: "")
        audioValue.fontName = "AvenirNext-Bold"
        audioValue.fontSize = 26
        audioValue.verticalAlignmentMode = .top
        audioValue.position = CGPoint(x: selectorCenterX, y: audioY)
        addChild(audioValue)
        self.audioLabel = audioValue

        let audioCap = SKLabelNode(text: "AUDIO")
        audioCap.fontName = "AvenirNext-Regular"
        audioCap.fontSize = 12
        audioCap.fontColor = SKColor(white: 0.55, alpha: 1)
        audioCap.verticalAlignmentMode = .top
        audioCap.position = CGPoint(x: selectorCenterX, y: audioY - 28)
        addChild(audioCap)
        self.audioCaption = audioCap

        renderSelectors()

        addChild(slotsLayer)
        renderSlots()

        manager.onSlotsChanged = { [weak self] in
            guard let self else { return }
            // Slot claims keep the previously stored name (or "P\(idx+1)"
            // on first launch). The name editor only opens when the player
            // explicitly asks for it via focus + A on their own tile.
            self.prevClaimedIndices = Set(self.manager.slots.map { $0.index })
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
        if let obs = titleSwipeObserver {
            NotificationCenter.default.removeObserver(obs)
            titleSwipeObserver = nil
        }
        // Neither scene state nor music is mutated here — willMove(from:)
        // on the old scene fires *after* didMove(to:) on the new scene in
        // SpriteKit transitions, so changing global state here clobbers the
        // next scene's setup. Each scene's didMove(to:) is responsible for
        // its own audio + overlay state.
    }

    /// Hit-test the title-scene's interactive elements against a SwiftUI-
    /// forwarded tap location (already in scene coords).
    ///
    /// Priority:
    ///   1. Empty slot tile → claim for the touch player.
    ///   2. Help label → openHelp().
    ///   3. Join hint at the bottom → tryStart() (acts as a touchable
    ///      "PRESS A TO JOIN · START / SPACE TO BEGIN" link).
    ///   4. Selector left arrow / right arrow → focus that selector and
    ///      cycle in that direction.
    ///   5. Selector value or caption → focus that selector (no cycle).
    private func handleTouchTap(at point: CGPoint) {
        // Cycler touch buttons take precedence whenever the editor is open.
        if activeNameSlot != nil, handleCyclerTouchTap(at: point) { return }

        if !manager.hasTouchPlayer,
           let i = slotTileIndex(at: point),
           manager.emptySlotIndices().contains(i) {
            manager.claimTouch(atSlot: i)
            return
        }

        // Tapping the touch player's own slot leaves it. Long-press still
        // opens the name editor (see handleTouchLongPress).
        if activeNameSlot == nil,
           let i = slotTileIndex(at: point),
           let slot = manager.slots.first(where: { $0.index == i }),
           slot.touchInput != nil {
            manager.releaseTouchSlot()
            return
        }

        let hitPad: CGFloat = 12

        if helpLabel.frame.insetBy(dx: -hitPad, dy: -hitPad).contains(point) {
            openHelp()
            return
        }

        if joinHintLabel.frame.insetBy(dx: -hitPad, dy: -hitPad).contains(point) {
            tryStart()
            return
        }

        let selectors: [(FocusItem, SKLabelNode, SKLabelNode, SKLabelNode, SKLabelNode?)] = [
            (.mode,    modeLeftArrow,    modeRightArrow,    modeLabel,    nil),
            (.level,   levelLeftArrow,   levelRightArrow,   levelLabel,   nil),
            (.density, densityLeftArrow, densityRightArrow, densityLabel, densityCaption),
            (.audio,   audioLeftArrow,   audioRightArrow,   audioLabel,   audioCaption),
        ]
        for (item, leftArrow, rightArrow, value, caption) in selectors {
            if leftArrow.frame.insetBy(dx: -hitPad, dy: -hitPad).contains(point) {
                focused = item
                cycleSelectorValue(item, by: -1)
                renderSelectors()
                return
            }
            if rightArrow.frame.insetBy(dx: -hitPad, dy: -hitPad).contains(point) {
                focused = item
                cycleSelectorValue(item, by:  1)
                renderSelectors()
                return
            }
            var valueRect = value.frame.insetBy(dx: -hitPad, dy: -hitPad)
            if let cap = caption {
                valueRect = valueRect.union(cap.frame.insetBy(dx: -hitPad, dy: -hitPad))
            }
            if valueRect.contains(point) {
                if focused != item {
                    focused = item
                    renderSelectors()
                }
                return
            }
        }
    }

    /// Returns the selector FocusItem whose value/arrow region contains
    /// `point`, or `nil` if none matches.
    private func selectorAt(_ point: CGPoint) -> FocusItem? {
        let hitPad: CGFloat = 12
        let selectors: [(FocusItem, SKLabelNode, SKLabelNode, SKLabelNode, SKLabelNode?)] = [
            (.mode,    modeLeftArrow,    modeRightArrow,    modeLabel,    nil),
            (.level,   levelLeftArrow,   levelRightArrow,   levelLabel,   nil),
            (.density, densityLeftArrow, densityRightArrow, densityLabel, densityCaption),
            (.audio,   audioLeftArrow,   audioRightArrow,   audioLabel,   audioCaption),
        ]
        for (item, leftArrow, rightArrow, value, caption) in selectors {
            var rect = leftArrow.frame
                .union(rightArrow.frame)
                .union(value.frame)
                .insetBy(dx: -hitPad, dy: -hitPad)
            if let cap = caption {
                rect = rect.union(cap.frame.insetBy(dx: -hitPad, dy: -hitPad))
            }
            if rect.contains(point) { return item }
        }
        return nil
    }

    /// Touch swipe handler: a horizontal swipe over a selector tile cycles
    /// its value. Direction is +1 (right) or -1 (left).
    private func handleTouchSwipe(at point: CGPoint, direction: Int) {
        guard activeNameSlot == nil,
              let item = selectorAt(point) else { return }
        focused = item
        cycleSelectorValue(item, by: direction > 0 ? 1 : -1)
        renderSelectors()
    }

    /// Long-press on a claimed touch slot opens the in-tile cycler editor
    /// for the touch player.
    private func handleTouchLongPress(at point: CGPoint) {
        guard activeNameSlot == nil,
              let i = slotTileIndex(at: point),
              let slot = manager.slots.first(where: { $0.index == i }),
              slot.touchInput != nil else { return }
        openNameEditor(forSlot: i)
    }

    /// Hit-test the cycler touch button row. Returns `true` if a button was
    /// hit and dispatched (so the outer tap handler can short-circuit).
    private func handleCyclerTouchTap(at point: CGPoint) -> Bool {
        let hitPad: CGFloat = 8
        for node in slotsLayer.children {
            guard let name = node.name,
                  name.hasPrefix("cyclerBtn"),
                  node.frame.insetBy(dx: -hitPad, dy: -hitPad).contains(point) else { continue }
            switch name {
            case "cyclerBtnLeft":      moveCyclerCursor(by: -1)
            case "cyclerBtnRight":     moveCyclerCursor(by:  1)
            case "cyclerBtnCycleFwd":  cycleLiveChar(by:  1)
            case "cyclerBtnCycleBack": cycleLiveChar(by: -1)
            case "cyclerBtnCommit":    commitLiveChar()
            case "cyclerBtnConfirm":   confirmName()
            default: break
            }
            return true
        }
        return false
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
            flashJoinSlots()
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

        let nameEntryActive = activeNameSlot != nil

        // While name entry is active, a rising-edge A on any claimed
        // controller confirms the entry — gives controller-only setups a way
        // out without a keyboard. When name entry is not active, A is routed
        // through the focus-confirm path further down.
        //
        // When confirmName fires, also pre-set this controller's
        // aWasPressed[id] so the same A press doesn't ALSO trigger
        // confirmFocused below — that would re-open the editor immediately
        // because the controller is now claimed at the focused slot.
        for (i, slot) in manager.slots.enumerated() {
            let pressed = slot.controller?.extendedGamepad?.buttonA.isPressed
                ?? slot.controller?.microGamepad?.buttonA.isPressed
                ?? false
            let was = slotAWasPressed[i] ?? false
            slotAWasPressed[i] = pressed
            if nameEntryActive, pressed && !was, slot.index == activeNameSlot {
                // The editing player's A press commits the live cycler char.
                // Pre-set the controller's aWasPressed to prevent the
                // controllers loop below from also firing confirmFocused on
                // the same press.
                commitLiveChar()
                if let c = slot.controller {
                    aWasPressed[ObjectIdentifier(c)] = pressed
                }
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
            let nameEntryActive: Bool = activeNameSlot != nil
            if !nameEntryActive {
                if curr.up    && !prev.up    { moveFocus(by: -1) }
                if curr.down  && !prev.down  { moveFocus(by:  1) }
                if curr.left  && !prev.left  { cycleFocusedHorizontal(by: -1) }
                if curr.right && !prev.right { cycleFocusedHorizontal(by:  1) }

                // Keep this controller's intendedSlot aligned with the focus
                // when it lands on a slot tile — drives the preview marker
                // and the join handler's claim target.
                if curr.up != prev.up || curr.down != prev.down
                   || curr.left != prev.left || curr.right != prev.right {
                    syncIntendedSlot(controller: c)
                }
            } else if let editing = activeNameSlot,
                      manager.slot(for: c)?.index == editing {
                // Editing player's d-pad: ↑/↓ cycle the live char,
                // ←/→ move the cursor.
                if curr.up    && !prev.up    { cycleLiveChar(by:  1) }
                if curr.down  && !prev.down  { cycleLiveChar(by: -1) }
                if curr.left  && !prev.left  { moveCyclerCursor(by: -1) }
                if curr.right && !prev.right { moveCyclerCursor(by:  1) }
            }
            dpadEdge[id] = curr

            // Menu button: Siri Remote's Menu is system-reserved (returns to
            // home screen). Only poll it for MFi controllers. While name
            // entry is open, Menu confirms the name instead of starting.
            let menuPressed = c.extendedGamepad?.buttonMenu.isPressed ?? false
            let menuWas = menuWasPressed[id] ?? false
            if menuPressed && !menuWas {
                if nameEntryActive {
                    if manager.slot(for: c)?.index == activeNameSlot { confirmName() }
                } else {
                    tryStart()
                    break
                }
            }
            menuWasPressed[id] = menuPressed

            // X / Play-Pause: starts the game; while name entry is open it
            // confirms the editing player's name (same role as keyboard
            // Enter / MFi Y).
            let xPressed = c.extendedGamepad?.buttonX.isPressed
                ?? c.microGamepad?.buttonX.isPressed
                ?? false
            let xWas = xWasPressed[id] ?? false
            if xPressed && !xWas {
                if nameEntryActive {
                    if manager.slot(for: c)?.index == activeNameSlot { confirmName() }
                } else {
                    tryStart()
                    break
                }
            }
            xWasPressed[id] = xPressed

            // Y button: alternative confirm during name entry (no-op
            // otherwise). MFi only — Siri Remote has no Y.
            let yPressed = c.extendedGamepad?.buttonY.isPressed ?? false
            let yWas = yWasPressed[id] ?? false
            if yPressed && !yWas
                && nameEntryActive
                && manager.slot(for: c)?.index == activeNameSlot {
                confirmName()
            }
            yWasPressed[id] = yPressed

            // B button (extended controllers only — Siri Remote has no B):
            // when this controller has claimed a slot, B releases it.
            let bPressed = c.extendedGamepad?.buttonB.isPressed ?? false
            let bWas = bWasPressed[id] ?? false
            if bPressed && !bWas
                && manager.slot(for: c) != nil
                && !nameEntryActive {
                manager.releaseSlot(for: c)
                bWasPressed[id] = bPressed
                break
            }
            bWasPressed[id] = bPressed

            // Claimed controllers: A = "confirm focused" — cycles a selector,
            // opens help, starts the game, or (if focus is on this
            // controller's own slot) opens the name editor.
            // Unclaimed controllers' A is handled by ControllerManager's
            // join handler at the controller's intendedSlot — which we keep
            // pinned to the shared focus when focus is on a slot tile.
            // aWasPressed is updated unconditionally so a held A-press
            // across the unclaimed→claimed transition doesn't mis-fire on
            // the first frame post-claim.
            let aPressed = c.extendedGamepad?.buttonA.isPressed
                ?? c.microGamepad?.buttonA.isPressed
                ?? false
            let aWas = aWasPressed[id] ?? false
            if aPressed && !aWas
                && manager.slot(for: c) != nil
                && !nameEntryActive
            {
                confirmFocused(byController: c)
            }
            aWasPressed[id] = aPressed
        }
    }

    private func handleKeyDown(_ code: GCKeyCode) {
        if activeNameSlot != nil {
            switch code {
            case .returnOrEnter, .keypadEnter:
                confirmName()
            case .escape:
                cancelNameEdit()
            case .deleteOrBackspace:
                // Direct backspace shortcut — same as cycling to ⌫ and
                // pressing A. Doesn't disturb the cycler's current char.
                if cyclerCursor > 0 {
                    let removeAt = nameBuffer.index(nameBuffer.startIndex, offsetBy: cyclerCursor - 1)
                    nameBuffer.remove(at: removeAt)
                    cyclerCursor -= 1
                    renderSlots()
                }
            case .upArrow:    cycleLiveChar(by:  1)
            case .downArrow:  cycleLiveChar(by: -1)
            case .leftArrow:  moveCyclerCursor(by: -1)
            case .rightArrow: moveCyclerCursor(by:  1)
            default:
                // Direct typing (hardware keyboard shortcut). Inserts at
                // cursor and advances; bypasses the cycler entirely.
                if let ch = TitleScene.charFor(keyCode: code), nameBuffer.count < 8 {
                    let insertAt = nameBuffer.index(nameBuffer.startIndex, offsetBy: cyclerCursor)
                    nameBuffer.insert(ch, at: insertAt)
                    cyclerCursor += 1
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
            // Confirm the focused item. Enter is intentionally NOT a
            // "start game" key here — Space starts; Enter only confirms
            // the focused selector / slot.
            confirmFocused()
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
        case .period: return "."
        case .hyphen: return "-"
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
        closeNameEditor()
    }

    /// Cancel name editing — discard buffer changes and revert to the
    /// previously stored name (no UserDefaults write).
    private func cancelNameEdit() {
        guard activeNameSlot != nil else { return }
        closeNameEditor()
    }

    private func closeNameEditor() {
        activeNameSlot = nil
        nameBuffer = ""
        cyclerCursor = 0
        cyclerCharIndex = 0
        let atMax = manager.slots.count >= ControllerManager.maxPlayers
        manager.setJoinEnabled(!atMax)
        renderSlots()
    }

    /// Cycle the live cycler character. +1 advances forward (A→B→...→Z→.→
    /// →-→SPACE→⌫→A), -1 reverses (A→⌫→SPACE→-→...).
    private func cycleLiveChar(by delta: Int) {
        let count = TitleScene.cyclerAlphabetCount
        cyclerCharIndex = ((cyclerCharIndex + delta) % count + count) % count
        renderSlots()
    }

    /// Move the cycler cursor within the buffer. Clamped 0...buffer.count.
    /// Cursor moves reset the live character to 'A' so each new position
    /// starts predictably.
    private func moveCyclerCursor(by delta: Int) {
        guard activeNameSlot != nil else { return }
        let target = cyclerCursor + delta
        cyclerCursor = max(0, min(nameBuffer.count, target))
        cyclerCharIndex = 0
        renderSlots()
    }

    /// Apply the live character at the cursor.
    /// - Regular char + buffer below cap: insert at cursor, advance cursor.
    /// - Backspace + cursor > 0: delete char before cursor, move cursor back.
    /// - At-cap commit: silently no-op.
    /// In every case the live character resets to 'A'.
    private func commitLiveChar() {
        guard activeNameSlot != nil else { return }
        if cyclerCharIndex == TitleScene.cyclerBackspaceIndex {
            guard cyclerCursor > 0 else { return }
            let removeAt = nameBuffer.index(nameBuffer.startIndex, offsetBy: cyclerCursor - 1)
            nameBuffer.remove(at: removeAt)
            cyclerCursor -= 1
        } else {
            guard nameBuffer.count < 8 else { return }
            let ch = TitleScene.cyclerAlphabet[cyclerCharIndex]
            let insertAt = nameBuffer.index(nameBuffer.startIndex, offsetBy: cyclerCursor)
            nameBuffer.insert(ch, at: insertAt)
            cyclerCursor += 1
        }
        cyclerCharIndex = 0
        renderSlots()
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
            let color: SKColor = slot?.color ?? SKColor(white: 0.4, alpha: 1)

            let isFocused = focusedSlotIndex() == i
            let tile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: 110), cornerRadius: 8)
            tile.position = center
            tile.strokeColor = color
            tile.fillColor = .black
            tile.lineWidth = isFocused ? 5 : 3
            if !claimed { tile.name = "joinTile" }
            slotsLayer.addChild(tile)

            if isFocused {
                let ring = SKShapeNode(rectOf: CGSize(width: tileWidth + 8, height: 118),
                                       cornerRadius: 10)
                ring.position = center
                ring.strokeColor = TitleScene.accentGold
                ring.fillColor = .clear
                ring.lineWidth = 2
                slotsLayer.addChild(ring)
            }

            if claimed {
                let ship = Shapes.shipV(color: color, scale: 1.6)
                ship.position = center
                ship.zRotation = .pi / 2
                slotsLayer.addChild(ship)
            } else {
                let label = SKLabelNode(text: "JOIN")
                label.fontName = "AvenirNext-Bold"
                label.fontSize = 16
                label.fontColor = ControllerManager.playerColors[i]
                label.position = CGPoint(x: x, y: y - 6)
                label.name = "joinLabel"
                slotsLayer.addChild(label)
            }

            let storedName = UserDefaults.standard.string(forKey: "player_name_\(i)") ?? "P\(i + 1)"
            if activeNameSlot == i {
                renderCyclerEditor(x: x, y: y, color: color, slotIndex: i,
                                   isTouchSlot: slot?.touchInput != nil)
            } else if claimed {
                let nameLabel = SKLabelNode(text: storedName)
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

    }

    /// Render the in-tile cycler editor for the slot currently being edited.
    /// Layout (anchored at slot tile center `(x, y)`):
    ///   y - 69 :  per-character buffer with the live char in gold at cursor
    ///   y - 80 :  caret marker (▲) under the cursor position
    ///   y - 92 :  legend hint
    ///   y - 110:  touch button row (only when the touch player is editing)
    private func renderCyclerEditor(x: CGFloat, y: CGFloat, color: SKColor,
                                    slotIndex: Int, isTouchSlot: Bool) {
        let bufferChars = Array(nameBuffer)
        let liveChar = TitleScene.cyclerAlphabet[cyclerCharIndex]

        // Build the visible string: buffer with live char inserted at cursor.
        var displayChars: [Character] = []
        let cursor = max(0, min(bufferChars.count, cyclerCursor))
        displayChars.append(contentsOf: bufferChars.prefix(cursor))
        displayChars.append(liveChar)
        displayChars.append(contentsOf: bufferChars.dropFirst(cursor))

        // Lay out characters with fixed advance so the caret aligns under
        // the live position regardless of glyph width.
        let advance: CGFloat = 11
        let totalWidth = CGFloat(displayChars.count - 1) * advance
        let startX = x - totalWidth / 2
        for (idx, ch) in displayChars.enumerated() {
            let lbl = SKLabelNode(text: String(ch))
            lbl.fontName = "AvenirNext-Bold"
            lbl.fontSize = 16
            lbl.fontColor = idx == cursor ? TitleScene.accentGold : color
            lbl.position = CGPoint(x: startX + CGFloat(idx) * advance, y: y - 69)
            slotsLayer.addChild(lbl)
        }

        // Caret (▲) under the live char.
        let caret = SKLabelNode(text: "▲")
        caret.fontName = "AvenirNext-Bold"
        caret.fontSize = 9
        caret.fontColor = TitleScene.accentGold
        caret.position = CGPoint(x: startX + CGFloat(cursor) * advance, y: y - 82)
        slotsLayer.addChild(caret)

        // Legend hint — abbreviated, fits under the caret.
        let hint = SKLabelNode(text: "↑↓ CYCLE  ◀▶ MOVE")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 8
        hint.fontColor = SKColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: x, y: y - 94)
        slotsLayer.addChild(hint)

        if isTouchSlot {
            renderCyclerTouchButtons(centerX: x, baseY: y - 110, slotIndex: slotIndex)
        }
    }

    /// Touch button row beneath the editing tile. Six buttons:
    /// `◀ ↑ ↓ ▶ ⌫ ✓`. Hit-tested in `handleTouchTap`.
    private func renderCyclerTouchButtons(centerX: CGFloat, baseY: CGFloat,
                                          slotIndex: Int) {
        let labels: [(Character, String)] = [
            ("◀", "cyclerBtnLeft"),
            ("↑", "cyclerBtnCycleFwd"),
            ("↓", "cyclerBtnCycleBack"),
            ("▶", "cyclerBtnRight"),
            ("⏎", "cyclerBtnCommit"),
            ("✓", "cyclerBtnConfirm")
        ]
        let advance: CGFloat = 24
        let totalWidth = CGFloat(labels.count - 1) * advance
        let startX = centerX - totalWidth / 2
        for (idx, entry) in labels.enumerated() {
            let bx = startX + CGFloat(idx) * advance
            let bg = SKShapeNode(circleOfRadius: 11)
            bg.position = CGPoint(x: bx, y: baseY)
            bg.strokeColor = TitleScene.accentGold
            bg.fillColor = SKColor.black.withAlphaComponent(0.4)
            bg.lineWidth = 1.5
            bg.name = entry.1
            slotsLayer.addChild(bg)

            let lbl = SKLabelNode(text: String(entry.0))
            lbl.fontName = "AvenirNext-Bold"
            lbl.fontSize = 12
            lbl.fontColor = TitleScene.accentGold
            lbl.verticalAlignmentMode = .center
            lbl.horizontalAlignmentMode = .center
            lbl.position = CGPoint(x: bx, y: baseY)
            slotsLayer.addChild(lbl)
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

        joinHintLabel.fontColor = focused == .start ? active : .white

        let editing = editingSelector
        let editingScale: CGFloat = 1.3

        func style(_ arrow: SKLabelNode, item: FocusItem) {
            arrow.fontColor = focused == item ? active : inactive
            arrow.setScale((focused == item && editing) ? editingScale : 1.0)
        }
        style(modeLeftArrow,    item: .mode)
        style(modeRightArrow,   item: .mode)
        style(levelLeftArrow,   item: .level)
        style(levelRightArrow,  item: .level)
        style(densityLeftArrow, item: .density)
        style(densityRightArrow,item: .density)
        style(audioLeftArrow,   item: .audio)
        style(audioRightArrow,  item: .audio)

        // Hint stays hidden by default; flashBattleHint() shows it briefly
        // when the player tries to start BATTLE without enough slots claimed.
    }

    private func cycleMode(by delta: Int) {
        selectedMode = (selectedMode == .survival) ? .battle : .survival
        renderSelectors()
    }

    private func flashJoinSlots() {
        let labelPulse = SKAction.sequence([
            .group([
                .scale(to: 1.25, duration: 0.14),
                .colorize(with: .white, colorBlendFactor: 1.0, duration: 0.14)
            ]),
            .group([
                .scale(to: 1.0, duration: 0.32),
                .colorize(withColorBlendFactor: 0.0, duration: 0.32)
            ])
        ])
        let tilePulse = SKAction.sequence([
            .scale(to: 1.06, duration: 0.14),
            .scale(to: 1.0,  duration: 0.32)
        ])
        for node in slotsLayer.children {
            switch node.name {
            case "joinLabel":
                node.removeAllActions()
                node.setScale(1.0)
                node.run(labelPulse)
            case "joinTile":
                node.removeAllActions()
                node.setScale(1.0)
                node.run(tilePulse)
            default:
                break
            }
        }
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

    /// Vertical navigation.
    /// - On a slot tile: down → start (the action), up → mode (the settings
    ///   entry point).
    /// - In the selector column: up/down moves through the list. Mode-up
    ///   returns to the slot you came from; start-up → help.
    /// - While editing a selector: up/down is ignored — A exits edit mode.
    private func moveFocus(by delta: Int) {
        if editingSelector { return }
        switch focused {
        case .slot0, .slot1, .slot2, .slot3:
            focused = (delta > 0) ? .start : .mode
        case .mode:
            if delta < 0 { focused = lastSlotFocus() }
            else { focused = .level }
        case .level:
            focused = (delta < 0) ? .mode : .density
        case .density:
            focused = (delta < 0) ? .level : .audio
        case .audio:
            focused = (delta < 0) ? .density : .help
        case .help:
            focused = (delta < 0) ? .audio : .start
        case .start:
            if delta < 0 { focused = .help }
        }
        renderSelectors()
        renderSlots()
    }

    /// When up-arrowing from the selector column, snap to the slot row,
    /// preferring the slot index that the actor (or the most recent action)
    /// last touched. Falls back to slot 0.
    private func lastSlotFocus() -> FocusItem {
        switch lastSlotFocusIndex {
        case 1: return .slot1
        case 2: return .slot2
        case 3: return .slot3
        default: return .slot0
        }
    }

    /// Horizontal navigation.
    /// - While editing a selector: left/right cycles its value.
    /// - Slot row: moves between tiles (clamped). Slot 3 right exits to the
    ///   audio selector (rightmost slot is adjacent to the selector column).
    /// - Selector / help / start: left exits the column to slot 3 (P4),
    ///   right is a no-op.
    private func cycleFocusedHorizontal(by delta: Int) {
        if editingSelector {
            cycleFocusedSelectorValue(by: delta)
            return
        }
        switch focused {
        case .slot0:
            if delta > 0 { setSlotFocus(1) }
        case .slot1:
            setSlotFocus(delta > 0 ? 2 : 0)
        case .slot2:
            setSlotFocus(delta > 0 ? 3 : 1)
        case .slot3:
            if delta < 0 { setSlotFocus(2) }
            else {
                focused = .audio
                editingSelector = false
                renderSelectors()
                renderSlots()
            }
        case .mode, .level, .density, .audio, .help, .start:
            if delta < 0 { setSlotFocus(3) }
        }
    }

    /// Cycle the value of whichever selector is currently focused. Called
    /// from edit mode and from direct touch gestures (arrow taps, swipes).
    private func cycleFocusedSelectorValue(by delta: Int) {
        switch focused {
        case .mode:    cycleMode(by: delta)
        case .level:   cycleLevel(by: delta)
        case .density: cycleDensity(by: delta)
        case .audio:   cycleAudio(by: delta)
        default: break
        }
    }

    /// Cycle the value of a specific selector (used for touch hits/swipes
    /// where the gesture's start point identifies the selector regardless
    /// of current focus).
    private func cycleSelectorValue(_ item: FocusItem, by delta: Int) {
        switch item {
        case .mode:    cycleMode(by: delta)
        case .level:   cycleLevel(by: delta)
        case .density: cycleDensity(by: delta)
        case .audio:   cycleAudio(by: delta)
        default: break
        }
    }

    private func setSlotFocus(_ index: Int) {
        switch index {
        case 0: focused = .slot0
        case 1: focused = .slot1
        case 2: focused = .slot2
        case 3: focused = .slot3
        default: return
        }
        lastSlotFocusIndex = index
        editingSelector = false
        renderSelectors()
        renderSlots()
    }

    /// For unclaimed controllers, keep the per-controller intendedSlot
    /// aligned with the shared focus when focus is on a slot — so the preview
    /// triangle and the upcoming claim agree.
    private func syncIntendedSlot(controller: GCController) {
        guard manager.slot(for: controller) == nil,
              let idx = focusedSlotIndex() else { return }
        manager.setIntendedSlotIndex(idx, for: controller)
    }

    private func focusedSlotIndex() -> Int? {
        switch focused {
        case .slot0: return 0
        case .slot1: return 1
        case .slot2: return 2
        case .slot3: return 3
        default: return nil
        }
    }

    /// Confirm the current focus.
    ///
    /// `controller` is the gamepad that triggered the confirmation, or `nil`
    /// for keyboard-driven activation. Slot focus delegates to
    /// `confirmSlotFocus` so the action depends on who pressed and what's
    /// already in that tile.
    private func confirmFocused(byController controller: GCController? = nil) {
        switch focused {
        case .slot0: confirmSlotFocus(0, controller: controller)
        case .slot1: confirmSlotFocus(1, controller: controller)
        case .slot2: confirmSlotFocus(2, controller: controller)
        case .slot3: confirmSlotFocus(3, controller: controller)
        case .mode, .level, .density, .audio:
            // Toggle edit mode for the focused selector. While editing,
            // left/right cycles the value; A again exits.
            editingSelector.toggle()
            renderSelectors()
        case .start:   tryStart()
        case .help:    openHelp()
        }
    }

    /// Slot tile activated.
    ///
    /// - Controller, unclaimed → claim this empty slot (no-op if claimed).
    /// - Controller, claimed at this slot → re-edit the player name.
    /// - Controller, claimed elsewhere → ignored.
    /// - Keyboard, unclaimed → claim this empty slot for the keyboard.
    /// - Keyboard, claimed at this slot → re-edit the player name.
    /// - Keyboard, claimed elsewhere → ignored.
    private func confirmSlotFocus(_ slotIndex: Int, controller: GCController?) {
        guard activeNameSlot == nil else { return }
        if let c = controller {
            if let mySlot = manager.slot(for: c) {
                if mySlot.index == slotIndex {
                    openNameEditor(forSlot: slotIndex)
                }
            } else if manager.emptySlotIndices().contains(slotIndex) {
                manager.claim(controller: c, atSlot: slotIndex)
            }
        } else {
            // Keyboard-driven confirm.
            if let kbSlotIndex = manager.slots.firstIndex(where: { $0.keyboard != nil }),
               manager.slots[kbSlotIndex].index == slotIndex {
                openNameEditor(forSlot: slotIndex)
            } else if !manager.hasKeyboardPlayer,
                      manager.emptySlotIndices().contains(slotIndex) {
                manager.claimKeyboard(atSlot: slotIndex)
            }
        }
    }

    private func openNameEditor(forSlot idx: Int) {
        let current = UserDefaults.standard.string(forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
        let trimmed = String(current.uppercased().prefix(8))
        activeNameSlot = idx
        nameBuffer = trimmed
        cyclerCursor = trimmed.count
        cyclerCharIndex = 0
        manager.setJoinEnabled(false)
        renderSlots()
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
