import SwiftUI

@main
struct BashteroidsApp: App {
    var body: some Scene {
        WindowGroup {
            gameView
        }
    }

    @ViewBuilder
    private var gameView: some View {
        #if targetEnvironment(macCatalyst)
        GameContainerView()
        #elseif os(iOS)
        GameContainerView()
            .ignoresSafeArea()
            .statusBarHidden()
            .persistentSystemOverlays(.hidden)
        #else
        GameContainerView()
            .ignoresSafeArea()
        #endif
    }
}
