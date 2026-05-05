import SwiftUI
import SpriteKit

struct GameContainerView: View {
    @FocusState private var focused: Bool

    var body: some View {
        GeometryReader { proxy in
            SpriteView(
                scene: makeScene(size: proxy.size),
                preferredFramesPerSecond: 60,
                options: [.ignoresSiblingOrder]
            )
        }
        .background(.black)
        .focusable()
        .focused($focused)
        .onAppear {
            MacFullScreen.enterIfNeeded()
            focused = true
        }
        .onKeyPress(.space)  { triggerStart() }
        .onKeyPress(.return) { triggerStart() }
        .onKeyPress(.escape) {
            MacFullScreen.exitIfActive()
            return .handled
        }
    }

    private func triggerStart() -> KeyPress.Result {
        ControllerManager.shared.simulateStartPressed()
        return .handled
    }

    private func makeScene(size: CGSize) -> SKScene {
        let scene = TitleScene(size: size)
        scene.scaleMode = .resizeFill
        return scene
    }
}

#if targetEnvironment(macCatalyst)
enum MacFullScreen {
    private static var requested = false

    static func enterIfNeeded() {
        guard !requested else { return }
        requested = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            toggle()
        }
    }

    static func exitIfActive() {
        if isInFullScreen() { toggle() }
    }

    private static func toggle() {
        firstWindow()?.perform(NSSelectorFromString("toggleFullScreen:"), with: nil)
    }

    private static func isInFullScreen() -> Bool {
        guard let mask = firstWindow()?.value(forKey: "styleMask") as? NSNumber else {
            return false
        }
        // NSWindow.StyleMask.fullScreen rawValue is 1 << 14.
        return mask.uintValue & (1 << 14) != 0
    }

    private static func firstWindow() -> NSObject? {
        guard let cls = NSClassFromString("NSApplication") else { return nil }
        let sharedSel = NSSelectorFromString("sharedApplication")
        guard let appAny = (cls as AnyObject).perform(sharedSel)?.takeUnretainedValue(),
              let app = appAny as? NSObject,
              let windows = app.value(forKey: "windows") as? [NSObject] else { return nil }
        return windows.first
    }
}
#else
enum MacFullScreen {
    static func enterIfNeeded() {}
    static func exitIfActive() {}
}
#endif
