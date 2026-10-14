import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var imagePicker: MobileImagePicker?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    imagePicker = MobileImagePicker(messenger: engineBridge.applicationRegistrar.messenger())
    let channel = FlutterMethodChannel(name: "universe_builder/device",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "installationRoot" else {
        result(FlutterMethodNotImplemented); return
      }
      do {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
          in: .userDomainMask, appropriateFor: nil, create: true)
        var root = support.appendingPathComponent("Universe Builder/Installation", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        result(root.path)
      } catch {
        result(FlutterError(code: "unavailable", message: "Local device storage unavailable.", details: nil))
      }
    }
  }
}

private class MobileImagePicker: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private var pending: FlutterResult?
  private var copying = false
  private var retained = Set<String>()
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "universe_builder/backup_files", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Image picker unavailable.", details: nil)); return
      }
      if call.method == "pickImage" {
        self.open(result)
      } else if call.method == "releasePickedImage" {
        if let arguments = call.arguments as? [String: String], let path = arguments["source"],
            self.retained.remove(path) != nil {
          try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
        }
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
  }

  private func open(_ result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "An image picker is already open.", details: nil)); return
    }
    guard var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "unavailable", message: "Image picker unavailable.", details: nil)); return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.png, .jpeg, .webP], asCopy: false)
    picker.allowsMultipleSelection = false
    picker.delegate = self
    presenter.present(picker, animated: true)
    picker.presentationController?.delegate = self
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { if !copying { finish(nil) } }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { finish(nil); return }
    copying = true
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let path = try Self.copySelectedImage(url)
        DispatchQueue.main.async {
          if self.pending != nil {
            self.retained.insert(path)
            self.finish(path)
          } else {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
          }
        }
      } catch {
        DispatchQueue.main.async {
          self.finish(FlutterError(code: "invalid_file", message: "Choose a readable PNG, JPEG or WebP image up to 10 MiB.", details: nil))
        }
      }
    }
  }

  private func finish(_ value: Any?) {
    let result = pending
    pending = nil
    copying = false
    result?(value)
  }

  nonisolated private static func copySelectedImage(_ source: URL) throws -> String {
    let granted = source.startAccessingSecurityScopedResource()
    defer { if granted { source.stopAccessingSecurityScopedResource() } }
    let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
    let name = source.lastPathComponent
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw CocoaError(.fileReadInvalidFileName) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ub-picked-images/" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let destination = directory.appendingPathComponent(name)
    do {
      guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
      let input = try FileHandle(forReadingFrom: source)
      defer { try? input.close() }
      let output = try FileHandle(forWritingTo: destination)
      defer { try? output.close() }
      var total = 0
      while let bytes = try input.read(upToCount: 65536), !bytes.isEmpty {
        total += bytes.count
        guard total <= 10 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        try output.write(contentsOf: bytes)
      }
      guard total > 0 else { throw CocoaError(.fileReadCorruptFile) }
      return destination.path
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }
}
