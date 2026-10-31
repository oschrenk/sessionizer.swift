import AppKit
import Carbon

/// Creates `pane` by splitting `parent` in direction `dir`.
struct Step: Equatable {
  var pane: Int
  var parent: Int
  var dir: String
}

/// Orders the splits that turn one pane into n panes arranged like the tmux
/// layout. A chain of splits in one direction comes out even once
/// equalize_splits runs.
func splitPlan(_ layout: String, _ n: Int) throws -> [Step] {
  var plan: [Step] = []
  func chain(_ from: Int, _ to: Int, _ dir: String) {
    for p in stride(from: from, to: to, by: 1) {
      plan.append(Step(pane: p, parent: p - 1, dir: dir))
    }
  }

  switch layout {
  case "even-horizontal", "":
    chain(1, n, "right")
  case "even-vertical":
    chain(1, n, "down")
  case "main-vertical":
    if n > 1 {
      plan.append(Step(pane: 1, parent: 0, dir: "right"))
      chain(2, n, "down")
    }
  case "main-horizontal":
    if n > 1 {
      plan.append(Step(pane: 1, parent: 0, dir: "down"))
      chain(2, n, "right")
    }
  case "tiled":
    // rows first, so the root splits into full-width rows
    let cols = Int(Double(n).squareRoot().rounded(.up))
    for r in stride(from: cols, to: n, by: cols) {
      plan.append(Step(pane: r, parent: r - cols, dir: "down"))
    }
    for r in stride(from: 0, to: n, by: cols) {
      chain(r + 1, min(r + cols, n), "right")
    }
  default:
    throw LayoutError(description: "unknown layout \"\(layout)\"")
  }
  return plan
}

/// Collects AppleScript lines and the argv they read. Every path, name and
/// command goes through `arg`, so none of them is ever part of the script text.
private struct Script {
  var lines: [String] = []
  var args: [String] = []

  mutating func arg(_ v: String) -> String {
    args.append(v)
    return "(item \(args.count) of argv)"
  }

  mutating func add(_ line: String) {
    lines.append("    " + line)
  }

  /// Sets cfg up for one pane: its directory and its command.
  mutating func config(_ dir: String, _ pane: Pane) {
    add("set cfg to new surface configuration")
    add("set initial working directory of cfg to \(arg(dir))")
    if !pane.shellCommand.isEmpty {
      add("set initial input of cfg to \(arg(pane.shellCommand.joined(separator: " ") + "\n"))")
    }
  }
}

/// The handler `openWindow` calls. AppleScript lowercases handler names.
let handlerName = "open_session"

/// Builds the script that opens a Ghostty window titled `title`, with one tab
/// per layout window and one split per pane, or brings an open window with that
/// title to the front. `with title` needs the patched Ghostty fork.
func buildScript(path: String, title: String, layout: Layout) throws -> (String, [String]) {
  var s = Script()
  var focus: [String] = []

  // a pick from another app, such as a launcher, must bring Ghostty forward
  s.add("activate")
  let titleArg = s.arg(title)
  s.add("set found to every window whose name is \(titleArg)")
  s.add("if found is not {} then")
  s.add("  activate window (item 1 of found)")
  s.add("  return")
  s.add("end if")

  for (w, window) in layout.windows.enumerated() {
    let plan: [Step]
    do {
      plan = try splitPlan(window.layout, window.panes.count)
    } catch {
      throw LayoutError(description: "window \(w): \(error)")
    }

    func dir(_ p: Int) -> String {
      [window.panes[p].startDirectory, window.startDirectory].first { !$0.isEmpty } ?? path
    }
    func term(_ p: Int) -> String { "t\(w)_\(p)" }

    s.config(dir(0), window.panes[0])
    if w == 0 {
      s.add("set w to new window with configuration cfg with title \(titleArg)")
      s.add("set tb to selected tab of w")
    } else {
      s.add("set tb to new tab in w with configuration cfg")
    }
    s.add("set \(term(0)) to focused terminal of tb")

    if !window.name.isEmpty {
      s.add("perform action (\"set_tab_title:\" & \(s.arg(window.name))) on \(term(0))")
    }

    for st in plan {
      s.config(dir(st.pane), window.panes[st.pane])
      s.add(
        "set \(term(st.pane)) to split \(term(st.parent)) direction \(st.dir) with configuration cfg"
      )
    }
    if !plan.isEmpty {
      s.add("perform action \"equalize_splits\" on \(term(0))")
    }

    focus += window.panes.indices.filter { window.panes[$0].focus }.map(term)
  }

  // focus selects the tab of the terminal it focuses, so tab 1 goes last, as
  // tmux selects the first window after applying a layout
  for t in focus.reversed() {
    s.add("focus \(t)")
  }
  s.add("select tab (tab 1 of w)")

  let text = "on \(handlerName)(argv)\n  tell application \"Ghostty\"\n"
    + s.lines.joined(separator: "\n") + "\n  end tell\nend \(handlerName)"
  return (text, s.args)
}

/// Port of the Ghostty branch of the Go `StartSession`.
@MainActor
func openEntry(_ entry: Entry, configDir: String) throws {
  var layout = simpleLayout(name: entry.label, path: entry.path)
  if let resolved = resolveLayoutPath(
    sessionPath: entry.path, layout: entry.layout, layoutPath: entry.layoutPath, configDir: configDir
  ) {
    layout = try readLayout(path: resolved)
  }
  let (text, args) = try buildScript(path: entry.path, title: entry.label, layout: layout)
  try runHandler(text, args: args)
}

/// Runs the script's handler in-process, passing args as an AppleScript list.
/// The values never enter the script text.
@MainActor
private func runHandler(_ text: String, args: [String]) throws {
  guard let script = NSAppleScript(source: text) else {
    throw LayoutError(description: "ghostty: script did not load")
  }

  let argv = NSAppleEventDescriptor.list()
  for (i, a) in args.enumerated() {
    argv.insert(NSAppleEventDescriptor(string: a), at: i + 1)
  }
  let params = NSAppleEventDescriptor.list()
  params.insert(argv, at: 1)

  let event = NSAppleEventDescriptor.appleEvent(
    withEventClass: AEEventClass(kASAppleScriptSuite),
    eventID: AEEventID(kASSubroutineEvent),
    targetDescriptor: nil,
    returnID: AEReturnID(kAutoGenerateReturnID),
    transactionID: AETransactionID(kAnyTransactionID)
  )
  event.setDescriptor(NSAppleEventDescriptor(string: handlerName), forKeyword: AEKeyword(keyASSubroutineName))
  event.setParam(params, forKeyword: AEKeyword(keyDirectObject))

  var error: NSDictionary?
  script.executeAppleEvent(event, error: &error)
  if let error {
    let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
    throw LayoutError(description: "ghostty: \(message)")
  }
}
