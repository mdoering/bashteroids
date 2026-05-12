import GameController

@MainActor
final class KeyboardManager {
    static let shared = KeyboardManager()

    var onKeyDown: ((GCKeyCode) -> Void)?

    private var connectObserver: NSObjectProtocol?

    init() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.installHandler() }
        }
        installHandler()
    }

    deinit {
        if let o = connectObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func installHandler() {
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return }
        input.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            MainActor.assumeIsolated {
                if pressed { self?.onKeyDown?(keyCode) }
            }
        }
    }

    func isPressed(_ code: GCKeyCode) -> Bool {
        GCKeyboard.coalesced?.keyboardInput?.button(forKeyCode: code)?.isPressed ?? false
    }
}
