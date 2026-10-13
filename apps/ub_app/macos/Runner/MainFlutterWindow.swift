import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let project = FlutterDartProject()
    var arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
    if !arguments.contains(where: { $0 == "--installation" || $0.hasPrefix("--installation=") || $0 == "--profile" || $0.hasPrefix("--profile=") }) {
      if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        arguments += ["--installation", support.appendingPathComponent("Universe Builder/Installation").path]
      }
    }
    project.dartEntrypointArguments = arguments
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
