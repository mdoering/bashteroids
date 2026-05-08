import SwiftUI
import SpriteKit

struct GameContainerView: View {
    @StateObject private var nameEntry = NameEntryCoordinator.shared
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

            #if os(iOS)
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

            #if os(tvOS) || os(iOS)
            if nameEntry.request != nil {
                NameEntryOverlay(coordinator: nameEntry)
            }
            #endif
        }
        .onAppear { MacFullScreen.enterIfNeeded() }
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
