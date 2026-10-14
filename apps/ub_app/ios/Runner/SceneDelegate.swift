import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if !connectionOptions.urlContexts.isEmpty {
      MobileSharedText.shared.receive(connectionOptions.urlContexts.map { $0.url })
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    MobileSharedText.shared.receive(URLContexts.map { $0.url })
  }
}
