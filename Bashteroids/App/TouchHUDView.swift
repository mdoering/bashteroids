#if os(iOS)
import SwiftUI

/// On-screen controls for the iPad/Mac touch player.
///
///   Bottom-left: ◀ ▶ side-by-side (turn).
///   Bottom-right (2×2):
///     [D] [▲]      deploy (mine/torpedo) · thrust
///     [●] [▼]      fire                  · brake
///
/// Each button is a HoldButton — turn / thrust / brake use the press/release
/// state to drive the `…Held` flags in TouchInputState; fire and mine fire
/// their respective edge triggers on press.
///
/// Visible only when a touch slot is claimed AND the game scene is presented.
struct TouchHUDView: View {
    private let gold = Color(red: 245/255, green: 194/255, blue: 66/255)

    var body: some View {
        HStack(alignment: .bottom) {
            // Bottom-left: turn-left / turn-right side-by-side.
            HStack(spacing: 18) {
                HoldButton(symbol: "◀", color: gold) { pressed in
                    TouchInputState.shared.leftHeld = pressed
                }
                HoldButton(symbol: "▶", color: gold) { pressed in
                    TouchInputState.shared.rightHeld = pressed
                }
            }

            Spacer()

            // Bottom-right: 2×2 action grid.
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    HoldButton(symbol: "D", color: gold) { pressed in
                        if pressed { TouchInputState.shared.mineTriggered() }
                    }
                    HoldButton(symbol: "▲", color: gold) { pressed in
                        TouchInputState.shared.thrustHeld = pressed
                    }
                }
                HStack(spacing: 18) {
                    HoldButton(symbol: "●", color: gold) { pressed in
                        if pressed { TouchInputState.shared.fireTriggered() }
                    }
                    HoldButton(symbol: "▼", color: gold) { pressed in
                        TouchInputState.shared.brakeHeld = pressed
                    }
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct HoldButton: View {
    let symbol: String
    let color: Color
    let onPressedChange: (Bool) -> Void

    @State private var pressed: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(pressed ? 0.55 : 0.3))
                .frame(width: 70, height: 70)
            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: 70, height: 70)
            Text(symbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(color)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !pressed { pressed = true; onPressedChange(true) }
                }
                .onEnded { _ in
                    pressed = false
                    onPressedChange(false)
                }
        )
    }
}

/// Transparent full-screen tap catcher for the help scene. Any tap
/// dismisses (returns to title) — matches the keyboard ESC/SPACE and
/// "any controller button" behaviour.
struct HelpTapCatcher: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .helpSceneTap, object: nil)
            }
    }
}

/// Transparent full-screen tap catcher for the game-over scene. Forwards
/// every tap (in SpriteKit scene coordinates) to GameOverScene via the
/// .gameOverSceneTap notification.
struct GameOverTapCatcher: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let scenePoint = CGPoint(
                                x: value.location.x,
                                y: proxy.size.height - value.location.y
                            )
                            NotificationCenter.default.post(
                                name: .gameOverSceneTap,
                                object: nil,
                                userInfo: ["location": scenePoint]
                            )
                        }
                )
        }
    }
}

/// Transparent full-screen tap catcher for the title scene. Forwards each
/// gesture's location (in SpriteKit scene coordinates) to TitleScene via
/// NotificationCenter — short presses claim a slot, long presses (≥0.5 s)
/// open the name editor for an already-claimed touch slot.
struct TitleTapCatcher: View {
    @State private var pressStart: Date?

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if pressStart == nil { pressStart = Date() }
                        }
                        .onEnded { value in
                            let elapsed = pressStart.map { Date().timeIntervalSince($0) } ?? 0
                            pressStart = nil

                            let dx = value.translation.width
                            let dy = value.translation.height
                            let absDx = abs(dx)
                            let absDy = abs(dy)
                            let startScenePoint = CGPoint(
                                x: value.startLocation.x,
                                y: proxy.size.height - value.startLocation.y
                            )
                            let endScenePoint = CGPoint(
                                x: value.location.x,
                                y: proxy.size.height - value.location.y
                            )

                            // Horizontal swipe takes precedence over tap /
                            // long-press classification. 30 pt is the
                            // smallest swipe iOS treats as deliberate.
                            if absDx > 30 && absDx > absDy {
                                NotificationCenter.default.post(
                                    name: .titleSceneSwipe,
                                    object: nil,
                                    userInfo: [
                                        "location": startScenePoint,
                                        "direction": dx > 0 ? 1 : -1
                                    ]
                                )
                                return
                            }

                            let name: Notification.Name = elapsed >= 0.5
                                ? .titleSceneLongPress
                                : .titleSceneTap
                            NotificationCenter.default.post(
                                name: name,
                                object: nil,
                                userInfo: ["location": endScenePoint]
                            )
                        }
                )
        }
    }
}
#endif
