import CoreGraphics

/// Per-frame touch input state for one iPad/Mac touch player. Mirrors
/// KeyboardInputState's interface: held flags for axes, edge triggers for
/// fire and minelayer/torpedo. Exactly one player can be a touch player —
/// `ControllerManager.claimTouch(atSlot:)` enforces that.
///
/// All access is implicitly main-thread (SwiftUI gestures + GameScene update
/// both run on main); no isolation is enforced so callers don't need to be
/// MainActor-annotated.
final class TouchInputState {
    static let shared = TouchInputState()

    var leftHeld:   Bool = false
    var rightHeld:  Bool = false
    var thrustHeld: Bool = false
    var brakeHeld:  Bool = false

    private var fireEdge: Bool = false
    private var mineEdge: Bool = false

    func fireTriggered() { fireEdge = true }
    func mineTriggered() { mineEdge = true }

    func snapshot() -> PlayerInput {
        let fire = fireEdge; fireEdge = false
        let mine = mineEdge; mineEdge = false
        let turn: CGFloat = rightHeld ? 1 : (leftHeld ? -1 : 0)
        return PlayerInput(turn: turn,
                           thrust: thrustHeld,
                           brake: brakeHeld,
                           firePressedThisFrame: fire,
                           minelayerActionPressedThisFrame: mine)
    }

    func releaseAll() {
        leftHeld = false; rightHeld = false
        thrustHeld = false; brakeHeld = false
        fireEdge = false; mineEdge = false
    }
}
