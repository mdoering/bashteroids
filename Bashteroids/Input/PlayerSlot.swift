import GameController
import SpriteKit

struct PlayerInput {
    var turn: CGFloat = 0                 // -1...1 (negative = left)
    var thrust: Bool = false              // held
    var brake: Bool = false               // held
    var firePressedThisFrame: Bool = false // edge-triggered, consumed on read
    var minelayerActionPressedThisFrame: Bool = false // edge-triggered, consumed on read
}

final class PlayerSlot {
    let index: Int
    var color: SKColor
    weak var controller: GCController?
    let keyboard: KeyboardInputState?
    let touchInput: TouchInputState?

    private var firePressedEdge: Bool = false
    private var minelayerEdge: Bool = false

    init(index: Int, color: SKColor, controller: GCController) {
        self.index = index
        self.color = color
        self.controller = controller
        self.keyboard = nil
        self.touchInput = nil
        installFireHandler()
    }

    init(index: Int, color: SKColor, keyboard: KeyboardInputState) {
        self.index = index
        self.color = color
        self.controller = nil
        self.keyboard = keyboard
        self.touchInput = nil
    }

    init(touchIndex index: Int, color: SKColor, touchInput: TouchInputState) {
        self.index = index
        self.color = color
        self.controller = nil
        self.keyboard = nil
        self.touchInput = touchInput
    }

    /// DEBUG: dummy slot with no input source. snapshot() returns the all-zero
    /// PlayerInput so the ship sits still and ignores controllers/keyboards.
    init(dummyIndex index: Int, color: SKColor) {
        self.index = index
        self.color = color
        self.controller = nil
        self.keyboard = nil
        self.touchInput = nil
    }

    deinit {
        removeFireHandler()
    }

    func snapshot() -> PlayerInput {
        if let kb = keyboard { return kb.snapshot() }
        if let touch = touchInput { return touch.snapshot() }

        let edge = firePressedEdge
        firePressedEdge = false
        let mineEdge = minelayerEdge
        minelayerEdge = false

        if let gp = controller?.extendedGamepad {
            var turn = CGFloat(gp.leftThumbstick.xAxis.value)
            if abs(turn) < 0.15 {
                turn = CGFloat(gp.dpad.xAxis.value)
            }
            turn = max(-1, min(1, turn))

            let stickY = CGFloat(gp.rightThumbstick.yAxis.value)
            let thrust = gp.buttonA.isPressed || gp.rightTrigger.value > 0.2 || stickY > 0.2
            let brake  = gp.buttonB.isPressed || stickY < -0.2

            return PlayerInput(turn: turn,
                               thrust: thrust,
                               brake: brake,
                               firePressedThisFrame: edge,
                               minelayerActionPressedThisFrame: mineEdge)
        }

        if let mg = controller?.microGamepad {
            let turn = max(-1, min(1, CGFloat(mg.dpad.xAxis.value)))
            let thrust = mg.dpad.yAxis.value > 0.2
            let brake  = mg.dpad.yAxis.value < -0.2
            return PlayerInput(turn: turn,
                               thrust: thrust,
                               brake: brake,
                               firePressedThisFrame: edge,
                               minelayerActionPressedThisFrame: false)
        }

        return PlayerInput(turn: 0,
                           thrust: false,
                           brake: false,
                           firePressedThisFrame: edge,
                           minelayerActionPressedThisFrame: mineEdge)
    }

    private func installFireHandler() {
        let handler: GCControllerButtonValueChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.firePressedEdge = true }
        }
        if let gp = controller?.extendedGamepad {
            gp.buttonX.pressedChangedHandler = handler
            gp.rightShoulder.pressedChangedHandler = handler
            gp.leftTrigger.pressedChangedHandler = handler

            gp.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed { self?.minelayerEdge = true }
            }
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
            gp.buttonY.pressedChangedHandler = nil
            return
        }
        if let mg = controller?.microGamepad {
            mg.buttonA.pressedChangedHandler = nil
        }
    }
}
