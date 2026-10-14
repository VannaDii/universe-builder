import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var filePicker: MobileFilePicker?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    filePicker = MobileFilePicker(messenger: engineBridge.applicationRegistrar.messenger())
    MobileSharedText.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
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

private class MobileFilePicker: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private var pending: FlutterResult?
  private var selection: UUID?
  private var copying = false
  private var limit = 10 * 1024 * 1024
  private var pickingText = false
  private var restoringTo: String?
  private var exporting = false
  private var retained = Set<String>()
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "universe_builder/backup_files", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "File picker unavailable.", details: nil)); return
      }
      if call.method == "pickImage" || call.method == "pickSourceText" {
        self.open(result, text: call.method == "pickSourceText")
      } else if call.method == "saveBackup" || call.method == "openBackup" {
        guard let arguments = call.arguments as? [String: String],
          let path = arguments[call.method == "saveBackup" ? "source" : "destination"] else {
          result(FlutterError(code: "unavailable", message: "Backup path unavailable.", details: nil)); return
        }
        self.open(result, text: false, restore: call.method == "openBackup" ? path : nil,
          export: call.method == "saveBackup" ? path : nil)
      } else if call.method == "releasePickedFile" {
        if let arguments = call.arguments as? [String: String], let path = arguments["source"],
            self.retained.remove(path) != nil {
          try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
        } else if let arguments = call.arguments as? [String: String], let path = arguments["source"] {
          MobileSharedText.shared.release(path)
        }
        result(nil)
      } else { result(FlutterMethodNotImplemented) }
    }
  }

  private func open(_ result: @escaping FlutterResult, text: Bool, restore: String? = nil, export: String? = nil) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "A file picker is already open.", details: nil)); return
    }
    guard var presenter = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "unavailable", message: "File picker unavailable.", details: nil)); return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    if let source = export {
      do {
        let values = try URL(fileURLWithPath: source).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
          let size = values.fileSize, size > 0, size <= 8 * 1024 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
      } catch {
        result(FlutterError(code: "unavailable", message: "Backup file unavailable.", details: nil)); return
      }
    }
    pending = result
    selection = UUID()
    restoringTo = restore
    exporting = export != nil
    pickingText = text
    limit = restore != nil ? 8 * 1024 * 1024 * 1024 : text ? 1024 * 1024 : 10 * 1024 * 1024
    let picker: UIDocumentPickerViewController
    if let source = export {
      picker = UIDocumentPickerViewController(forExporting: [URL(fileURLWithPath: source)], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: restore != nil ? [.data] : text ? [.plainText, UTType(filenameExtension: "md") ?? .plainText] : [.png, .jpeg, .webP], asCopy: false)
    }
    picker.allowsMultipleSelection = false
    picker.delegate = self
    presenter.present(picker, animated: true)
    picker.presentationController?.delegate = self
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(restoringTo == nil ? nil : false) }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { if !copying { finish(restoringTo == nil ? nil : false) } }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { finish(nil); return }
    if exporting { finish(url.lastPathComponent); return }
    copying = true
    let restore = self.restoringTo
    let selected = self.selection
    let limit = self.limit, text = self.pickingText
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let path = try Self.copySelectedFile(url, limit: limit, allowEmpty: text, destinationPath: restore)
        DispatchQueue.main.async {
          if self.selection == selected && self.pending != nil {
            if restore == nil { self.retained.insert(path) }
            if restore == nil { self.finish(path) } else { self.finish(true) }
          } else {
            try? FileManager.default.removeItem(at: restore == nil ? URL(fileURLWithPath: path).deletingLastPathComponent() : URL(fileURLWithPath: path))
          }
        }
      } catch {
        DispatchQueue.main.async {
          guard self.selection == selected else { return }
          self.finish(FlutterError(code: "invalid_file", message: restore != nil ? "Could not copy this backup file." : text ? "Choose a readable UTF-8 text file up to 1 MiB." : "Choose a readable PNG, JPEG or WebP image up to 10 MiB.", details: nil))
        }
      }
    }
  }

  private func finish(_ value: Any?) {
    let result = pending
    pending = nil
    selection = nil
    copying = false
    restoringTo = nil
    exporting = false
    result?(value)
  }

  nonisolated fileprivate static func copySelectedFile(_ source: URL, limit: Int, allowEmpty: Bool, destinationPath: String? = nil, requireExternalAccess: Bool = false) throws -> String {
    let granted = source.startAccessingSecurityScopedResource()
    defer { if granted { source.stopAccessingSecurityScopedResource() } }
    let inbox = NSHomeDirectory() + "/Documents/Inbox/"
    if requireExternalAccess && !granted && !source.standardizedFileURL.path.hasPrefix(inbox) {
      throw CocoaError(.fileReadNoPermission)
    }
    let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadUnsupportedScheme) }
    let name = source.lastPathComponent
    guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw CocoaError(.fileReadInvalidFileName) }
    let directory = destinationPath == nil ? FileManager.default.temporaryDirectory.appendingPathComponent("ub-picked-files/" + UUID().uuidString, isDirectory: true) : URL(fileURLWithPath: destinationPath!).deletingLastPathComponent()
    if destinationPath == nil {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    let destination = destinationPath == nil ? directory.appendingPathComponent(name) : URL(fileURLWithPath: destinationPath!)
    var created = false
    do {
      try Data().write(to: destination, options: .withoutOverwriting)
      created = true
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
      let input = try FileHandle(forReadingFrom: source)
      defer { try? input.close() }
      let output = try FileHandle(forWritingTo: destination)
      defer { try? output.close() }
      var total = 0
      while let bytes = try input.read(upToCount: 65536), !bytes.isEmpty {
        total += bytes.count
        guard total <= limit else { throw CocoaError(.fileReadTooLarge) }
        try output.write(contentsOf: bytes)
      }
      guard allowEmpty || total > 0 else { throw CocoaError(.fileReadCorruptFile) }
      return destination.path
    } catch {
      if destinationPath == nil { try? FileManager.default.removeItem(at: directory) }
      else if created { try? FileManager.default.removeItem(at: destination) }
      throw error
    }
  }
}


/// OS document delivery is private staging, never a universe command.
/// A completed directory move makes the single waiting file discoverable after
/// a cold launch. Partial copies are never exposed as pending source input.
final class MobileSharedText {
  static let shared = MobileSharedText()
  private var channel: FlutterMethodChannel?
  private var copying = false
  private var lastError: String?
  private var slot: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ub-shared-source", isDirectory: true)
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "universe_builder/shared_sources", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "status":
        let error = self.lastError
        self.lastError = nil
        result(["pending": self.pendingPath() != nil, "error": error.map { $0 as Any } ?? NSNull()])
      case "pendingPath": result(self.pendingPath())
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func changed() { channel?.invokeMethod("changed", arguments: nil) }

  private func pendingPath() -> String? {
    guard let files = try? FileManager.default.contentsOfDirectory(at: slot,
      includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), files.count == 1,
      let file = files.first,
      let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
      values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size <= 1024 * 1024 else { return nil }
    return file.path
  }

  func receive(_ urls: [URL]) {
    guard urls.count == 1, let source = urls.first, source.isFileURL,
      ["txt", "md"].contains(source.pathExtension.lowercased()) else {
      lastError = "Open one .txt or .md file up to 1 MiB in Universe Builder."
      changed(); return
    }
    guard !copying && !FileManager.default.fileExists(atPath: slot.path) else {
      lastError = "A shared text file is already waiting. Review it in Import source before opening another."
      changed(); return
    }
    copying = true
    lastError = nil
    let destination = slot
    DispatchQueue.global(qos: .userInitiated).async {
      var incoming: URL?
      do {
        let path = try MobileFilePicker.copySelectedFile(source, limit: 1024 * 1024,
          allowEmpty: true, requireExternalAccess: true)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        incoming = directory
        try FileManager.default.moveItem(at: directory, to: destination)
        DispatchQueue.main.async { self.copying = false; self.changed() }
      } catch {
        if let directory = incoming { try? FileManager.default.removeItem(at: directory) }
        DispatchQueue.main.async {
          self.copying = false
          self.lastError = "Could not receive this text file. Open a readable .txt or .md file up to 1 MiB."
          self.changed()
        }
      }
    }
  }

  func release(_ path: String) {
    guard pendingPath() == path else { return }
    do {
      try FileManager.default.removeItem(at: slot)
      lastError = nil
      changed()
    } catch { /* Keep the waiting file available if cache cleanup fails. */ }
  }
}
