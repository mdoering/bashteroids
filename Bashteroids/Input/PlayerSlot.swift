import GameController
import SpriteKit

struct PlayerInput {
    var turn: CGFloat = 0                 // -1...1 (negative = left)
    var thrust: Bool = false              // held
    var brake: Bool = false               // held — only effective if ship.hasBrakes
    var firePressedThisFrame: Bool = false // edge-triggered, consumed on read
}

final class PlayerSlot {
    let index: Int
    let color: SKColor
    weak var controller: GCController?
    let keyboard: KeyboardInputState?

    private var firePressedEdge: Bool = false

    init(index: Int, color: SKColor, controller: GCController) {
        self.index = index
        self.color = color
        self.controller = controller
        self.keyboard = nil
        installFireHandler()
    }

    init(index: Int, color: SKColor, keyboard: KeyboardInputState) {
        self.index = index
        self.color = color
        self.controller = nil
        self.keyboard = keyboard
    }

    deinit {
        removeFireHandler()
    }

    func snapshot() -> PlayerInput {
        if let kb = keyboard { return kb.snapshot() }

        let edge = firePressedEdge
        firePressedEdge = false

        if let gp = controller?.extendedGamepad {
            var turn = CGFloat(gp.leftThumbstick.xAxis.value)
            if abs(turn) < 0.15 {
                turn = CGFloat(gp.dpad.xAxis.value)
            }
            turn = max(-1, min(1, turn))

            let stickY = CGFloat(gp.rightThumbstick.yAxis.value)
            let thrust = gp.buttonA.isPressed || gp.rightTrigger.value > 0.2 || stickY > 0.2
            let brake  = gp.buttonB.isPressed || stickY < -0.2

            return PlayerInput(turn: turn, thrust: thrust, brake: brake, firePressedThisFrame: edge)
        }

        if let mg = controller?.microGamepad {
            let turn = max(-1, min(1, CGFloat(mg.dpad.xAxis.value)))
            let thrust = mg.dpad.yAxis.value > 0.2
            let brake  = mg.dpad.yAxis.value < -0.2
            return PlayerInput(turn: turn, thrust: thrust, brake: brake, firePressedThisFrame: edge)
        }

        return PlayerInput(turn: 0, thrust: false, brake: false, firePressedThisFrame: edge)
    }

    private func installFireHandler() {
        let handler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.firePressedEdge = true }
        }
        if let gp = controller?.extendedGamepad {
            gp.buttonX.pressedChangedHandler = handler
            gp.rightShoulder.pressedChangedHandler = handler
            gp.leftTrigger.pressedChangedHandler = handler
            return
        }
        if let mg = controller?.microGamepad {
            mg.buttonA.pressedChangedHandler = handler
        }
    }

    private func removeFireHandler() {
        if let gp = controller?.extendedGamepad {
            gp.buttonX.pressedChangedHandler = nil
            gp.rightShoulder.pressedChangedHandler = nil
            gp.leftTrigger.pressedChangedHandler = nil
            return
        }
        if let mg = controller?.microGamepad {
            mg.buttonA.pressedChangedHandler = nil
        }
    }
}
