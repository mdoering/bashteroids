import SpriteKit
import GameController

final class PosterScene: SKScene {
    private let manager = ControllerManager.shared
    private var transitioning = false
    private var prevButtonState: [ObjectIdentifier: Bool] = [:]

    override func didMove(to view: SKView) {
        backgroundColor = .black

        // Letterbox: fill height, preserve portrait aspect ratio.
        let texture = SKTexture(imageNamed: "Splash")
        let aspect = texture.size().width / max(texture.size().height, 1)
        let posterHeight = size.height
        let posterWidth = posterHeight * aspect
        let sprite = SKSpriteNode(texture: texture)
        sprite.size = CGSize(width: posterWidth, height: posterHeight)
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(sprite)

        let prompt = SKLabelNode(text: "PRESS ANY KEY")
        prompt.fontName = "AvenirNext-Regular"
        prompt.fontSize = 20
        prompt.fontColor = SKColor(white: 0.55, alpha: 1)
        prompt.position = CGPoint(x: size.width / 2, y: size.height * 0.06)
        prompt.alpha = 0
        addChild(prompt)
        prompt.run(.sequence([
            .wait(forDuration: 1.0),
            .fadeAlpha(to: 1.0, duration: 0.6)
        ]))

        KeyboardManager.shared.onKeyDown = { [weak self] _ in
            self?.advance()
        }
    }

    override func willMove(from view: SKView) {
        KeyboardManager.shared.onKeyDown = nil
    }

    override func update(_ currentTime: TimeInterval) {
        guard !transitioning else { return }
        for c in manager.connectedControllers {
            let id = ObjectIdentifier(c)
            let pressed = anyButtonPressed(c)
            let wasPressed = prevButtonState[id] ?? false
            if pressed && !wasPressed {
                advance()
                break
            }
            prevButtonState[id] = pressed
        }
    }

    private func anyButtonPressed(_ c: GCController) -> Bool {
        if let gp = c.extendedGamepad {
            return gp.buttonA.isPressed || gp.buttonB.isPressed
                || gp.buttonX.isPressed || gp.buttonY.isPressed
                || gp.buttonMenu.isPressed
                || (gp.buttonOptions?.isPressed ?? false)
                || gp.leftShoulder.isPressed || gp.rightShoulder.isPressed
                || gp.leftTrigger.isPressed || gp.rightTrigger.isPressed
                || abs(gp.dpad.xAxis.value) > 0.5
                || abs(gp.dpad.yAxis.value) > 0.5
        }
        if let mg = c.microGamepad {
            return mg.buttonA.isPressed
                || mg.buttonX.isPressed
                || mg.buttonMenu.isPressed
                || abs(mg.dpad.xAxis.value) > 0.5
                || abs(mg.dpad.yAxis.value) > 0.5
        }
        return false
    }

    private func advance() {
        guard !transitioning else { return }
        transitioning = true
        let title = TitleScene(size: size)
        title.scaleMode = scaleMode
        view?.presentScene(title, transition: .fade(withDuration: 0.4))
    }
}
