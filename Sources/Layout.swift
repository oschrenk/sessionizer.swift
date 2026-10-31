import Foundation
import Yams

/// The tmuxp-compatible layout format of `.sessionizer.yml` and `layouts/<name>.yml`.
struct Layout: Decodable, Equatable {
  var windows: [Window]
}

struct Window: Decodable, Equatable {
  var name = ""
  /// even-horizontal, even-vertical, main-horizontal, main-vertical or tiled
  var layout = ""
  var startDirectory = ""
  var panes: [Pane]

  enum CodingKeys: String, CodingKey {
    case name = "window_name", layout, startDirectory = "start_directory", panes
  }

  init(name: String, layout: String, startDirectory: String, panes: [Pane]) {
    self.name = name
    self.layout = layout
    self.startDirectory = startDirectory
    self.panes = panes
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    layout = try c.decodeIfPresent(String.self, forKey: .layout) ?? ""
    startDirectory = try c.decodeIfPresent(String.self, forKey: .startDirectory) ?? ""
    panes = try c.decodeIfPresent([Pane].self, forKey: .panes) ?? []
  }
}

struct Pane: Decodable, Equatable {
  var shellCommand: [String] = []
  var focus = false
  var startDirectory = ""

  enum CodingKeys: String, CodingKey {
    case shellCommand = "shell_command", focus, startDirectory = "start_directory"
  }

  init(shellCommand: [String] = [], focus: Bool = false, startDirectory: String = "") {
    self.shellCommand = shellCommand
    self.focus = focus
    self.startDirectory = startDirectory
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    shellCommand = try c.decodeIfPresent([String].self, forKey: .shellCommand) ?? []
    focus = try c.decodeIfPresent(Bool.self, forKey: .focus) ?? false
    startDirectory = try c.decodeIfPresent(String.self, forKey: .startDirectory) ?? ""
  }
}

struct LayoutError: Error, CustomStringConvertible {
  let description: String
}

/// The layout used when no layout file resolves: one window, one focused pane.
func simpleLayout(name: String, path: String) -> Layout {
  Layout(windows: [
    Window(name: name, layout: "main-vertical", startDirectory: path, panes: [Pane(focus: true)]),
  ])
}

/// The entry's layout file when one resolves, else `simpleLayout`.
func resolveLayout(_ entry: Entry, configDir: String) throws -> Layout {
  guard let resolved = resolveLayoutPath(
    sessionPath: entry.path, layout: entry.layout, layoutPath: entry.layoutPath, configDir: configDir
  ) else {
    return simpleLayout(name: entry.label, path: entry.path)
  }
  return try readLayout(path: resolved)
}

func readLayout(path: String) throws -> Layout {
  let text = try String(contentsOfFile: path, encoding: .utf8)
  var layout = try YAMLDecoder().decode(Layout.self, from: text)

  if layout.windows.isEmpty {
    throw LayoutError(description: "layout must have at least one window")
  }
  for i in layout.windows.indices {
    if layout.windows[i].panes.isEmpty {
      throw LayoutError(description: "window \(i) must have at least one pane")
    }
    layout.windows[i].startDirectory = expandPath(layout.windows[i].startDirectory)
    for j in layout.windows[i].panes.indices where !layout.windows[i].panes[j].startDirectory.isEmpty {
      layout.windows[i].panes[j].startDirectory = expandPath(layout.windows[i].panes[j].startDirectory)
    }
  }
  return layout
}
