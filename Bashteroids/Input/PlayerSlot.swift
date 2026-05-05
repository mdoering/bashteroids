import GameController
import SpriteKit

struct PlayerInput {
    var turn: CGFloat = 0                 // -1...1 (negative = left)
    var thrust: Bool = false              // held
    var firePressedThisFrame: Bool = false // edge-triggered, consumed on read
}

final class PlayerSlot {
    let index: Int
    let color: SKColor
    weak var controller: GCController?

    private var firePressedEdge: Bool = false

    init(index: Int, color: SKColor, controller: GCController) {
        self.index = index
        self.color = color
        self.controller = controller
        installFireHandler()
    }

    deinit {
        removeFireHandler()
    }

    func snapshot() -> PlayerInput {
        let edge = firePressedEdge
        firePressedEdge = false

        guard let gp = controller?.extendedGamepad else {
            return PlayerInput(turn: 0, thrust: false, firePressedThisFrame: edge)
        }

        var turn = CGFloat(gp.leftThumbstick.xAxis.value)
        if abs(turn) < 0.15 {
            turn = CGFloat(gp.dpad.xAxis.value)
        }
        turn = max(-1, min(1, turn))

        let thrust = gp.buttonA.isPressed || gp.rightTrigger.value > 0.2

        return PlayerInput(turn: turn, thrust: thrust, firePressedThisFrame: edge)
    }

    private func installFireHandler() {
        guard let gp = controller?.extendedGamepad else { return }
        let handler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.firePressedEdge = true }
        }
        gp.buttonX.pressedChangedHandler = handler
        gp.rightShoulder.pressedChangedHandler = handler
    }

    private func removeFireHandler() {
        guard let gp = controller?.extendedGamepad else { return }
        gp.buttonX.pressedChangedHandler = nil
        gp.rightShoulder.pressedChangedHandler = nil
    }
}
