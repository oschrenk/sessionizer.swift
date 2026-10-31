import Foundation

private let rexPath = NSHomeDirectory()
  + "/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex"

private struct RexSession: Decodable {
  let sessionId: String
  var label: String?

  enum CodingKeys: String, CodingKey {
    case sessionId = "session_id"
    case label
  }
}

private struct RexSessions: Decodable {
  let sessions: [RexSession]
}

/// The id of the first session labelled `label` in the output of `rex ls --json`.
func rexSessionID(label: String, in listing: Data) throws -> String? {
  try JSONDecoder().decode(RexSessions.self, from: listing).sessions.first { $0.label == label }?.sessionId
}

/// A label, not a layout: a Rex session opens as one plain terminal.
func openRexEntry(_ entry: Entry) throws {
  let listing = try run(rexPath, ["--autostart=false", "ls", "--json"])
  let id = try rexSessionID(label: entry.label, in: listing) ?? JSONDecoder().decode(
    RexSession.self,
    from: run(rexPath, ["--autostart=false", "new", entry.label, "-c", entry.path, "--json"])
  ).sessionId
  do {
    try run(rexPath, ["--autostart=false", "do", "session.select", "session_id=\(id)"])
  } catch {
    throw LayoutError(description: "\(error)\nIs Remote Control on, under Rex Settings → Server?")
  }
  try run("/usr/bin/open", ["-b", "com.superlogical.rex"])
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
