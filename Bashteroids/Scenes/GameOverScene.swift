import SpriteKit
import GameController

final class GameOverScene: SKScene {
    enum Result {
        case gameOver(topScore: Int)
        case winner(color: SKColor, label: String, score: Int)
        case battleWinner(color: SKColor, name: String)
        case battleDraw
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

    private func renderBanner(text: String, color: SKColor) {
        let banner = SKLabelNode(text: text)
        banner.fontName = "AvenirNext-Bold"
        banner.fontSize = 72
        banner.fontColor = color
        banner.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        addChild(banner)
    }

    private func renderSubtitle(text: String) {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 32
        label.fontColor = SKColor(white: 0.75, alpha: 1)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.45)
        addChild(label)
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black

        switch result {
        case .gameOver(let s):
            renderBanner(text: "GAME OVER", color: .white)
            renderSubtitle(text: "SCORE  \(s)")
        case .winner(let c, let label, let s):
            renderBanner(text: label, color: c)
            renderSubtitle(text: "SCORE  \(s)")
        case .battleWinner(let c, let name):
            renderBanner(text: "\(name) WINS", color: c)
        case .battleDraw:
            renderBanner(text: "DRAW", color: .white)
        }

        let hint = SKLabelNode(text: "PRESS A · START · SPACE")
        hint.fontName = "AvenirNext-Regular"
        hint.fontSize = 18
        hint.fontColor = SKColor(white: 0.55, alpha: 1)
        hint.position = CGPoint(x: size.width / 2, y: size.height * 0.34)
        addChild(hint)

        KeyboardManager.shared.onKeyDown = { [weak self] code in
            self?.handleKeyDown(code)
        }
    }

    private func handleKeyDown(_ code: GCKeyCode) {
        switch code {
        case .keyA, .spacebar, .returnOrEnter, .keypadEnter:
            returnToTitle()
        case .escape:
            MacFullScreen.exitIfActive()
        default:
            break
        }
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

    private func returnToTitle() {
        guard !transitioning else { return }
        transitioning = true
        let title = TitleScene(size: size)
        title.scaleMode = scaleMode
        view?.presentScene(title, transition: .fade(withDuration: 0.4))
    }
}
