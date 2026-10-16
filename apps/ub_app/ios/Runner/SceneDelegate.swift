import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    let sources = connectionOptions.urlContexts.map { $0.url }.filter { $0.scheme != "universe-builder" }
    if !sources.isEmpty { MobileSharedText.shared.receive(sources) }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let links = Set(URLContexts.filter { $0.url.scheme == "universe-builder" })
    if !links.isEmpty { super.scene(scene, openURLContexts: links) }
    let sources = URLContexts.map { $0.url }.filter { $0.scheme != "universe-builder" }
    if !sources.isEmpty { MobileSharedText.shared.receive(sources) }
  }
}
