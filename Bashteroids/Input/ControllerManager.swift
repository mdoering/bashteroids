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

    var onSlotsChanged: (() -> Void)?
    var onStartPressed: (() -> Void)?

    private var joinEnabled = false
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
        onSlotsChanged?()
    }

    // MARK: - Notifications

    private func handleConnect(_ controller: GCController) {
        wireSystemHandlers(controller)
        installJoinHandler(controller)
        onSlotsChanged?()
    }

    private func handleDisconnect(_ controller: GCController) {
        let removed = slots.contains { $0.controller === controller }
        slots.removeAll { $0.controller === controller }
        if removed { onSlotsChanged?() }
    }

    // MARK: - Handler wiring

    private func wireSystemHandlers(_ controller: GCController) {
        // Menu/Start is polled per-frame by TitleScene/GameOverScene rather
        // than wired through pressedChangedHandler. The handler-based path
        // turned out to be unreliable across fullscreen transitions.
    }

    private func installJoinHandler(_ controller: GCController) {
        guard let gp = controller.extendedGamepad else { return }
        if joinEnabled && slot(for: controller) == nil {
            gp.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed, let self else { return }
                self.claim(controller: controller)
            }
        } else {
            gp.buttonA.pressedChangedHandler = nil
        }
    }

    @discardableResult
    private func claim(controller: GCController) -> PlayerSlot? {
        guard slots.count < Self.maxPlayers else { return nil }
        guard slot(for: controller) == nil else { return nil }
        let index = slots.count
        let slot = PlayerSlot(
            index: index,
            color: Self.playerColors[index],
            controller: controller
        )
        slots.append(slot)
        installJoinHandler(controller)
        onSlotsChanged?()
        return slot
    }
}
