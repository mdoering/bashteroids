import SpriteKit
import GameController

final class TitleScene: SKScene {
    private static let accentGold = SKColor(red: 245/255, green: 194/255, blue: 66/255, alpha: 1)
    private static let unclaimedRingColor = SKColor(white: 0.35, alpha: 1)

    private let manager = ControllerManager.shared
    private let slotsLayer = SKNode()
    private var transitioning = false
    private var menuWasPressed: [ObjectIdentifier: Bool] = [:]
    private var xWasPressed: [ObjectIdentifier: Bool] = [:]
    private var aWasPressed: [ObjectIdentifier: Bool] = [:]
    private var bWasPressed: [ObjectIdentifier: Bool] = [:]
    private var yWasPressed: [ObjectIdentifier: Bool] = [:]

    // MARK: - Per-slot claim state
    //
    // A slot is in `pickingColor` once a controller (or keyboard / touch) has
    // claimed it — the slot is in `manager.slots` already, but the player is
    // still choosing a color. `pickingColor[idx]` holds the palette index
    // (0..3) of the candidate. On A-confirm the slot transitions to
    // `nameEditing[idx]` (cycler editor open); on a second A-confirm the
    // slot drops both dicts and becomes fully claimed-idle.
    //
    // Multiple slots can be in either phase simultaneously — each player's
    // input is routed through their own slot's state.

    private var pickingColor: [Int: Int] = [:]
    private struct NameEditState {
        var buffer: String = ""
        var cursor: Int = 0
        var charIndex: Int = 0
    }
    private var nameEditing: [Int: NameEditState] = [:]

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
    private var selectedLevel: Int = GameSettings.lastPlayedLevel
    private var selectedMode: GameMode = GameSettings.lastMode
    private var selectedDensity: PowerUpDensity = GameSettings.sessionPowerUpDensity
    private var selectedAudio: AudioMode = GameSettings.audioMode

    // Focus lives only on the right-side menu now; slot tiles are not
    // focusable. Left/right directly cycles the focused selector — no
    // edit-mode toggle.
    private enum FocusItem: CaseIterable {
        case mode, level, density, audio, help, start
    }
    private var focused: FocusItem = .start

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

        let arrowGap: CGFloat = 14
        let valueHalfWidth: CGFloat = 60
        let selectorRightX = size.width - edgeMargin
        let selectorCenterX = selectorRightX - 12 - arrowGap - valueHalfWidth
        let modeY  = topAnchorY
        let levelY = topAnchorY - 50
        let densityY = levelY - 50
        let densityCaptionY = densityY - 28

        modeLeftArrow = makeSelectorArrow("<", x: selectorCenterX - valueHalfWidth - arrowGap, y: modeY)
        modeRightArrow = makeSelectorArrow(">", x: selectorRightX, y: modeY)
        modeLabel = makeSelectorValue(x: selectorCenterX, y: modeY)

        levelLeftArrow = makeSelectorArrow("<", x: selectorCenterX - valueHalfWidth - arrowGap, y: levelY)
        levelRightArrow = makeSelectorArrow(">", x: selectorRightX, y: levelY)
        levelLabel = makeSelectorValue(x: selectorCenterX, y: levelY)

        densityLeftArrow = makeSelectorArrow("<", x: selectorCenterX - valueHalfWidth - arrowGap, y: densityY)
        densityRightArrow = makeSelectorArrow(">", x: selectorRightX, y: densityY)
        densityLabel = makeSelectorValue(x: selectorCenterX, y: densityY)

        let densityCap = SKLabelNode(text: "POWERUPS")
        densityCap.fontName = "AvenirNext-Regular"
        densityCap.fontSize = 12
        densityCap.fontColor = SKColor(white: 0.55, alpha: 1)
        densityCap.verticalAlignmentMode = .top
        densityCap.position = CGPoint(x: selectorCenterX, y: densityCaptionY)
        addChild(densityCap)
        self.densityCaption = densityCap

        // Battle-needs-2 hint sits below the slot row, centered. Hidden by
        // default; flashBattleHint() pulses it in (and pulses the slot tiles)
        // when the user tries to start BATTLE without enough players.
        let battleHint = SKLabelNode(text: "BATTLE NEEDS 2+ PLAYERS")
        battleHint.fontName = "AvenirNext-Bold"
        battleHint.fontSize = 14
        battleHint.fontColor = SKColor(red: 0.85, green: 0.45, blue: 0.45, alpha: 1)
        battleHint.verticalAlignmentMode = .top
        battleHint.position = CGPoint(x: size.width / 2, y: size.height * 0.46 - 98)
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

        let audioY = densityCaptionY - 80
        audioLeftArrow = makeSelectorArrow("<", x: selectorCenterX - valueHalfWidth - arrowGap, y: audioY)
        audioRightArrow = makeSelectorArrow(">", x: selectorRightX, y: audioY)
        audioLabel = makeSelectorValue(x: selectorCenterX, y: audioY)

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
        prevClaimedIndices = Set(manager.slots.map { $0.index })
        renderSlots()

        manager.onSlotsChanged = { [weak self] in
            guard let self else { return }
            let now = Set(self.manager.slots.map { $0.index })
            let newly = now.subtracting(self.prevClaimedIndices)
            let released = self.prevClaimedIndices.subtracting(now)
            for idx in newly {
                self.enterColorPicker(slot: idx)
            }
            for idx in released {
                self.pickingColor.removeValue(forKey: idx)
                self.nameEditing.removeValue(forKey: idx)
            }
            self.prevClaimedIndices = now
            self.renderSlots()
            self.renderSelectors()
        }
        manager.onStartPressed = { [weak self] in self?.tryStart() }
        manager.setJoinEnabled(true)

        KeyboardManager.shared.onKeyDown = { [weak self] code in
            self?.handleKeyDown(code)
        }

        // Seed per-controller button-state dicts from the currently-held
        // state so a button held across a scene transition (e.g. user A's
        // press that returned them here from help / game-over) doesn't fire
        // a spurious edge on frame 1.
        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)
            aWasPressed[id] = c.extendedGamepad?.buttonA.isPressed
                ?? c.microGamepad?.buttonA.isPressed ?? false
            xWasPressed[id] = c.extendedGamepad?.buttonX.isPressed
                ?? c.microGamepad?.buttonX.isPressed ?? false
            menuWasPressed[id] = c.extendedGamepad?.buttonMenu.isPressed ?? false
            yWasPressed[id] = c.extendedGamepad?.buttonY.isPressed ?? false
            bWasPressed[id] = c.extendedGamepad?.buttonB.isPressed ?? false
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
    }

    private func makeSelectorArrow(_ glyph: String, x: CGFloat, y: CGFloat) -> SKLabelNode {
        let n = SKLabelNode(text: glyph)
        n.fontName = "AvenirNext-Regular"
        n.fontSize = 22
        n.fontColor = TitleScene.accentGold
        n.verticalAlignmentMode = .top
        n.horizontalAlignmentMode = .right
        n.position = CGPoint(x: x, y: y)
        addChild(n)
        return n
    }

    private func makeSelectorValue(x: CGFloat, y: CGFloat) -> SKLabelNode {
        let n = SKLabelNode(text: "")
        n.fontName = "AvenirNext-Bold"
        n.fontSize = 26
        n.verticalAlignmentMode = .top
        n.position = CGPoint(x: x, y: y)
        addChild(n)
        return n
    }

    // MARK: - Phase helpers

    /// True when at least one slot is mid-claim. Blocks `tryStart` / `openHelp`
    /// so half-claimed players don't get yanked into the game.
    private var anyClaiming: Bool {
        !pickingColor.isEmpty || !nameEditing.isEmpty
    }

    /// Palette indices currently locked by slots past the color-pick phase
    /// (i.e. claimed-idle or in name-editing). Color-picking slots don't
    /// lock — that's resolved at confirm time.
    private func lockedColorIndices() -> Set<Int> {
        var locked: Set<Int> = []
        for slot in manager.slots where pickingColor[slot.index] == nil {
            if let i = paletteIndex(of: slot.color) {
                locked.insert(i)
            }
        }
        return locked
    }

    private func paletteIndex(of color: SKColor) -> Int? {
        ControllerManager.playerColors.firstIndex(where: { colorsEqual($0, color) })
    }

    private func colorsEqual(_ a: SKColor, _ b: SKColor) -> Bool {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return abs(ar - br) < 0.005 && abs(ag - bg) < 0.005 && abs(ab - bb) < 0.005
    }

    private func enterColorPicker(slot idx: Int) {
        let palette = ControllerManager.playerColors
        let locked = lockedColorIndices()
        // Initial candidate: remembered (if free), else slot-index default
        // (if free), else first free.
        let remembered = UserDefaults.standard.object(forKey: "slot_color_\(idx)") as? Int
        let candidates = ([remembered, idx] + Array(0..<palette.count)).compactMap { $0 }
        let chosen = candidates.first(where: { $0 >= 0 && $0 < palette.count && !locked.contains($0) }) ?? 0
        pickingColor[idx] = chosen
        manager.setColor(at: idx, to: palette[chosen])
    }

    private func cycleColorCandidate(slot idx: Int, by delta: Int) {
        guard var cur = pickingColor[idx] else { return }
        let palette = ControllerManager.playerColors
        let locked = lockedColorIndices()
        let n = palette.count
        for _ in 0..<n {
            cur = ((cur + delta) % n + n) % n
            if !locked.contains(cur) { break }
        }
        pickingColor[idx] = cur
        manager.setColor(at: idx, to: palette[cur])
        renderSlots()
    }

    private func confirmColorPick(slot idx: Int) {
        guard let pal = pickingColor[idx] else { return }
        pickingColor.removeValue(forKey: idx)
        UserDefaults.standard.set(pal, forKey: "slot_color_\(idx)")
        rebumpCandidatesAfterLock()
        enterNameEditor(slot: idx)
        renderSlots()
    }

    /// Advance any other picking slot whose candidate just got locked by a
    /// peer's confirmation.
    private func rebumpCandidatesAfterLock() {
        let palette = ControllerManager.playerColors
        let locked = lockedColorIndices()
        for (slotIdx, candidate) in pickingColor where locked.contains(candidate) {
            var next = candidate
            for _ in 0..<palette.count {
                next = (next + 1) % palette.count
                if !locked.contains(next) { break }
            }
            pickingColor[slotIdx] = next
            manager.setColor(at: slotIdx, to: palette[next])
        }
    }

    private func enterNameEditor(slot idx: Int) {
        let stored = UserDefaults.standard.string(forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
        let trimmed = String(stored.uppercased().prefix(8))
        nameEditing[idx] = NameEditState(buffer: trimmed,
                                          cursor: trimmed.count,
                                          charIndex: 0)
    }

    private func confirmName(slot idx: Int) {
        guard let st = nameEditing[idx] else { return }
        let trimmed = st.buffer.trimmingCharacters(in: .whitespaces)
        let previous = UserDefaults.standard.string(forKey: "player_name_\(idx)") ?? "P\(idx + 1)"
        let name = trimmed.isEmpty ? previous : trimmed
        UserDefaults.standard.set(name, forKey: "player_name_\(idx)")
        RecentNames.record(name)
        nameEditing.removeValue(forKey: idx)
        renderSlots()
    }

    /// Cycle the live cycler character for `slot`.
    private func cycleLiveChar(slot idx: Int, by delta: Int) {
        guard var st = nameEditing[idx] else { return }
        let count = TitleScene.cyclerAlphabetCount
        st.charIndex = ((st.charIndex + delta) % count + count) % count
        nameEditing[idx] = st
        renderSlots()
    }

    /// Move the cursor within the buffer. The live character is preserved
    /// across moves so a player parked on `⌫` (or any letter) can keep
    /// committing without re-cycling.
    private func moveCyclerCursor(slot idx: Int, by delta: Int) {
        guard var st = nameEditing[idx] else { return }
        let target = st.cursor + delta
        st.cursor = max(0, min(st.buffer.count, target))
        nameEditing[idx] = st
        renderSlots()
    }

    /// Insert the live char at the cursor (delete if cycler is on `⌫`).
    /// The live char is preserved after insertion.
    private func insertLiveChar(slot idx: Int) {
        guard var st = nameEditing[idx] else { return }
        if st.charIndex == TitleScene.cyclerBackspaceIndex {
            guard st.cursor > 0 else { return }
            let removeAt = st.buffer.index(st.buffer.startIndex, offsetBy: st.cursor - 1)
            st.buffer.remove(at: removeAt)
            st.cursor -= 1
        } else {
            guard st.buffer.count < 8 else { return }
            let ch = TitleScene.cyclerAlphabet[st.charIndex]
            let insertAt = st.buffer.index(st.buffer.startIndex, offsetBy: st.cursor)
            st.buffer.insert(ch, at: insertAt)
            st.cursor += 1
        }
        nameEditing[idx] = st
        renderSlots()
    }

    // MARK: - Touch

    /// Hit-test the title-scene's interactive elements against a SwiftUI-
    /// forwarded tap location (already in scene coords).
    private func handleTouchTap(at point: CGPoint) {
        let touchSlotIdx = manager.slots.first(where: { $0.touchInput != nil })?.index

        // Cycler touch buttons take precedence whenever the touch player's
        // name editor is open.
        if let i = touchSlotIdx, nameEditing[i] != nil,
           handleCyclerTouchTap(at: point, slot: i) {
            return
        }

        // Color-picker arrows on the touch player's pickColor tile take
        // precedence over the slot-tile tap, since the arrows live inside
        // the tile rect.
        if let i = touchSlotIdx, pickingColor[i] != nil,
           handleColorPickerTouchTap(at: point, slot: i) {
            return
        }

        // Tap on a slot tile.
        if let i = slotTileIndex(at: point) {
            if let slot = manager.slots.first(where: { $0.index == i }), slot.touchInput != nil {
                // Tap on the touch player's own tile mirrors the controller's
                // triple-A: pickColor → confirm color → enter nameEdit.
                // Inside nameEdit, the cycler ⏎/✓ buttons handle char insert
                // and final confirm — but a tap anywhere else in the tile
                // commits the name (treats tap as "I'm done"). On idle,
                // tap-own-slot releases. Long-press releases at any phase.
                if pickingColor[i] != nil {
                    confirmColorPick(slot: i)
                } else if nameEditing[i] != nil {
                    confirmName(slot: i)
                } else {
                    manager.releaseTouchSlot()
                }
                return
            }
            if !manager.hasTouchPlayer, manager.emptySlotIndices().contains(i) {
                manager.claimTouch(atSlot: i)
                return
            }
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

    private func handleTouchSwipe(at point: CGPoint, direction: Int) {
        // Swipe over the touch player's pickColor tile cycles the candidate
        // color. Otherwise fall through to the selector swipe path.
        if let touchSlot = manager.slots.first(where: { $0.touchInput != nil })?.index,
           pickingColor[touchSlot] != nil,
           slotTileIndex(at: point) == touchSlot {
            cycleColorCandidate(slot: touchSlot, by: direction > 0 ? 1 : -1)
            return
        }
        guard let item = selectorAt(point) else { return }
        focused = item
        cycleSelectorValue(item, by: direction > 0 ? 1 : -1)
        renderSelectors()
    }

    /// Long-press on the touch player's own slot tile releases the slot at
    /// any phase (mirrors the controller's B button).
    private func handleTouchLongPress(at point: CGPoint) {
        guard let i = slotTileIndex(at: point),
              let slot = manager.slots.first(where: { $0.index == i }),
              slot.touchInput != nil else { return }
        manager.releaseTouchSlot()
    }

    /// Hit-test the cycler touch button row for `slot`. Returns true if a
    /// button was dispatched.
    private func handleCyclerTouchTap(at point: CGPoint, slot idx: Int) -> Bool {
        let hitPad: CGFloat = 8
        for node in slotsLayer.children {
            guard let name = node.name,
                  name.hasPrefix("cyclerBtn"),
                  node.frame.insetBy(dx: -hitPad, dy: -hitPad).contains(point) else { continue }
            switch name {
            case "cyclerBtnLeft":      moveCyclerCursor(slot: idx, by: -1)
            case "cyclerBtnRight":     moveCyclerCursor(slot: idx, by:  1)
            case "cyclerBtnCycleFwd":  cycleLiveChar(slot: idx, by:  1)
            case "cyclerBtnCycleBack": cycleLiveChar(slot: idx, by: -1)
            case "cyclerBtnCommit":    insertLiveChar(slot: idx)
            case "cyclerBtnConfirm":   confirmName(slot: idx)
            default: break
            }
            return true
        }
        return false
    }

    /// Hit-test the color-picker arrows for `slot`. Returns true if an arrow
    /// was hit and the candidate was cycled.
    private func handleColorPickerTouchTap(at point: CGPoint, slot idx: Int) -> Bool {
        let hitPad: CGFloat = 12
        for node in slotsLayer.children {
            guard let name = node.name,
                  name.hasPrefix("colorArrow"),
                  node.frame.insetBy(dx: -hitPad, dy: -hitPad).contains(point) else { continue }
            switch name {
            case "colorArrowLeft":  cycleColorCandidate(slot: idx, by: -1)
            case "colorArrowRight": cycleColorCandidate(slot: idx, by:  1)
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

    // MARK: - Start / Help

    private func tryStart() {
        guard !transitioning, !anyClaiming else { return }
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
        guard !transitioning, !anyClaiming else { return }
        transitioning = true
        let help = HelpScene(size: size)
        help.scaleMode = scaleMode
        view?.presentScene(help, transition: .fade(withDuration: 0.3))
    }

    // MARK: - Per-frame controller polling

    override func update(_ currentTime: TimeInterval) {
        guard !transitioning else { return }

        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)
            let myIdx = manager.slot(for: c)?.index
            let myPickIdx: Int? = myIdx.flatMap { pickingColor[$0] != nil ? $0 : nil }
            let myEditIdx: Int? = myIdx.flatMap { nameEditing[$0] != nil ? $0 : nil }
            let midClaim = myPickIdx != nil || myEditIdx != nil

            // --- D-pad: edge-trigger ---
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

            if let pickIdx = myPickIdx {
                if curr.left  && !prev.left  { cycleColorCandidate(slot: pickIdx, by: -1) }
                if curr.right && !prev.right { cycleColorCandidate(slot: pickIdx, by:  1) }
            } else if let editIdx = myEditIdx {
                if curr.up    && !prev.up    { cycleLiveChar(slot: editIdx, by:  1) }
                if curr.down  && !prev.down  { cycleLiveChar(slot: editIdx, by: -1) }
                if curr.left  && !prev.left  { moveCyclerCursor(slot: editIdx, by: -1) }
                if curr.right && !prev.right { moveCyclerCursor(slot: editIdx, by:  1) }
            } else {
                if curr.up    && !prev.up    { moveFocus(by: -1) }
                if curr.down  && !prev.down  { moveFocus(by:  1) }
                if curr.left  && !prev.left  { cycleFocusedSelector(by: -1) }
                if curr.right && !prev.right { cycleFocusedSelector(by:  1) }
            }
            dpadEdge[id] = curr

            // --- Menu (MFi only — Siri Remote's Menu is system-reserved) ---
            let menuPressed = c.extendedGamepad?.buttonMenu.isPressed ?? false
            let menuWas = menuWasPressed[id] ?? false
            if menuPressed && !menuWas {
                if let editIdx = myEditIdx { confirmName(slot: editIdx) }
                else if let pickIdx = myPickIdx { confirmColorPick(slot: pickIdx) }
                else { tryStart() }
            }
            menuWasPressed[id] = menuPressed

            // --- X / Play-Pause ---
            // In name-edit phase on the editing player's own slot: insert the
            // live char. Otherwise: begin-game shortcut (or color confirm).
            let xPressed = c.extendedGamepad?.buttonX.isPressed
                ?? c.microGamepad?.buttonX.isPressed
                ?? false
            let xWas = xWasPressed[id] ?? false
            if xPressed && !xWas {
                if let editIdx = myEditIdx {
                    insertLiveChar(slot: editIdx)
                } else if let pickIdx = myPickIdx {
                    confirmColorPick(slot: pickIdx)
                } else {
                    tryStart()
                }
            }
            xWasPressed[id] = xPressed

            // --- Y (MFi only) ---
            // Y confirms the name during name-edit. Outside name-edit it's a
            // no-op (Y is the in-game minelayer).
            let yPressed = c.extendedGamepad?.buttonY.isPressed ?? false
            let yWas = yWasPressed[id] ?? false
            if yPressed && !yWas, let editIdx = myEditIdx {
                confirmName(slot: editIdx)
            }
            yWasPressed[id] = yPressed

            // --- B (MFi only — Siri Remote has no B) ---
            // B releases the slot at any phase (pickColor, nameEdit, idle).
            let bPressed = c.extendedGamepad?.buttonB.isPressed ?? false
            let bWas = bWasPressed[id] ?? false
            if bPressed && !bWas, manager.slot(for: c) != nil {
                manager.releaseSlot(for: c)
                bWasPressed[id] = bPressed
                break
            }
            bWasPressed[id] = bPressed

            // --- A ---
            // Unclaimed controllers' A is wired through ControllerManager's
            // installJoinHandler (pressedChangedHandler). For claimed
            // controllers: A confirms the current phase (color → name → done),
            // and on a fully-claimed-idle controller it triggers the focused
            // menu item (help/start) — selectors are no-ops since ◀▶ cycles
            // them directly.
            // aWasPressed is updated unconditionally so a held A across the
            // unclaimed → claimed transition doesn't mis-fire on the first
            // post-claim frame.
            let aPressed = c.extendedGamepad?.buttonA.isPressed
                ?? c.microGamepad?.buttonA.isPressed
                ?? false
            let aWas = aWasPressed[id] ?? false
            if aPressed && !aWas, manager.slot(for: c) != nil {
                if let pickIdx = myPickIdx {
                    confirmColorPick(slot: pickIdx)
                } else if let editIdx = myEditIdx {
                    confirmName(slot: editIdx)
                } else {
                    confirmFocusedMenu()
                }
                _ = midClaim
            }
            aWasPressed[id] = aPressed
        }
    }

    // MARK: - Keyboard

    private func handleKeyDown(_ code: GCKeyCode) {
        let kbSlot = manager.slots.first(where: { $0.keyboard != nil })?.index
        let kbPickIdx: Int? = kbSlot.flatMap { pickingColor[$0] != nil ? $0 : nil }
        let kbEditIdx: Int? = kbSlot.flatMap { nameEditing[$0] != nil ? $0 : nil }

        // Name-edit on the keyboard player's slot — eats most keys.
        if let editIdx = kbEditIdx {
            switch code {
            case .returnOrEnter, .keypadEnter:
                confirmName(slot: editIdx)
            case .escape:
                manager.releaseKeyboardSlot()
            case .deleteOrBackspace:
                if var st = nameEditing[editIdx], st.cursor > 0 {
                    let removeAt = st.buffer.index(st.buffer.startIndex, offsetBy: st.cursor - 1)
                    st.buffer.remove(at: removeAt)
                    st.cursor -= 1
                    nameEditing[editIdx] = st
                    renderSlots()
                }
            case .upArrow:    cycleLiveChar(slot: editIdx, by:  1)
            case .downArrow:  cycleLiveChar(slot: editIdx, by: -1)
            case .leftArrow:  moveCyclerCursor(slot: editIdx, by: -1)
            case .rightArrow: moveCyclerCursor(slot: editIdx, by:  1)
            default:
                if let ch = TitleScene.charFor(keyCode: code),
                   var st = nameEditing[editIdx],
                   st.buffer.count < 8 {
                    let insertAt = st.buffer.index(st.buffer.startIndex, offsetBy: st.cursor)
                    st.buffer.insert(ch, at: insertAt)
                    st.cursor += 1
                    nameEditing[editIdx] = st
                    renderSlots()
                }
            }
            return
        }

        // Color-pick on the keyboard player's slot.
        if let pickIdx = kbPickIdx {
            switch code {
            case .leftArrow:  cycleColorCandidate(slot: pickIdx, by: -1)
            case .rightArrow: cycleColorCandidate(slot: pickIdx, by:  1)
            case .returnOrEnter, .keypadEnter, .keyA, .spacebar:
                confirmColorPick(slot: pickIdx)
            case .escape, .keyB:
                manager.releaseKeyboardSlot()
            default: break
            }
            return
        }

        // Idle keyboard input — navigate the menu / claim / start. Esc and B
        // both release the keyboard slot when one exists (B mirrors the MFi
        // controller's "leave slot" button); Esc with no keyboard player
        // falls back to exiting Mac fullscreen.
        switch code {
        case .upArrow:    moveFocus(by: -1)
        case .downArrow:  moveFocus(by:  1)
        case .leftArrow:  cycleFocusedSelector(by: -1)
        case .rightArrow: cycleFocusedSelector(by:  1)
        case .keyH:       openHelp()
        case .escape:
            if manager.hasKeyboardPlayer { manager.releaseKeyboardSlot() }
            else { MacFullScreen.exitIfActive() }
        case .keyB:
            if manager.hasKeyboardPlayer { manager.releaseKeyboardSlot() }
        case .spacebar:   tryStart()
        case .returnOrEnter, .keypadEnter, .keyA:
            if !manager.hasKeyboardPlayer,
               manager.slots.count < ControllerManager.maxPlayers {
                _ = manager.claimKeyboard()
            } else {
                confirmFocusedMenu()
            }
        #if DEBUG
        case .keyD:       manager.claimDummy()
        #endif
        default: break
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

    // MARK: - Slot rendering

    private func renderSlots() {
        slotsLayer.removeAllChildren()
        let count = ControllerManager.maxPlayers
        let tileWidth: CGFloat = 110
        let spacing: CGFloat = 24
        let totalWidth = CGFloat(count) * tileWidth + CGFloat(count - 1) * spacing
        let startX = (size.width - totalWidth) / 2 + tileWidth / 2
        let y = size.height * 0.46
        let slotByIndex = Dictionary(manager.slots.map { ($0.index, $0) },
                                     uniquingKeysWith: { _, latest in latest })

        for i in 0..<count {
            let x = startX + CGFloat(i) * (tileWidth + spacing)
            let center = CGPoint(x: x, y: y)
            let slot = slotByIndex[i]
            let claimed = slot != nil
            let isPicking = pickingColor[i] != nil
            let isEditing = nameEditing[i] != nil
            let ringColor: SKColor = claimed ? (slot?.color ?? TitleScene.unclaimedRingColor)
                                             : TitleScene.unclaimedRingColor

            let tile = SKShapeNode(rectOf: CGSize(width: tileWidth, height: 110), cornerRadius: 8)
            tile.position = center
            tile.strokeColor = ringColor
            tile.fillColor = .black
            tile.lineWidth = isPicking ? 5 : 3
            tile.name = "slotTile"
            slotsLayer.addChild(tile)

            if claimed {
                let shipColor = slot?.color ?? TitleScene.accentGold
                let ship = Shapes.shipV(color: shipColor, scale: 1.6)
                ship.position = center
                ship.zRotation = .pi / 2
                slotsLayer.addChild(ship)
            }

            let storedName = UserDefaults.standard.string(forKey: "player_name_\(i)") ?? "P\(i + 1)"

            if isEditing {
                renderCyclerEditor(x: x, y: y,
                                   color: slot?.color ?? TitleScene.accentGold,
                                   slotIndex: i,
                                   isTouchSlot: slot?.touchInput != nil)
            } else if isPicking {
                renderColorPicker(x: x, y: y, color: slot?.color ?? TitleScene.accentGold)
            } else if claimed {
                let nameLabel = SKLabelNode(text: storedName)
                nameLabel.fontName = "AvenirNext-Regular"
                nameLabel.fontSize = 14
                nameLabel.fontColor = ringColor
                nameLabel.position = CGPoint(x: x, y: y - 79)
                slotsLayer.addChild(nameLabel)
            } else {
                // Unclaimed: stored name on top, JOIN below.
                let nameLabel = SKLabelNode(text: storedName)
                nameLabel.fontName = "AvenirNext-Regular"
                nameLabel.fontSize = 14
                nameLabel.fontColor = TitleScene.unclaimedRingColor
                nameLabel.position = CGPoint(x: x, y: y + 4)
                slotsLayer.addChild(nameLabel)

                let join = SKLabelNode(text: "JOIN")
                join.fontName = "AvenirNext-Bold"
                join.fontSize = 16
                join.fontColor = TitleScene.unclaimedRingColor
                join.position = CGPoint(x: x, y: y - 18)
                join.name = "joinLabel"
                slotsLayer.addChild(join)
            }
        }
    }

    /// Render the color-picker overlay on a slot tile mid-pickColor. Layout:
    ///   ← on the left edge of the tile, → on the right edge (both tappable),
    ///   a single-line hint below the tile.
    /// The tile ring + ghost ship already preview the candidate color, so the
    /// label below just summarises how to advance / cancel.
    /// (`←`/`→` rather than `◀`/`▶` because AvenirNext-Bold at this size
    /// renders the triangle glyphs as tofu on iPad.)
    private func renderColorPicker(x: CGFloat, y: CGFloat, color: SKColor) {
        let leftArrow = SKLabelNode(text: "\u{2190}")
        leftArrow.fontName = "AvenirNext-Bold"
        leftArrow.fontSize = 24
        leftArrow.fontColor = TitleScene.accentGold
        leftArrow.position = CGPoint(x: x - 40, y: y)
        leftArrow.verticalAlignmentMode = .center
        leftArrow.horizontalAlignmentMode = .center
        leftArrow.name = "colorArrowLeft"
        slotsLayer.addChild(leftArrow)

        let rightArrow = SKLabelNode(text: "\u{2192}")
        rightArrow.fontName = "AvenirNext-Bold"
        rightArrow.fontSize = 24
        rightArrow.fontColor = TitleScene.accentGold
        rightArrow.position = CGPoint(x: x + 40, y: y)
        rightArrow.verticalAlignmentMode = .center
        rightArrow.horizontalAlignmentMode = .center
        rightArrow.name = "colorArrowRight"
        slotsLayer.addChild(rightArrow)

        let title = SKLabelNode(text: "PICK COLOR")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 10
        title.fontColor = color
        title.position = CGPoint(x: x, y: y - 75)
        title.verticalAlignmentMode = .top
        slotsLayer.addChild(title)

        let hint = SKLabelNode(text: "TAP / A ACCEPT  ·  HOLD / B CANCEL")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 8
        hint.fontColor = SKColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: x, y: y - 92)
        hint.verticalAlignmentMode = .top
        slotsLayer.addChild(hint)
    }

    /// Render the in-tile cycler editor for the slot currently editing its
    /// name. Layout (anchored at slot tile center `(x, y)`):
    ///   y - 79 :  per-character buffer with the live char in gold at cursor
    ///   y - 92 :  caret marker (▲) under the cursor position
    ///   y - 104:  legend hint
    ///   y - 120:  touch button row (only when the touch player is editing)
    private func renderCyclerEditor(x: CGFloat, y: CGFloat, color: SKColor,
                                    slotIndex: Int, isTouchSlot: Bool) {
        guard let st = nameEditing[slotIndex] else { return }
        let bufferChars = Array(st.buffer)
        let liveChar = TitleScene.cyclerAlphabet[st.charIndex]

        var displayChars: [Character] = []
        let cursor = max(0, min(bufferChars.count, st.cursor))
        displayChars.append(contentsOf: bufferChars.prefix(cursor))
        displayChars.append(liveChar)
        displayChars.append(contentsOf: bufferChars.dropFirst(cursor))

        let advance: CGFloat = 11
        let totalWidth = CGFloat(displayChars.count - 1) * advance
        let startX = x - totalWidth / 2
        for (idx, ch) in displayChars.enumerated() {
            let lbl = SKLabelNode(text: String(ch))
            lbl.fontName = "AvenirNext-Bold"
            lbl.fontSize = 16
            lbl.fontColor = idx == cursor ? TitleScene.accentGold : color
            lbl.position = CGPoint(x: startX + CGFloat(idx) * advance, y: y - 79)
            slotsLayer.addChild(lbl)
        }

        let caret = SKLabelNode(text: "▲")
        caret.fontName = "AvenirNext-Bold"
        caret.fontSize = 9
        caret.fontColor = TitleScene.accentGold
        caret.position = CGPoint(x: startX + CGFloat(cursor) * advance, y: y - 92)
        slotsLayer.addChild(caret)

        let hint = SKLabelNode(text: "\u{2191}\u{2193} CYCLE  \u{2190}\u{2192} MOVE  X TYPE  A DONE")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 8
        hint.fontColor = SKColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: x, y: y - 104)
        slotsLayer.addChild(hint)

        if isTouchSlot {
            renderCyclerTouchButtons(centerX: x, baseY: y - 120, slotIndex: slotIndex)
        }
    }

    private func renderCyclerTouchButtons(centerX: CGFloat, baseY: CGFloat,
                                          slotIndex: Int) {
        let labels: [(Character, String)] = [
            ("\u{2190}", "cyclerBtnLeft"),
            ("\u{2191}", "cyclerBtnCycleFwd"),
            ("\u{2193}", "cyclerBtnCycleBack"),
            ("\u{2192}", "cyclerBtnRight"),
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
        _ = slotIndex
    }

    // MARK: - Selector rendering / cycling

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

        func style(_ arrow: SKLabelNode, item: FocusItem) {
            arrow.fontColor = focused == item ? active : inactive
            arrow.setScale(1.0)
        }
        style(modeLeftArrow,    item: .mode)
        style(modeRightArrow,   item: .mode)
        style(levelLeftArrow,   item: .level)
        style(levelRightArrow,  item: .level)
        style(densityLeftArrow, item: .density)
        style(densityRightArrow,item: .density)
        style(audioLeftArrow,   item: .audio)
        style(audioRightArrow,  item: .audio)
    }

    private func cycleFocusedSelector(by delta: Int) {
        switch focused {
        case .mode:    cycleMode(by: delta)
        case .level:   cycleLevel(by: delta)
        case .density: cycleDensity(by: delta)
        case .audio:   cycleAudio(by: delta)
        case .help, .start: break
        }
    }

    private func cycleSelectorValue(_ item: FocusItem, by delta: Int) {
        switch item {
        case .mode:    cycleMode(by: delta)
        case .level:   cycleLevel(by: delta)
        case .density: cycleDensity(by: delta)
        case .audio:   cycleAudio(by: delta)
        default: break
        }
    }

    private func cycleMode(by delta: Int) {
        selectedMode = (selectedMode == .survival) ? .battle : .survival
        _ = delta
        renderSelectors()
    }

    private func cycleAudio(by delta: Int) {
        let cases = AudioMode.allCases
        guard let i = cases.firstIndex(of: selectedAudio) else { return }
        let next = max(0, min(cases.count - 1, i + delta))
        if next != i {
            selectedAudio = cases[next]
            GameSettings.audioMode = selectedAudio
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

    // MARK: - Menu focus navigation

    private func moveFocus(by delta: Int) {
        let order: [FocusItem] = [.mode, .level, .density, .audio, .help, .start]
        guard let i = order.firstIndex(of: focused) else {
            focused = .start
            renderSelectors()
            return
        }
        let next = max(0, min(order.count - 1, i + delta))
        if next != i {
            focused = order[next]
            renderSelectors()
        }
    }

    /// A on a fully-claimed-idle controller (or on keyboard at idle) confirms
    /// whatever the menu focus is. Selectors are no-ops since ◀▶ cycles them
    /// directly; help/start trigger their actions.
    private func confirmFocusedMenu() {
        switch focused {
        case .help:  openHelp()
        case .start: tryStart()
        case .mode, .level, .density, .audio: break
        }
    }

    // MARK: - Flashes

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
            case "slotTile":
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
                .colorize(with: SKColor(red: 1.0, green: 0.7, blue: 0.7, alpha: 1),
                          colorBlendFactor: 1.0, duration: 0.12)
            ]),
            .group([
                .scale(to: 1.0,  duration: 0.18),
                .colorize(with: SKColor(red: 0.85, green: 0.45, blue: 0.45, alpha: 1),
                          colorBlendFactor: 0.0, duration: 0.18)
            ]),
            .wait(forDuration: 1.2),
            .fadeOut(withDuration: 0.4),
        ])
        battleHintLabel.run(pulse)

        let tilePulse = SKAction.sequence([
            .scale(to: 1.06, duration: 0.14),
            .scale(to: 1.0,  duration: 0.32)
        ])
        for node in slotsLayer.children where node.name == "slotTile" {
            node.removeAllActions()
            node.setScale(1.0)
            node.run(tilePulse)
        }
    }
}
