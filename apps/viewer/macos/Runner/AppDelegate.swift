import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

@main
class AppDelegate: FlutterAppDelegate {
  private var instanceChannel: FlutterMethodChannel?
  private var externalOpen: ExternalOpenBridge?
  private var pendingFiles: [String] = []
  private var dartReady = false

  func registerInstanceChannel(on controller: FlutterViewController) {
    externalOpen = ExternalOpenBridge(controller: controller)
    let channel = FlutterMethodChannel(name: "shenview/app_instance",
                                      binaryMessenger: controller.engine.binaryMessenger)
    instanceChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "ready":
        self.dartReady = true
        let files = self.pendingFiles
        self.pendingFiles.removeAll()
        result(files)
      case "newInstance":
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = call.arguments as? [String] ?? []
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "instance_launch_failed", message: error.localizedDescription, details: nil))
            } else { result(nil) }
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(_ sender: NSApplication, open urls: [URL]) {
    let files = urls.filter { $0.isFileURL }.map { $0.path }
    if files.isEmpty { super.application(sender, open: urls); return }
    receiveFiles(files)
  }

  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    receiveFiles(filenames)
    sender.reply(toOpenOrPrint: .success)
  }

  private func receiveFiles(_ filenames: [String]) {
    if dartReady {
      instanceChannel?.invokeMethod("openFiles", arguments: filenames)
    } else {
      pendingFiles.append(contentsOf: filenames)
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if dartReady { instanceChannel?.invokeMethod("openFiles", arguments: [String]()) }
    return true
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

private final class ExternalOpenBridge {
  private let channel: FlutterMethodChannel
  private weak var controller: FlutterViewController?
  private var choosing = false

  init(controller: FlutterViewController) {
    self.controller = controller
    channel = FlutterMethodChannel(name: "shenview/external_open",
                                  binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "Invalid file arguments", details: nil))
        return
      }
      switch call.method {
      case "applications":
        let path = args["path"] as? String
        let ext = (args["extension"] as? String ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        DispatchQueue.global(qos: .userInitiated).async {
          let workspace = NSWorkspace.shared
          let apps: [URL]
          if let path = path {
            let file = URL(fileURLWithPath: path)
            let scoped = file.startAccessingSecurityScopedResource()
            apps = workspace.urlsForApplications(toOpen: file)
            if scoped { file.stopAccessingSecurityScopedResource() }
          } else if let type = UTType(filenameExtension: ext) {
            apps = workspace.urlsForApplications(toOpen: type)
          } else { apps = [] }
          DispatchQueue.main.async {
            var seen = Set<String>()
            let candidates = apps.filter { app in
              !Self.isViewer(app) && seen.insert(app.standardizedFileURL.path).inserted
            }.prefix(8)
            result(candidates.map { app -> [String: Any] in
              var value: [String: Any] = [
                "id": app.path,
                "name": FileManager.default.displayName(atPath: app.path)
                  .replacingOccurrences(of: ".app", with: "", options: [.anchored, .backwards]),
              ]
              if let icon = Self.icon(app) { value["icon"] = FlutterStandardTypedData(bytes: icon) }
              return value
            })
          }
        }
      case "open", "choose":
        guard let path = args["path"] as? String, FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "file_missing", message: "The image no longer exists", details: nil))
          return
        }
        let file = URL(fileURLWithPath: path)
        if call.method == "open", let app = args["application"] as? String {
          self.open(file, with: URL(fileURLWithPath: app), result: result)
        } else if call.method == "choose" {
          self.choose(file, result: result)
        } else {
          result(FlutterError(code: "invalid_arguments", message: "No application selected", details: nil))
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func isViewer(_ app: URL) -> Bool {
    app.resolvingSymlinksInPath() == Bundle.main.bundleURL.resolvingSymlinksInPath() ||
      Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
  }

  private static func icon(_ app: URL) -> Data? {
    let image = NSImage(size: NSSize(width: 32, height: 32))
    image.lockFocus()
    NSWorkspace.shared.icon(forFile: app.path).draw(in: NSRect(x: 0, y: 0, width: 32, height: 32))
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
  }

  private func choose(_ file: URL, result: @escaping FlutterResult) {
    guard !choosing else { result(false); return }
    choosing = true
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.treatsFilePackagesAsDirectories = false
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard let self = self else { result(false); return }
      self.choosing = false
      guard response == .OK, let app = panel.url else { result(false); return }
      self.open(file, with: app, result: result)
    }
    if let window = controller?.view.window {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else { panel.begin(completionHandler: completion) }
  }

  private func open(_ file: URL, with app: URL, result: @escaping FlutterResult) {
    guard !Self.isViewer(app), Bundle(url: app) != nil else {
      result(FlutterError(code: "invalid_application", message: "Choose an application other than ShenView", details: nil))
      return
    }
    let scoped = file.startAccessingSecurityScopedResource()
    NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
      if scoped { file.stopAccessingSecurityScopedResource() }
      DispatchQueue.main.async {
        if let error = error {
          result(FlutterError(code: "open_failed", message: error.localizedDescription, details: nil))
        } else { result(true) }
      }
    }
  }
}
