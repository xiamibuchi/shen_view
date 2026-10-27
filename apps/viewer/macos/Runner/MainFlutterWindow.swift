import Cocoa
import FlutterMacOS
import ImageIO
import Metal
import CoreImage
import QuartzCore
import Darwin
import AVFoundation

// State and callbacks stay on the platform thread. Only bounded pixel work
// runs on the two lanes; the Dart scheduler owns global admission and memory.
private final class NativeImageDecodeQueue {
  typealias Decode = (String, [String: Any], Bool, () -> Bool) -> [String: Any]?
  private final class Task {
    let id: Int
    let path: String
    let arguments: [String: Any]
    let metadata: Bool
    let sequence: Int
    let result: FlutterResult
    var priority: Int
    var distance: Double
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
      lock.lock()
      defer { lock.unlock() }
      return cancelled
    }
    func cancel() {
      lock.lock()
      cancelled = true
      lock.unlock()
    }
    init(id: Int, path: String, arguments: [String: Any], metadata: Bool,
         sequence: Int, result: @escaping FlutterResult) {
      self.id = id
      self.path = path
      self.arguments = arguments
      self.metadata = metadata
      self.sequence = sequence
      self.result = result
      priority = min(7, max(0, arguments["priority"] as? Int ?? (metadata ? 5 : 0)))
      let raw = (arguments["distance"] as? NSNumber)?.doubleValue ?? 0
      distance = raw.isFinite ? max(0, raw) : Double.greatestFiniteMagnitude
    }
  }
  private let lanes = [
    DispatchQueue(label: "shenview.decoder.foreground", qos: .userInitiated),
    DispatchQueue(label: "shenview.decoder.auxiliary", qos: .userInitiated),
  ]
  private var busy = [false, false]
  private var pending: [Task] = []
  private var tasks: [Int: Task] = [:]
  private var sequence = 0
  private var fallbackId = 0
  private var stopped = false
  private let decode: Decode
  init(decode: @escaping Decode) { self.decode = decode }

  func stop() {
    stopped = true
    for task in tasks.values { task.cancel() }
    pending.removeAll()
    // Running closures retain their task until the codec actually returns.
    // A destroyed window must not receive a late platform-channel reply.
    tasks.removeAll()
  }

  func enqueue(path: String, arguments: [String: Any], metadata: Bool,
               result: @escaping FlutterResult) {
    fallbackId -= 1
    let task = Task(id: arguments["requestId"] as? Int ?? fallbackId, path: path,
                    arguments: arguments, metadata: metadata, sequence: sequence, result: result)
    sequence += 1
    tasks[task.id] = task
    pending.append(task)
    drain()
  }

  func cancel(_ id: Int) {
    guard let task = tasks[id] else { return }
    task.cancel()
    if let index = pending.firstIndex(where: { $0 === task }) {
      pending.remove(at: index)
      tasks.removeValue(forKey: id)
      task.result(FlutterError(code: "cancelled", message: "解码已取消", details: nil))
    }
  }

  func updatePriority(_ id: Int, priority: Int, distance: Double) {
    guard let task = tasks[id] else { return }
    task.priority = min(7, max(0, priority))
    task.distance = distance.isFinite ? max(0, distance) : Double.greatestFiniteMagnitude
    drain()
  }

  private func drain() {
    if stopped { return }
    pending.sort {
      if $0.priority != $1.priority { return $0.priority < $1.priority }
      if $0.distance != $1.distance { return $0.distance < $1.distance }
      return $0.sequence < $1.sequence
    }
    for lane in 0..<2 where !busy[lane] {
      guard let index = pending.firstIndex(where: { lane != 0 || $0.priority <= 1 }) else { continue }
      let task = pending.remove(at: index)
      busy[lane] = true
      lanes[lane].async {
        let decoded: [String: Any]? = autoreleasepool {
          if task.isCancelled { return nil }
          return self.decode(task.path, task.arguments, task.metadata, { task.isCancelled })
        }
        DispatchQueue.main.async {
          self.busy[lane] = false
          self.tasks.removeValue(forKey: task.id)
          if self.stopped { return }
          if task.isCancelled {
            task.result(FlutterError(code: "cancelled", message: "解码已取消", details: nil))
          } else {
            task.result(decoded)
          }
          self.drain()
        }
      }
    }
  }
}

private final class NativeMediaAudio {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
  private var owner = -1
  private var generation = 0
  private var queued = 0
  private let channel: FlutterMethodChannel
  init(controller: FlutterViewController) {
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    channel = FlutterMethodChannel(name: "shenview/media_audio", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "open":
        guard let id = call.arguments as? Int else { result(FlutterError(code: "arguments", message: "Invalid audio owner", details: nil)); return }
        self.stop()
        do {
          try self.engine.start()
          self.owner = id
          self.player.play()
          result(nil)
        } catch { result(FlutterError(code: "audio_device", message: error.localizedDescription, details: nil)) }
      case "stop":
        if call.arguments as? Int == self.owner { self.stop() }
        result(nil)
      case "write":
        guard let args = call.arguments as? [String: Any], let id = args["owner"] as? Int,
              id == self.owner, let data = args["bytes"] as? FlutterStandardTypedData,
              !data.data.isEmpty, data.data.count <= 8192, data.data.count % 4 == 0 else {
          result(FlutterError(code: "audio_session", message: "Invalid PCM session", details: nil)); return
        }
        if self.queued + data.data.count > 48000 { result(false); return }
        let frames = AVAudioFrameCount(data.data.count / 4)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { result(false); return }
        buffer.frameLength = frames
        data.data.withUnsafeBytes { raw in
          for i in 0..<Int(frames) {
            for c in 0..<2 {
              let p = i * 4 + c * 2
              let value = UInt16(raw[p]) | (UInt16(raw[p + 1]) << 8)
              channels[c][i] = Float(Int16(bitPattern: value)) / 32768
            }
          }
        }
        self.queued += data.data.count
        let generation = self.generation
        self.player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
          DispatchQueue.main.async {
            guard let self = self, self.generation == generation else { return }
            self.queued -= data.data.count
          }
        }
        result(true)
      case "position":
        let time = self.player.lastRenderTime.flatMap { self.player.playerTime(forNodeTime: $0) }
        result(["samples": time?.sampleTime ?? 0, "queuedBytes": self.queued])
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func stop() {
    generation += 1
    player.stop()
    engine.stop()
    queued = 0
    owner = -1
  }
  deinit { stop() }
}

class MainFlutterWindow: NSWindow {
  private var mediaAudio: NativeMediaAudio?
  private let imageDecodeQueue = NativeImageDecodeQueue { path, arguments, metadata, cancelled in
    try? MainFlutterWindow.decode(path: path, arguments: arguments, metadata: metadata, cancelled: cancelled)
  }
  private var hdrDisplay: NativeHdrDisplay?
  private var systemResourceChannel: FlutterMethodChannel?
  private var materialEffectsChannel: FlutterMethodChannel?

  deinit { imageDecodeQueue.stop() }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    RegisterGeneratedPlugins(registry: flutterViewController)
    mediaAudio = NativeMediaAudio(controller: flutterViewController)
    (NSApplication.shared.delegate as? AppDelegate)?.registerInstanceChannel(on: flutterViewController)
    registerNativeImageDecoder(on: flutterViewController)
    registerSystemResources(on: flutterViewController)
    registerMaterialEffects(on: flutterViewController)
    hdrDisplay = NativeHdrDisplay(controller: flutterViewController)
    super.awakeFromNib()
  }

  private func registerMaterialEffects(on controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "shenview/material_effects",
                                      binaryMessenger: controller.engine.binaryMessenger)
    materialEffectsChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "enabled" else { result(FlutterMethodNotImplemented); return }
      var saving = false
      if #available(macOS 12.0, *) { saving = ProcessInfo.processInfo.isLowPowerModeEnabled }
      result(!NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency &&
             !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast && !saving)
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(materialEffectsChanged),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    if #available(macOS 12.0, *) {
      NotificationCenter.default.addObserver(
        self, selector: #selector(materialEffectsChanged),
        name: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }
  }

  @objc private func materialEffectsChanged(_ notification: Notification) {
    materialEffectsChannel?.invokeMethod("changed", arguments: nil)
  }

  private func registerNativeImageDecoder(on controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "shenview/native_decoder", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, let arguments = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_arguments", message: "图片路径无效", details: nil))
        return
      }
      let requestId = arguments["requestId"] as? Int ?? 0
      if call.method == "cancel" {
        self.imageDecodeQueue.cancel(requestId)
        result(nil)
        return
      }
      if call.method == "updatePriority" {
        self.imageDecodeQueue.updatePriority(requestId, priority: arguments["priority"] as? Int ?? 0,
                                            distance: (arguments["distance"] as? NSNumber)?.doubleValue ?? 0)
        result(nil)
        return
      }
      guard let path = arguments["path"] as? String,
            call.method == "decode" || call.method == "metadata" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.imageDecodeQueue.enqueue(path: path, arguments: arguments,
                                    metadata: call.method == "metadata", result: result)
    }
  }

  private func registerSystemResources(on controller: FlutterViewController) {
    let channel = FlutterMethodChannel(name: "shenview/system_resources",
                                      binaryMessenger: controller.engine.binaryMessenger)
    systemResourceChannel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "read" else { result(FlutterMethodNotImplemented); return }
      let diskPath = (call.arguments as? [String: Any])?["diskPath"] as? String
      DispatchQueue.global(qos: .utility).async {
        var response: [String: Any] = [:]
        var physical: UInt64 = 0
        var physicalSize = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &physical, &physicalSize, nil, 0) == 0 {
          response["physicalMemoryBytes"] = NSNumber(value: physical)
        }
        let host = mach_host_self()
        var pageSize: vm_size_t = 0
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
          pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(host, HOST_VM_INFO64, $0, &count)
          }
        }
        if status == KERN_SUCCESS && host_page_size(host, &pageSize) == KERN_SUCCESS {
          // Count reclaimable inactive pages without adding purgeable pages
          // again: purgeable pages can already belong to the inactive queue.
          let available = (UInt64(statistics.free_count) + UInt64(statistics.inactive_count)) * UInt64(pageSize)
          response["availableMemoryBytes"] = NSNumber(value: available)
        }
        mach_port_deallocate(mach_task_self_, host)
        if let diskPath = diskPath, !diskPath.isEmpty {
          var directory = URL(fileURLWithPath: diskPath).standardizedFileURL
          var isDirectory: ObjCBool = false
          while !FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
          }
          if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: directory.path) {
            response["availableDiskBytes"] = attributes[.systemFreeSize]
            response["diskCapacityBytes"] = attributes[.systemSize]
          }
        }
        DispatchQueue.main.async { result(response) }
      }
    }
  }

  fileprivate static func decode(path: String, arguments: [String: Any], metadata: Bool,
                                 cancelled: () -> Bool) throws -> [String: Any] {
    if cancelled() { return [:] }
    let preserveHdr = arguments["preserveHdr"] as? Bool ?? false
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int,
          let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int,
          sourceWidth > 0, sourceHeight > 0 else {
      throw NSError(domain: "ShenViewNativeDecoder", code: 1)
    }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    if cancelled() { return [:] }
    if metadata {
      var response: [String: Any] = [
        "width": sourceWidth,
        "height": sourceHeight,
        "orientation": orientation,
      ]
      if let depth = properties[kCGImagePropertyDepth] as? Int {
        response["bitDepth"] = depth
      }
      if let profile = properties[kCGImagePropertyProfileName] as? String {
        response["colorSpace"] = profile
      } else if let colorModel = properties[kCGImagePropertyColorModel] as? String {
        response["colorSpace"] = colorModel
      }
      return response
    }
    let orientedWidth = orientation >= 5 && orientation <= 8 ? sourceHeight : sourceWidth
    let orientedHeight = orientation >= 5 && orientation <= 8 ? sourceWidth : sourceHeight
    let region = arguments["region"] as? [String: Int]
    let crop = CGRect(x: region?["left"] ?? 0, y: region?["top"] ?? 0, width: region?["width"] ?? orientedWidth, height: region?["height"] ?? orientedHeight)
    guard crop.width > 0, crop.height > 0,
          CGRect(x: 0, y: 0, width: orientedWidth, height: orientedHeight).contains(crop) else {
      throw NSError(domain: "ShenViewNativeDecoder", code: 2)
    }
    let pixelBudget = preserveHdr ? 4 * 1024 * 1024 : 16 * 1024 * 1024
    var ratio = min(1, sqrt(Double(pixelBudget) / (crop.width * crop.height)))
    if let width = arguments["targetWidth"] as? Int, width > 0 { ratio = min(ratio, Double(width) / crop.width) }
    if let height = arguments["targetHeight"] as? Int, height > 0 { ratio = min(ratio, Double(height) / crop.height) }
    let decodeRatio = min(ratio, sqrt(Double(pixelBudget) / Double(orientedWidth * orientedHeight)))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, Int(Double(max(orientedWidth, orientedHeight)) * decodeRatio)),
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      throw NSError(domain: "ShenViewNativeDecoder", code: 3)
    }
    if cancelled() { return [:] }
    let image: CGImage
    if region != nil {
      let scaleX = Double(thumbnail.width) / Double(orientedWidth)
      let scaleY = Double(thumbnail.height) / Double(orientedHeight)
      guard let cropped = thumbnail.cropping(to: CGRect(x: crop.minX * scaleX, y: crop.minY * scaleY, width: crop.width * scaleX, height: crop.height * scaleY)) else {
        throw NSError(domain: "ShenViewNativeDecoder", code: 4)
      }
      image = cropped
    } else {
      image = thumbnail
    }
    let width = image.width
    let height = image.height
    let bytesPerPixel = preserveHdr ? 16 : 4
    if cancelled() { return [:] }
    var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
    let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
      let colorSpaceName = preserveHdr ? CGColorSpace.extendedLinearSRGB : CGColorSpace.sRGB
      guard let colorSpace = CGColorSpace(name: colorSpaceName) else { return false }
      let bitmapInfo = preserveHdr
        ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue | CGBitmapInfo.floatComponents.rawValue
        : CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: preserveHdr ? 32 : 8, bytesPerRow: width * bytesPerPixel, space: colorSpace, bitmapInfo: bitmapInfo) else { return false }
      if cancelled() { return false }
      context.translateBy(x: 0, y: CGFloat(height))
      context.scaleBy(x: 1, y: -1)
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard rendered else { throw NSError(domain: "ShenViewNativeDecoder", code: 5) }
    if cancelled() { return [:] }
    return [
      "width": width,
      "height": height,
      "pixels": FlutterStandardTypedData(bytes: Data(pixels)),
      "pixelFormat": preserveHdr ? "rgbaFloat32" : "rgba8888",
    ]
  }
}

// A native EDR surface, deliberately outside Flutter's SDR compositor.
// It is transparent to hit-testing; Flutter retains all input ownership.
private final class NativeHdrView: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func makeBackingLayer() -> CALayer { CAMetalLayer() }
}

private final class NativeHdrDisplay {
  private weak var controller: FlutterViewController?
  private let channel: FlutterMethodChannel
  private let device: MTLDevice?
  private let queue: MTLCommandQueue?
  private let context: CIContext?
  private let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
  private var frames: [Int: Frame] = [:]
  private var output = "SDR"
  private var screenObservers: [NSObjectProtocol] = []

  private struct Frame {
    let image: CIImage
    let pixels: Int
    let view: NativeHdrView
  }

  init(controller: FlutterViewController) {
    self.controller = controller
    let metalDevice = MTLCreateSystemDefaultDevice()
    device = metalDevice
    queue = metalDevice?.makeCommandQueue()
    context = metalDevice.map { CIContext(mtlDevice: $0, options: [
      .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
      .workingFormat: CIFormat.RGBAh, .cacheIntermediates: false,
    ]) }
    channel = FlutterMethodChannel(name: "shenview/hdr_display",
                                   binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      let args = call.arguments as? [String: Any] ?? [:]
      let id = args["id"] as? Int ?? 0
      switch call.method {
      case "capabilities": result(self.capabilities())
      case "diagnostics": result([
        "activeFrames": self.frames.count,
        "visibleFrames": self.frames.values.filter { !$0.view.isHidden }.count,
        "surfaceFormat": "RGBA16Float", "colorSpace": "extendedLinearSRGB",
      ])
      case "upload": result(self.upload(id: id, args: args))
      case "geometry": result(self.geometry(id: id, args: args))
      case "remove": self.remove(id); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    screenObservers.append(NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main
    ) { [weak self] notification in
      guard let self = self, let window = notification.object as? NSWindow,
            let target = self.controller?.view.window, window === target else { return }
      self.invalidate()
    })
    screenObservers.append(NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.invalidate() })
  }

  deinit {
    screenObservers.forEach { NotificationCenter.default.removeObserver($0) }
    channel.setMethodCallHandler(nil)
    frames.values.forEach { $0.view.removeFromSuperview() }
  }

  private func invalidate() {
    let hadFrames = !frames.isEmpty
    for id in Array(frames.keys) { remove(id) }
    output = "SDR"
    if hadFrames { channel.invokeMethod("invalidated", arguments: "display-changed") }
  }

  private func capabilities() -> [String: Any] {
    let screen = controller?.view.window?.screen
    let headroom = screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1
    let available = device != nil && queue != nil && context != nil && headroom > 1
    let nextOutput = available
      ? "EDR-\(screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? 0)" : "SDR"
    if nextOutput != output {
      for id in Array(frames.keys) { remove(id) }
      output = nextOutput
    }
    return ["available": available, "headroom": headroom, "output": output,
            "reason": available ? "Metal-EDR" : "edr-unavailable",
            "colorManagement": "ColorSync",
            "displayProfile": screen?.colorSpace?.localizedName ?? "ColorSync display profile"]
  }

  private func remove(_ id: Int) {
    frames.removeValue(forKey: id)?.view.removeFromSuperview()
  }

  private func upload(id: Int, args: [String: Any]) -> Bool {
    guard id > 0, capabilities()["available"] as? Bool == true,
          let parent = controller?.view, let device = device,
          let width = args["width"] as? Int, let height = args["height"] as? Int,
          width > 0, height > 0, width <= 16384, height <= 16384,
          width * height <= 4 * 1024 * 1024,
          let pixels = args["pixels"] as? FlutterStandardTypedData,
          pixels.data.count == width * height * 16 else { return false }
    remove(id)
    guard frames.count < 4, frames.values.reduce(width * height, { $0 + $1.pixels }) <= 8 * 1024 * 1024 else { return false }
    let valid = pixels.data.withUnsafeBytes { raw -> Bool in
      for offset in stride(from: 0, to: raw.count, by: 4) {
        let value = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
        if !value.isFinite || abs(value) > 65504 { return false }
        if offset % 16 == 12 && (value < 0 || value > 1) { return false }
      }
      return true
    }
    guard valid else { return false }
    let image = CIImage(bitmapData: pixels.data, bytesPerRow: width * 16,
                        size: CGSize(width: width, height: height),
                        format: .RGBAf, colorSpace: colorSpace)
      .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(height)).scaledBy(x: 1, y: -1))
    let view = NativeHdrView(frame: .zero)
    view.wantsLayer = true
    guard let layer = view.layer as? CAMetalLayer else { return false }
    layer.device = device
    layer.pixelFormat = .rgba16Float
    layer.colorspace = colorSpace
    layer.wantsExtendedDynamicRangeContent = true
    layer.framebufferOnly = false
    layer.isOpaque = false
    layer.backgroundColor = NSColor.clear.cgColor
    view.isHidden = true
    parent.addSubview(view, positioned: .above, relativeTo: nil)
    frames[id] = Frame(image: image, pixels: width * height, view: view)
    return true
  }

  private func geometry(id: Int, args: [String: Any]) -> Bool {
    guard let frame = frames[id], let parent = controller?.view else { return false }
    guard args["visible"] as? Bool == true,
          (parent.window?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1) > 1,
          parent.window?.isMiniaturized == false else { frame.view.isHidden = true; return true }
    guard let encoded = args["geometry"] as? FlutterStandardTypedData, encoded.data.count == 80,
          let layer = frame.view.layer as? CAMetalLayer, let queue = queue, let context = context else { return false }
    var g = [Double](repeating: 0, count: 10)
    _ = g.withUnsafeMutableBytes { encoded.data.copyBytes(to: $0) }
    guard g.allSatisfy({ $0.isFinite && abs($0) < 1e8 }), g[8] > g[6], g[9] > g[7] else { return false }
    let scale = parent.window?.backingScaleFactor ?? 1
    let width = ceil(g[8] - g[6]), height = ceil(g[9] - g[7])
    guard width * height <= 16 * 1024 * 1024 else { return false }
    // Dart coordinates are top-down physical pixels; Core Image is bottom-up.
    var rect = CGRect(x: g[6] / scale, y: g[7] / scale, width: width / scale, height: height / scale)
    if !parent.isFlipped { rect.origin.y = parent.bounds.height - rect.maxY }
    frame.view.frame = rect
    layer.contentsScale = scale
    layer.drawableSize = CGSize(width: width, height: height)
    guard let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return false }
    let source = frame.image.extent
    // The float bridge supplies top-down pixels. Map its top-left, top-right and
    // bottom-left to the same affine geometry used by Flutter (including flips).
    let transform = CGAffineTransform(
      a: (g[2] - g[0]) / source.width, b: -(g[3] - g[1]) / source.width,
      c: (g[0] - g[4]) / source.height, d: (g[5] - g[1]) / source.height,
      tx: g[4] - g[6], ty: height - (g[5] - g[7]))
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let image = frame.image.transformed(by: transform)
      .composited(over: CIImage(color: .clear).cropped(to: bounds))
      .cropped(to: bounds)
    context.render(image, to: drawable.texture, commandBuffer: commands, bounds: bounds, colorSpace: colorSpace)
    commands.present(drawable)
    commands.commit()
    frame.view.isHidden = false
    return true
  }
}
