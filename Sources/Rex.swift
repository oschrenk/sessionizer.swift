import Foundation

private let rexPath = NSHomeDirectory()
  + "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"

private struct RexSession: Decodable {
  let sessionId: String
  var label: String?
}

private struct RexSessions: Decodable {
  let sessions: [RexSession]
}

/// What `rex new`, `rex window new` and `rex split` print with `--json`.
private struct RexCreated: Decodable {
  var sessionId: String?
  var initialWindows: [RexCreated]?
  var windowId: String?
  var blockIds: [String]?
}

private func decode<T: Decodable>(_ data: Data) throws -> T {
  let decoder = JSONDecoder()
  decoder.keyDecodingStrategy = .convertFromSnakeCase
  return try decoder.decode(T.self, from: data)
}

/// The id of the first session labelled `label` in the output of `rex ls --json`.
func rexSessionID(label: String, in listing: Data) throws -> String? {
  let listed: RexSessions = try decode(listing)
  return listed.sessions.first { $0.label == label }?.sessionId
}

/// One terminal to create. `parent` is the pane it splits, nil for a window's first pane.
struct RexStep: Equatable {
  var window: Int
  var pane: Int
  var parent: Int?
  var split = ""
  var name = ""
  var cwd: String
  var command = ""
  var focus = false
}

/// The terminals of a layout, in the order to create them.
func rexSteps(_ layout: Layout, path: String) throws -> [RexStep] {
  var steps: [RexStep] = []
  for (w, window) in layout.windows.enumerated() {
    let plan: [Step]
    do {
      plan = try splitPlan(window.layout, window.panes.count)
    } catch {
      throw LayoutError(description: "window \(w): \(error)")
    }

    func step(_ p: Int) -> RexStep {
      let pane = window.panes[p]
      return RexStep(
        window: w,
        pane: p,
        cwd: [pane.startDirectory, window.startDirectory].first { !$0.isEmpty } ?? path,
        command: pane.shellCommand.joined(separator: " "),
        focus: pane.focus
      )
    }

    var first = step(0)
    first.name = window.name
    steps.append(first)
    for st in plan {
      var next = step(st.pane)
      next.parent = st.parent
      next.split = st.dir == "down" ? "below" : st.dir
      steps.append(next)
    }
  }
  return steps
}

/// Creates the session and applies its layout, or removes what it created and throws.
private func createRexSession(_ entry: Entry, configDir: String) throws -> String {
  let steps = try rexSteps(resolveLayout(entry, configDir: configDir), path: entry.path)
  var session = ""
  var firstWindow = ""
  var blocks: [[Int]: String] = [:]

  do {
    for step in steps {
      let block: String
      if let parent = step.parent, let anchor = blocks[[step.window, parent]] {
        let created: RexCreated = try decode(rex(
          "split", "-s", session, "-b", anchor, "--split", step.split, "--cwd", step.cwd, "--focus=false", "--json"
        ))
        block = created.blockIds?.first ?? ""
      } else if step.window == 0 {
        let name = step.name.isEmpty ? [] : ["--window", step.name]
        let created: RexCreated = try decode(rex(["new", entry.label, "-c", step.cwd] + name + ["--json"]))
        session = created.sessionId ?? ""
        firstWindow = created.initialWindows?.first?.windowId ?? ""
        block = created.initialWindows?.first?.blockIds?.first ?? ""
      } else {
        let name = step.name.isEmpty ? [] : [step.name]
        let created: RexCreated = try decode(rex(
          ["window", "new", "-s", session] + name + ["-c", step.cwd, "--focus=false", "--json"]
        ))
        block = created.blockIds?.first ?? ""
      }
      blocks[[step.window, step.pane]] = block
      // typed into the shell, as the Ghostty backend does, so the shell parses it and outlives it
      if !step.command.isEmpty {
        try rex("send", "-s", session, "-b", block, step.command + "\n")
      }
    }

    // focusing a block selects its window, so the first window goes last, as in the Ghostty backend
    for step in steps.reversed() where step.focus {
      try rex("block", "focus", "-s", session, blocks[[step.window, step.pane]] ?? "")
    }
    try rex("window", "focus", "-s", session, firstWindow)
  } catch {
    if !session.isEmpty {
      _ = try? rex("kill", session)
    }
    throw error
  }
  return session
}

func openRexEntry(_ entry: Entry, configDir: String) throws {
  let id = try rexSessionID(label: entry.label, in: rex("ls", "--json"))
    ?? createRexSession(entry, configDir: configDir)
  do {
    try rex("do", "session.select", "session_id=\(id)")
  } catch {
    throw LayoutError(description: "\(error)\nIs Remote Control on, under Rex Settings → Server?")
  }
  try run("/usr/bin/open", ["-b", "com.superlogical.rex"])
}

@discardableResult
private func rex(_ args: String...) throws -> Data {
  try rex(args)
}

@discardableResult
private func rex(_ args: [String]) throws -> Data {
  try run(rexPath, ["--autostart=false"] + args)
}

@discardableResult
private func run(_ path: String, _ args: [String]) throws -> Data {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: path)
  process.arguments = args
  let out = Pipe()
  let err = Pipe()
  process.standardOutput = out
  process.standardError = err
  do {
    try process.run()
  } catch {
    throw LayoutError(description: "rex: \(error.localizedDescription)")
  }
  let stdout = out.fileHandleForReading.readDataToEndOfFile()
  let stderr = err.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw LayoutError(description: "rex: \(String(decoding: stderr, as: UTF8.self))")
  }
  return stdout
}
