import Foundation
@testable import Sessionizer
import Testing

struct RexTests {
  private static let listing = Data("""
  {"sessions":[
    {"session_id":"session:a","label":"ops/dotfiles"},
    {"session_id":"session:b","label":"ops/dotfiles"},
    {"session_id":"session:c","label":"config/nvim"}
  ]}
  """.utf8)

  @Test
  func `finds the first session with the label`() throws {
    #expect(try rexSessionID(label: "ops/dotfiles", in: Self.listing) == "session:a")
  }

  @Test
  func `no session with the label`() throws {
    #expect(try rexSessionID(label: "ops", in: Self.listing) == nil)
  }

  @Test
  func `host labels in listed order`() throws {
    let listing = Data("""
    {"home":{"label":"","this_machine":true},"hosts":[
      {"host":{"id":"host:a","label":"maxbook.tail.ts.net","endpoints":["https://maxbook.tail.ts.net"]},"from":"home","held":false},
      {"host":{"id":"host:b","label":"studio"},"from":"home","held":false}
    ],"warnings":[]}
    """.utf8)
    #expect(try rexHosts(in: listing) == ["maxbook.tail.ts.net", "studio"])
  }
}

struct RexStepsTests {
  @Test
  func `two columns with a command and focus`() throws {
    let layout = Layout(windows: [
      Window(name: "", layout: "even-horizontal", startDirectory: "", panes: [
        Pane(),
        Pane(shellCommand: ["claude --continue || claude"], focus: true),
      ]),
    ])
    #expect(try rexSteps(layout, path: "/p") == [
      RexStep(window: 0, pane: 0, cwd: "/p"),
      RexStep(
        window: 0, pane: 1, parent: 0, split: "right", cwd: "/p",
        command: "claude --continue || claude", focus: true
      ),
    ])
  }

  @Test
  func `splits map down to below, and later windows start over`() throws {
    let layout = Layout(windows: [
      Window(name: "dev", layout: "even-vertical", startDirectory: "/w", panes: [
        Pane(),
        Pane(shellCommand: ["echo", "hi"], startDirectory: "/q"),
      ]),
      Window(name: "logs", layout: "", startDirectory: "", panes: [Pane()]),
    ])
    #expect(try rexSteps(layout, path: "/p") == [
      RexStep(window: 0, pane: 0, name: "dev", cwd: "/w"),
      RexStep(window: 0, pane: 1, parent: 0, split: "below", cwd: "/q", command: "echo hi"),
      RexStep(window: 1, pane: 0, name: "logs", cwd: "/p"),
    ])
  }

  @Test
  func `unknown layout names the window`() {
    let layout = Layout(windows: [Window(name: "", layout: "spiral", startDirectory: "", panes: [Pane()])])
    #expect(throws: LayoutError.self) {
      try rexSteps(layout, path: "/p")
    }
  }
}

struct BackendConfigTests {
  @Test(arguments: [
    ("", ""),
    ("[base]\nbackend = \"ghostty\"", "ghostty"),
    ("[base]\nbackend = \"rex\"", "rex"),
  ])
  func `reads the backend`(toml: String, want: String) throws {
    #expect(try parseConfig(toml).backend == want)
  }

  @Test
  func `rejects an unknown backend`() {
    #expect(throws: ConfigError.self) {
      try parseConfig("[base]\nbackend = \"tmux\"")
    }
  }
}
