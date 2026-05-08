import Combine
import Foundation

/// SwiftUI-observable state for the touch-control overlay. Tracks which scene
/// is currently presented (so the overlay shows different things on title
/// vs in-game) and whether a touch slot has been claimed (no buttons until
/// somebody actually taps to join as a touch player).
@MainActor
final class TouchOverlayState: ObservableObject {
    static let shared = TouchOverlayState()

    enum Scene { case title, game, gameOver, other }

    @Published private(set) var scene: Scene = .other
    @Published private(set) var hasTouchSlot: Bool = false

    /// `true` when the in-game touch HUD (turn / thrust / brake buttons +
    /// tap-to-fire zone) should be visible.
    var inGameHUDVisible: Bool { scene == .game && hasTouchSlot }
    /// `true` when the title-screen tap-catcher should be active.
    var titleTapActive: Bool { scene == .title }
    /// `true` when the game-over tap-catcher should be active.
    var gameOverTapActive: Bool { scene == .gameOver }

    func setScene(_ scene: Scene) {
        if self.scene != scene { self.scene = scene }
    }

    /// Refresh `hasTouchSlot` from the live ControllerManager. Called by
    /// ControllerManager whenever its slot list changes.
    func recompute() {
        let value = ControllerManager.shared.hasTouchPlayer
        if hasTouchSlot != value { hasTouchSlot = value }
    }
}

extension Notification.Name {
    /// Posted by the SwiftUI title overlay when the user taps (<0.5 s)
    /// inside the SpriteView area. `userInfo["location"]` is a CGPoint in
    /// SpriteKit scene coordinates (origin bottom-left).
    static let titleSceneTap = Notification.Name("TitleSceneTap")

    /// Posted by the SwiftUI title overlay when the user holds (≥0.5 s)
    /// inside the SpriteView area. Same `userInfo` shape as titleSceneTap.
    static let titleSceneLongPress = Notification.Name("TitleSceneLongPress")

    /// Posted by the SwiftUI game-over overlay on tap. Same userInfo shape.
    static let gameOverSceneTap = Notification.Name("GameOverSceneTap")
}
