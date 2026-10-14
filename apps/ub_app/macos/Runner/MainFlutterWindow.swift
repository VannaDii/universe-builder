import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  private var deviceChannel: FlutterMethodChannel?
  private var backupChannel: FlutterMethodChannel?
  override func awakeFromNib() {
    let project = FlutterDartProject()
    let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Universe Builder/Installation").path
    var arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
    if !arguments.contains(where: { $0 == "--fixture" || $0 == "--installation" || $0.hasPrefix("--installation=") || $0 == "--profile" || $0.hasPrefix("--profile=") }) {
      if let root = defaultRoot { arguments += ["--installation", root] }
    }
    project.dartEntrypointArguments = arguments
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let device = FlutterMethodChannel(name: "universe_builder/device", binaryMessenger: flutterViewController.engine.binaryMessenger)
    deviceChannel = device
    device.setMethodCallHandler { call, result in
      if call.method == "installationRoot" { result(defaultRoot) }
      else { result(FlutterMethodNotImplemented) }
    }
    let channel = FlutterMethodChannel(name: "universe_builder/backup_files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    backupChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let window = self, let arguments = call.arguments as? [String: String] else {
        result(FlutterError(code: "unavailable", message: "File dialog unavailable", details: nil)); return
      }
      if call.method == "saveBackup", let source = arguments["source"] {
        let panel = NSSavePanel()
        panel.title = "Save Universe Builder file"
        panel.nameFieldStringValue = URL(fileURLWithPath: source).lastPathComponent
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { response in
          guard response == .OK, let destination = panel.url else { result(nil); return }
          do {
            try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: destination)
            result(destination.path)
          } catch {
            result(FlutterError(code: "copy_failed", message: "Choose an unused filename.", details: nil))
          }
        }
      } else if call.method == "openBackup", let destination = arguments["destination"] {
        let panel = NSOpenPanel()
        panel.title = "Choose Universe Builder file"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
          guard response == .OK, let source = panel.url else { result(false); return }
          do {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
              result(FlutterError(code: "invalid_file", message: "Choose a regular backup file.", details: nil)); return
            }
            try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: destination))
            result(true)
          } catch {
            result(FlutterError(code: "copy_failed", message: "Could not read the selected backup.", details: nil))
          }
        }
      } else if call.method == "pickImage" || call.method == "pickSourceText" {
        let panel = NSOpenPanel()
        let text = call.method == "pickSourceText"
        panel.title = text ? "Choose source text" : "Choose appearance image"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = (text ? ["txt", "md"] : ["png", "jpg", "jpeg", "webp"]).compactMap { UTType(filenameExtension: $0) }
        panel.beginSheetModal(for: window) { response in
          guard response == .OK, let source = panel.url else { result(nil); return }
          result(source.path)
        }
      } else { result(FlutterMethodNotImplemented) }
    }


    super.awakeFromNib()
  }
}
