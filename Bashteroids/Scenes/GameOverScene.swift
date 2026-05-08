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

    /// First key/button in a non-NORMAL survival run plays the score-reveal
    /// animation; subsequent presses dismiss to title. NORMAL density and
    /// the BATTLE results skip the reveal phase and go straight to dismiss.
    private enum RevealState { case awaitingReveal, awaitingDismiss }
    private var revealState: RevealState = .awaitingDismiss

    private var scoreLabel: SKLabelNode?
    private var densityLabel: SKLabelNode?
    private var revealedBaseScore: Int = 0
    private var revealedFinalScore: Int = 0
    private var revealedPlayerCountIsTeam: Bool = false

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
            let isTeam = playerCount > 1

            // Phase-1 display: original score for non-NORMAL densities,
            // final score for NORMAL (where they're equal anyway).
            let initialScore = density == .normal ? finalScore : baseScore
            let scoreL = SKLabelNode(text: scoreText(initialScore, isTeam: isTeam))
            scoreL.fontName = "AvenirNext-Bold"
            scoreL.fontSize = 32
            scoreL.fontColor = SKColor(red: 245/255, green: 194/255, blue: 66/255, alpha: 1)
            scoreL.position = CGPoint(x: size.width / 2, y: size.height * 0.45)
            addChild(scoreL)
            self.scoreLabel = scoreL

            if density != .normal {
                // Highscore-leaderboard cyan, matching the title's
                // otherEntryColor — signals "this affects your placement".
                let highscoreBlue = SKColor(red: 98/255, green: 212/255, blue: 214/255, alpha: 1)
                let dl = SKLabelNode(text: "\(density.label) POWERUPS")
                dl.fontName = "AvenirNext-Bold"
                dl.fontSize = 20
                dl.fontColor = highscoreBlue
                dl.position = CGPoint(x: size.width / 2, y: size.height * 0.40)
                addChild(dl)
                self.densityLabel = dl

                self.revealState = .awaitingReveal
                self.revealedBaseScore = baseScore
                self.revealedFinalScore = finalScore
                self.revealedPlayerCountIsTeam = isTeam
            }

            if isTeam {
                let footer = SKLabelNode(text: "\(lastName) SURVIVED LONGEST")
                footer.fontName = "AvenirNext-Regular"
                footer.fontSize = 22
                footer.fontColor = lastColor
                let footerY: CGFloat = density == .normal ? 0.39 : 0.35
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
            handleDismissPress()
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
                handleDismissPress()
                break
            }
            prevButtonState[id] = (menu, a)
        }
    }

    private func handleDismissPress() {
        switch revealState {
        case .awaitingReveal:
            playRevealAnimation()
            revealState = .awaitingDismiss
        case .awaitingDismiss:
            returnToTitle()
        }
    }

    /// Counts the score label up (or down) from base to final over ~0.8 s
    /// with an ease-out curve, finishes with a brief scale pulse, and fades
    /// the density label out underneath.
    private func playRevealAnimation() {
        guard let scoreL = scoreLabel else { return }
        let base = revealedBaseScore
        let final = revealedFinalScore
        let isTeam = revealedPlayerCountIsTeam

        let duration: TimeInterval = 0.8
        let count = SKAction.customAction(withDuration: duration) { [weak self] node, elapsed in
            guard let self else { return }
            let progress = max(0, min(1, Double(elapsed) / duration))
            let eased = 1 - pow(1 - progress, 3)
            let value = Int((Double(base) + (Double(final) - Double(base)) * eased).rounded())
            (node as? SKLabelNode)?.text = self.scoreText(value, isTeam: isTeam)
        }
        let pulse = SKAction.sequence([
            .scale(to: 1.18, duration: 0.10),
            .scale(to: 1.0,  duration: 0.20)
        ])
        scoreL.run(.sequence([count, pulse]))
        densityLabel?.run(.fadeOut(withDuration: 0.4))
    }

    private func scoreText(_ value: Int, isTeam: Bool) -> String {
        (isTeam ? "TEAM SCORE: " : "SCORE: ") + "\(value)"
    }

    private func returnToTitle() {
        guard !transitioning else { return }
        transitioning = true
        let title = TitleScene(size: size)
        title.scaleMode = scaleMode
        view?.presentScene(title, transition: .fade(withDuration: 0.4))
    }
}
