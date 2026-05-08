import SwiftUI
import SpriteKit

struct GameContainerView: View {
    @ObservedObject private var touchOverlay = TouchOverlayState.shared

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                SpriteView(
                    scene: makeScene(size: proxy.size),
                    preferredFramesPerSecond: 60,
                    options: [.ignoresSiblingOrder]
                )
            }
            .background(.black)

            // Touch overlays are intentionally iPad-only. On Mac Catalyst
            // mouse clicks would otherwise pose as touches and silently
            // claim a touch slot, which on Mac is never what the user
            // intended (they have a real keyboard).
            #if os(iOS) && !targetEnvironment(macCatalyst)
            if touchOverlay.titleTapActive {
                TitleTapCatcher()
                    .ignoresSafeArea()
            }
            if touchOverlay.helpTapActive {
                HelpTapCatcher()
                    .ignoresSafeArea()
            }
            if touchOverlay.gameOverTapActive {
                GameOverTapCatcher()
                    .ignoresSafeArea()
            }
            if touchOverlay.inGameHUDVisible {
                TouchHUDView()
                    .ignoresSafeArea()
            }
            #endif
        }
        .onAppear {
            MacFullScreen.enterIfNeeded()
            // Pre-warm the audio singletons so CoreAudio's render thread
            // has fully ramped before the first user input. Without this,
            // a Mac Catalyst main-thread spike on the very first focus
            // move can push the music's HAL output past its buffer
            // deadline (audible click + an `IOWorkLoop: skipping cycle
            // due to overload` log). Touching the singletons here forces
            // their inits to run during launch, when the main thread is
            // already busy and no audio is yet playing.
            _ = AudioEngine.shared
            _ = MusicPlayer.shared
        }
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
