import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var navigation: FlutterMethodChannel?
  private var pendingLink: URL?

  override func application(_ application: NSApplication, open urls: [URL]) {
    guard let link = urls.last(where: { $0.scheme == "universe-builder" }) else { return }
    openApplicationLink(link)
  }

  func openApplicationLink(_ link: URL) {
    guard link.scheme == "universe-builder" else { return }
    pendingLink = link
    deliverPendingLink()
  }

  // Dart signals after its first frame so cold-start URL events cannot run
  // before the guarded Router has registered its navigation observer.
  func navigationReady(messenger: FlutterBinaryMessenger) {
    navigation = FlutterMethodChannel(name: "flutter/navigation", binaryMessenger: messenger,
      codec: FlutterJSONMethodCodec.sharedInstance())
    deliverPendingLink()
  }

  private func deliverPendingLink() {
    guard let channel = navigation, let link = pendingLink else { return }
    pendingLink = nil
    channel.invokeMethod("pushRouteInformation", arguments: ["location": link.absoluteString])
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
  }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
