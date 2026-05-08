import SpriteKit
import GameController

final class GameOverScene: SKScene {
    enum Result {
        case survivalEnd(lastPlayerName: String, lastPlayerColor: SKColor,
                         baseScore: Int, density: PowerUpDensity, playerCount: Int)
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

        // Defensive: GameScene.willMove already stops thrust audio, but if
        // any thrust loop survived the transition we silence it again here
        // so the game-over screen is silent.
        AudioEngine.shared.stopAllThrust()

        switch result {
        case .survivalEnd(let lastName, let lastColor, let baseScore, let density, let playerCount):
            renderBanner(text: "GAME OVER", color: .white)
            let finalScore = Int((Double(baseScore) * density.scoreMultiplier).rounded())
            let scoreLabel = SKLabelNode(text: playerCount > 1 ? "TEAM SCORE: \(finalScore)" : "SCORE: \(finalScore)")
            scoreLabel.fontName = "AvenirNext-Bold"
            scoreLabel.fontSize = 32
            scoreLabel.fontColor = SKColor(red: 245/255, green: 194/255, blue: 66/255, alpha: 1)
            scoreLabel.position = CGPoint(x: size.width / 2, y: size.height * 0.45)
            addChild(scoreLabel)

            if let mulDisplay = density.scoreMultiplierDisplay {
                let calc = SKLabelNode(text: "\(baseScore) \(mulDisplay) = \(finalScore)  ·  \(density.label) POWERUPS")
                calc.fontName = "AvenirNext-Regular"
                calc.fontSize = 18
                calc.fontColor = SKColor(white: 0.7, alpha: 1)
                calc.position = CGPoint(x: size.width / 2, y: size.height * 0.40)
                addChild(calc)
            }

            if playerCount > 1 {
                let footer = SKLabelNode(text: "\(lastName) SURVIVED LONGEST")
                footer.fontName = "AvenirNext-Regular"
                footer.fontSize = 22
                footer.fontColor = lastColor
                let footerY = density.scoreMultiplierDisplay == nil ? 0.39 : 0.35
                footer.position = CGPoint(x: size.width / 2, y: size.height * footerY)
                addChild(footer)
            }
        case .battleWinner(let c, let name):
            renderBanner(text: "\(name) WINS", color: c)
            let ship = Shapes.shipV(color: c, scale: 2.5)
            ship.position = CGPoint(x: size.width / 2, y: size.height * 0.42)
            ship.zRotation = .pi / 2
            addChild(ship)
        case .battleDraw:
            renderBanner(text: "DRAW", color: .white)
            let leftShip = Shapes.shipV(color: SKColor(white: 0.6, alpha: 1), scale: 2.0)
            leftShip.position = CGPoint(x: size.width / 2 - 28, y: size.height * 0.42)
            leftShip.zRotation = .pi / 4
            addChild(leftShip)
            let rightShip = Shapes.shipV(color: SKColor(white: 0.6, alpha: 1), scale: 2.0)
            rightShip.position = CGPoint(x: size.width / 2 + 28, y: size.height * 0.42)
            rightShip.zRotation = .pi - .pi / 4
            addChild(rightShip)
        }

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
