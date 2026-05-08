#if os(iOS)
import SwiftUI

/// On-screen controls for the iPad/Mac touch player. Two stacked buttons in
/// each lower corner (turn ←/→ on the left, thrust/brake on the right) plus
/// a full-area tap zone underneath: tap-anywhere-not-on-a-button fires;
/// long-press triggers the special action (mine / torpedo).
///
/// Visible only when a touch slot is claimed AND the game scene is presented.
struct TouchHUDView: View {
    private let gold = Color(red: 245/255, green: 194/255, blue: 66/255)

    var body: some View {
        ZStack {
            // Tap-anywhere-not-on-a-button zone for fire / minelayer.
            // Long-press first so a quick tap falls through to .onTapGesture.
            Color.clear
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.5) {
                    TouchInputState.shared.mineTriggered()
                }
                .onTapGesture {
                    TouchInputState.shared.fireTriggered()
                }

            HStack(alignment: .bottom) {
                VStack(spacing: 18) {
                    HoldButton(symbol: "◀", color: gold) { pressed in
                        TouchInputState.shared.leftHeld = pressed
                    }
                    HoldButton(symbol: "▶", color: gold) { pressed in
                        TouchInputState.shared.rightHeld = pressed
                    }
                }
                Spacer()
                VStack(spacing: 18) {
                    HoldButton(symbol: "▲", color: gold) { pressed in
                        TouchInputState.shared.thrustHeld = pressed
                    }
                    HoldButton(symbol: "▼", color: gold) { pressed in
                        TouchInputState.shared.brakeHeld = pressed
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
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
                            let scenePoint = CGPoint(
                                x: value.location.x,
                                y: proxy.size.height - value.location.y
                            )
                            let name: Notification.Name = elapsed >= 0.5
                                ? .titleSceneLongPress
                                : .titleSceneTap
                            NotificationCenter.default.post(
                                name: name,
                                object: nil,
                                userInfo: ["location": scenePoint]
                            )
                        }
                )
        }
    }
}
#endif
