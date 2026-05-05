import SpriteKit
import GameController

final class GameOverScene: SKScene {
    enum Result {
        case gameOver
        case winner(color: SKColor, label: String)
    }

    private let result: Result
    private let manager = ControllerManager.shared
    private var transitioning = false
    private var prevButtonState: [ObjectIdentifier: (menu: Bool, a: Bool)] = [:]

    init(size: CGSize, result: Result) {
        self.result = result
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override var canBecomeFirstResponder: Bool { true }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        becomeFirstResponder()

        let (text, color): (String, SKColor) = {
            switch result {
            case .gameOver: return ("GAME OVER", .white)
            case .winner(let c, let label): return (label, c)
            }
        }()

        let banner = SKLabelNode(text: text)
        banner.fontName = "AvenirNext-Bold"
        banner.fontSize = 72
        banner.fontColor = color
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        addChild(banner)

        let hint = SKLabelNode(text: "PRESS A · START · SPACE")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 18
        hint.fontColor = SKColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: size.width / 2, y: size.height * 0.34)
        addChild(hint)
    }

    override func update(_ currentTime: TimeInterval) {
        guard !transitioning else { return }
        for c in manager.connectedControllers {
            let menu = c.extendedGamepad?.buttonMenu.isPressed ?? false
            let a    = c.extendedGamepad?.buttonA.isPressed    ?? false
            let id = ObjectIdentifier(c)
            let prev = prevButtonState[id] ?? (false, false)

            if (menu && !prev.menu) || (a && !prev.a) {
                returnToTitle()
                break
            }
            prevButtonState[id] = (menu, a)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardSpacebar, .keyboardReturnOrEnter:
                returnToTitle()
                return
            case .keyboardEscape:
                MacFullScreen.exitIfActive()
                return
            default:
                break
            }
        }
        super.pressesBegan(presses, with: event)
    }

    private func returnToTitle() {
        guard !transitioning else { return }
        transitioning = true
        let title = TitleScene(size: size)
        title.scaleMode = scaleMode
        view?.presentScene(title, transition: .fade(withDuration: 0.4))
    }
}
