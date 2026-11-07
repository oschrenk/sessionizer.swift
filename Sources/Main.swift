import AppKit
import SwiftUI

/// A borderless panel cannot become key by default, and the search field needs it.
final class Panel: NSPanel {
  override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let model = PickerModel()
  var panel: Panel?

  func applicationDidFinishLaunching(_: Notification) {
    let panel = Panel(
      contentRect: NSRect(origin: .zero, size: pickerSize),
      // non-activating: takes the keyboard without activating the app, which
      // macOS may refuse on launch and leave keystrokes in the previous app
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .floating
    panel.contentView = NSHostingView(rootView: PickerView(model: model))
    // exact centre; `center()` deliberately sits windows above the middle
    if let screen = NSScreen.main?.visibleFrame {
      panel.setFrameOrigin(NSPoint(
        x: screen.midX - pickerSize.width / 2,
        y: screen.midY - pickerSize.height / 2
      ))
    }
    self.panel = panel

    panel.makeKeyAndOrderFront(nil)

    // the walk runs off the main thread, so it never delays the first frame
    Task.detached { [model] in
      let loaded = Result { try loadEntries() }
      await MainActor.run {
        switch loaded {
        case let .success((entries, configDir, backend)):
          model.entries = entries
          model.configDir = configDir
          model.backend = backend
          logTiming("entries ready (\(entries.count))")
        case let .failure(error):
          model.error = "\(error)"
        }
      }
      guard case let .success((_, _, backend)) = loaded, backend == "rex" else { return }
      let hosts = Result { try listRexHosts() }
      await MainActor.run {
        switch hosts {
        case let .success(hosts):
          model.hosts = hosts
        case let .failure(error):
          model.error = "\(error)"
        }
      }
    }
  }
}

func loadEntries() throws -> ([Entry], String, String) {
  guard let file = findConfigFile() else {
    throw ConfigError(description: "Config file not found")
  }
  let config = try parseConfig(String(contentsOfFile: file, encoding: .utf8))
  return (buildEntries(config), (file as NSString).deletingLastPathComponent, config.backend)
}

/// ponytail: spike timing, remove once launch speed is settled.
func logTiming(_ label: String) {
  var info = kinfo_proc()
  var size = MemoryLayout<kinfo_proc>.stride
  var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
  sysctl(&mib, 4, &info, &size, nil, 0)
  let start = info.kp_proc.p_un.__p_starttime
  var now = timeval()
  gettimeofday(&now, nil)
  let ms = (now.tv_sec - start.tv_sec) * 1000 + Int(now.tv_usec - start.tv_usec) / 1000
  FileHandle.standardError.write(Data("\(label): \(ms) ms\n".utf8))
}

@main
enum Sessionizer {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }
}
