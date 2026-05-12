import CoreGraphics
import GameController

final class KeyboardInputState {
    private var spaceEdge = false
    private var deployEdge = false

    func spaceDown()     { spaceEdge = true }
    func deployPressed() { deployEdge = true }

    func snapshot() -> PlayerInput {
        let kb = GCKeyboard.coalesced?.keyboardInput
        let leftHeld  = kb?.button(forKeyCode: .leftArrow)?.isPressed  ?? false
        let rightHeld = kb?.button(forKeyCode: .rightArrow)?.isPressed ?? false
        let upHeld    = kb?.button(forKeyCode: .upArrow)?.isPressed    ?? false
        let downHeld  = kb?.button(forKeyCode: .downArrow)?.isPressed  ?? false

        let fire = spaceEdge; spaceEdge = false
        let mine = deployEdge; deployEdge = false
        let turn: CGFloat = rightHeld ? 1 : (leftHeld ? -1 : 0)
        return PlayerInput(turn: turn,
                           thrust: upHeld,
                           brake: downHeld,
                           firePressedThisFrame: fire,
                           minelayerActionPressedThisFrame: mine)
    }

    func releaseAll() {
        spaceEdge = false
        deployEdge = false
    }
}
