import GameController
import SpriteKit

@MainActor
final class ControllerManager {
    static let shared = ControllerManager()
    static let maxPlayers = 4
    static let playerColors: [SKColor] = [
        SKColor(red: 1.00, green: 0.30, blue: 0.30, alpha: 1), // red
        SKColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 1), // blue
        SKColor(red: 0.45, green: 0.95, blue: 0.45, alpha: 1), // green
        SKColor(red: 1.00, green: 0.90, blue: 0.30, alpha: 1), // yellow
    ]

    private(set) var slots: [PlayerSlot] = []
    let keyboardInput = KeyboardInputState()

    var onSlotsChanged: (() -> Void)?
    var onStartPressed: (() -> Void)?

    var hasKeyboardPlayer: Bool { slots.contains { $0.keyboard != nil } }
    var hasTouchPlayer: Bool    { slots.contains { $0.touchInput != nil } }

    private var joinEnabled = false
    /// For unclaimed controllers, which empty slot index this controller will
    /// claim when its A button fires. Defaults to the leftmost empty slot
    /// when not set.
    private var intendedSlot: [ObjectIdentifier: Int] = [:]
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?

    init() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let c = note.object as? GCController else { return }
            MainActor.assumeIsolated { self.handleConnect(c) }
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let c = note.object as? GCController else { return }
            MainActor.assumeIsolated { self.handleDisconnect(c) }
        }

        for c in GCController.controllers() {
            wireSystemHandlers(c)
            assignDefaultIntent(for: c)
            installJoinHandler(c)
        }
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    deinit {
        if let o = connectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = disconnectObserver { NotificationCenter.default.removeObserver(o) }
        GCController.stopWirelessControllerDiscovery()
    }

    var connectedControllers: [GCController] { GCController.controllers() }

    func simulateStartPressed() {
        onStartPressed?()
    }

    func slot(for controller: GCController) -> PlayerSlot? {
        slots.first { $0.controller === controller }
    }

    func intendedSlotIndex(for controller: GCController) -> Int {
        let id = ObjectIdentifier(controller)
        if let idx = intendedSlot[id], emptySlotIndices().contains(idx) {
            return idx
        }
        return emptySlotIndices().first ?? 0
    }

    func setIntendedSlotIndex(_ idx: Int, for controller: GCController) {
        let id = ObjectIdentifier(controller)
        intendedSlot[id] = idx
    }

    /// Indices in 0..<maxPlayers that aren't currently claimed.
    func emptySlotIndices() -> [Int] {
        let claimed = Set(slots.map { $0.index })
        return (0..<Self.maxPlayers).filter { !claimed.contains($0) }
    }

    func setJoinEnabled(_ enabled: Bool) {
        joinEnabled = enabled
        for c in connectedControllers {
            installJoinHandler(c)
        }
    }

    func releaseAllSlots() {
        slots.removeAll()
        for c in connectedControllers {
            installJoinHandler(c)
        }
        TouchOverlayState.shared.recompute()
        onSlotsChanged?()
    }

    /// Release the touch player's slot, if any. Used by the iPad
    /// title-tap path: tapping the touch player's own slot leaves it.
    func releaseTouchSlot() {
        guard hasTouchPlayer else { return }
        slots.removeAll { $0.touchInput != nil }
        TouchOverlayState.shared.recompute()
        onSlotsChanged?()
    }

    /// Release a single controller's slot — used by the title scene's "leave
    /// slot" binding (B on extended controllers). The controller becomes
    /// joinable again immediately, with its preview marker parked on the
    /// slot it just left so it doesn't snap back to the leftmost (red) tile.
    func releaseSlot(for controller: GCController) {
        guard let slot = slot(for: controller) else { return }
        let releasedIndex = slot.index
        slots.removeAll { $0.controller === controller }
        intendedSlot[ObjectIdentifier(controller)] = releasedIndex
        installJoinHandler(controller)
        TouchOverlayState.shared.recompute()
        onSlotsChanged?()
    }

    // MARK: - Notifications

    private func handleConnect(_ controller: GCController) {
        wireSystemHandlers(controller)
        assignDefaultIntent(for: controller)
        installJoinHandler(controller)
        TouchOverlayState.shared.recompute()
        onSlotsChanged?()
    }

    /// Pick a default intended slot for a freshly connected controller,
    /// avoiding slots already targeted by other unclaimed controllers — so
    /// two controllers connecting to a fresh title don't both stack their
    /// preview triangles on the leftmost (red) tile.
    private func assignDefaultIntent(for controller: GCController) {
        let id = ObjectIdentifier(controller)
        let empty = emptySlotIndices()
        let alreadyTargeted = Set(
            intendedSlot
                .filter { $0.key != id }
                .values
        )
        if let pick = empty.first(where: { !alreadyTargeted.contains($0) }) ?? empty.first {
            intendedSlot[id] = pick
        }
    }

    private func handleDisconnect(_ controller: GCController) {
        let removed = slots.contains { $0.controller === controller }
        slots.removeAll { $0.controller === controller }
        intendedSlot.removeValue(forKey: ObjectIdentifier(controller))
        if removed {
            TouchOverlayState.shared.recompute()
            onSlotsChanged?()
        }
    }

    // MARK: - Handler wiring

    private func wireSystemHandlers(_ controller: GCController) {
        // Menu/Start is polled per-frame by TitleScene/GameOverScene rather
        // than wired through pressedChangedHandler. The handler-based path
        // turned out to be unreliable across fullscreen transitions.
        configureMicroGamepad(controller)
    }

    private func configureMicroGamepad(_ controller: GCController) {
        guard let mg = controller.microGamepad else { return }
        mg.reportsAbsoluteDpadValues = true
        mg.allowsRotation = false
    }

    private func installJoinHandler(_ controller: GCController) {
        if let gp = controller.extendedGamepad {
            if joinEnabled && slot(for: controller) == nil {
                gp.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                    guard pressed, let self else { return }
                    self.claim(controller: controller,
                               atSlot: self.intendedSlotIndex(for: controller))
                }
            } else {
                gp.buttonA.pressedChangedHandler = nil
            }
            return
        }

        if let mg = controller.microGamepad {
            if joinEnabled && slot(for: controller) == nil {
                mg.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                    guard pressed, let self else { return }
                    self.claim(controller: controller,
                               atSlot: self.intendedSlotIndex(for: controller))
                }
            } else {
                mg.buttonA.pressedChangedHandler = nil
            }
        }
    }

    @discardableResult
    func claimKeyboard() -> PlayerSlot? {
        guard !hasKeyboardPlayer, slots.count < Self.maxPlayers else { return nil }
        return claimKeyboard(atSlot: slots.count)
    }

    /// Claim a specific empty slot for the keyboard player.
    @discardableResult
    func claimKeyboard(atSlot index: Int) -> PlayerSlot? {
        guard !hasKeyboardPlayer else { return nil }
        guard emptySlotIndices().contains(index) else { return nil }
        let slot = PlayerSlot(index: index, color: Self.playerColors[index], keyboard: keyboardInput)
        slots.append(slot)
        slots.sort { $0.index < $1.index }
        TouchOverlayState.shared.recompute()
        onSlotsChanged?()
        return slot
    }

    /// Public claim path used by TitleScene's focus-confirm flow when an
    /// unclaimed controller activates a focused slot tile. The internal
    /// pressedChangedHandler-based claim path also funnels through here.
    @discardableResult
    func claim(controller: GCController, atSlot index: Int) -> PlayerSlot? {
        return internalClaim(controller: controller, atSlot: index)
    }

    /// Claim a specific empty slot for the touch player. At most one touch
    /// slot may exist at a time; subsequent calls are no-ops.
    @discardableResult
    func claimTouch(atSlot index: Int) -> PlayerSlot? {
        guard !hasTouchPlayer else { return nil }
        guard emptySlotIndices().contains(index) else { return nil }
        let slot = PlayerSlot(touchIndex: index,
                              color: Self.playerColors[index],
                              touchInput: TouchInputState.shared)
        slots.append(slot)
        slots.sort { $0.index < $1.index }
        TouchOverlayState.shared.recompute()
        onSlotsChanged?()
        return slot
    }

    #if DEBUG
    /// Claim a dummy slot with no controller and no keyboard. The ship spawned
    /// for it sits still and ignores all input — useful as a target.
    @discardableResult
    func claimDummy() -> PlayerSlot? {
        guard slots.count < Self.maxPlayers else { return nil }
        let index = slots.count
        let slot = PlayerSlot(dummyIndex: index, color: Self.playerColors[index])
        slots.append(slot)
        TouchOverlayState.shared.recompute()
        onSlotsChanged?()
        return slot
    }
    #endif

    @discardableResult
    private func internalClaim(controller: GCController, atSlot index: Int) -> PlayerSlot? {
        guard slot(for: controller) == nil else { return nil }
        guard emptySlotIndices().contains(index) else { return nil }
        let slot = PlayerSlot(
            index: index,
            color: Self.playerColors[index],
            controller: controller
        )
        slots.append(slot)
        slots.sort { $0.index < $1.index }   // keep iteration order stable
        intendedSlot.removeValue(forKey: ObjectIdentifier(controller))
        installJoinHandler(controller)
        TouchOverlayState.shared.recompute()
        onSlotsChanged?()
        return slot
    }
}
