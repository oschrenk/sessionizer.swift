import Foundation
@testable import Sessionizer
import Testing

private func fixture(_ name: String) throws -> String {
  try #require(Bundle.module.path(forResource: name, ofType: "yaml", inDirectory: "testdata"))
}

struct SplitPlanTests {
  private static func s(_ pane: Int, _ parent: Int, _ dir: String) -> Step {
    Step(pane: pane, parent: parent, dir: dir)
  }

  @Test(arguments: [
    ("even-horizontal", 1, []),
    ("even-horizontal", 3, [s(1, 0, "right"), s(2, 1, "right")]),
    ("", 2, [s(1, 0, "right")]),
    ("even-vertical", 3, [s(1, 0, "down"), s(2, 1, "down")]),
    ("main-vertical", 1, []),
    ("main-vertical", 4, [s(1, 0, "right"), s(2, 1, "down"), s(3, 2, "down")]),
    ("main-horizontal", 3, [s(1, 0, "down"), s(2, 1, "right")]),
    // 2x2: row 2 first, then each row filled to the right
    ("tiled", 4, [s(2, 0, "down"), s(1, 0, "right"), s(3, 2, "right")]),
    // 3 panes: two on top, one full-width below
    ("tiled", 3, [s(2, 0, "down"), s(1, 0, "right")]),
    ("tiled", 5, [s(3, 0, "down"), s(1, 0, "right"), s(2, 1, "right"), s(4, 3, "right")]),
  ] as [(String, Int, [Step])])
  func `split plan`(layout: String, n: Int, want: [Step]) throws {
    #expect(try splitPlan(layout, n) == want)
  }

  @Test func `unknown layout is an error`() {
    #expect(throws: LayoutError.self) { try splitPlan("spiral", 2) }
  }
}

struct BuildScriptTests {
  @Test func `script reads every value from argv`() throws {
    var layout = try readLayout(path: fixture("multi_window_layout"))
    layout.windows[0].panes[0].startDirectory = "/it's a dir"

    let (text, args) = try buildScript(path: "/session", title: "group/repo", layout: layout)

    for want in [
      "on open_session(argv)",
      "set found to every window whose name is (item 1 of argv)",
      "set w to new window with configuration cfg with title (item 1 of argv)",
      "set t0_1 to split t0_0 direction right with configuration cfg",
      "set t0_3 to split t0_2 direction down with configuration cfg",
      "set tb to new tab in w with configuration cfg",
      "focus t0_2",
      "select tab (tab 1 of w)",
    ] {
      #expect(text.contains(want), "script lacks \(want)")
    }

    // argv carries every value, and the script text carries none of them
    for v in ["/it's a dir", "group/repo", "dev", "echo Pane 3\n", "/var/log", "tail -f system.log\n"] {
      #expect(args.contains(v), "args lack \(v)")
      #expect(!text.contains(v.trimmingCharacters(in: .whitespacesAndNewlines)), "script has \(v)")
    }
  }
}

struct LayoutTests {
  @Test func `simple layout is one focused pane`() {
    let layout = simpleLayout(name: "test-window", path: "/home/user")
    #expect(layout == Layout(windows: [
      Window(
        name: "test-window", layout: "main-vertical", startDirectory: "/home/user",
        panes: [Pane(focus: true)]
      ),
    ]))
  }

  @Test func `basic layout reads`() throws {
    let layout = try readLayout(path: fixture("basic_layout"))
    #expect(layout == Layout(windows: [
      Window(
        name: "test", layout: "main-vertical", startDirectory: "/tmp",
        panes: [Pane(shellCommand: ["echo", "hello"], focus: true)]
      ),
    ]))
  }

  @Test func `missing layout file is an error`() {
    #expect(throws: (any Error).self) { try readLayout(path: "nonexistent.yaml") }
  }

  @Test func `multi window layout reads and expands`() throws {
    let layout = try readLayout(path: fixture("multi_window_layout"))
    #expect(layout.windows.map(\.name) == ["dev", "logs"])
    #expect(layout.windows[0].startDirectory == NSHomeDirectory() + "/projects")
    #expect(layout.windows[0].panes.map(\.focus) == [false, false, true, false])
    #expect(layout.windows[1].layout == "even-horizontal")
    #expect(layout.windows[1].panes.count == 1)
  }

  @Test func `a window without panes is an error`() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).yml")
    try "windows:\n- layout: tiled\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(throws: LayoutError.self) { try readLayout(path: file.path) }
  }
}

struct FuzzyTests {
  @Test func `subsequence matches and word starts rank first`() {
    let entries = ["config/nvim", "personal/novim", "work/api"].map { Entry(label: $0, path: "/" + $0) }
    #expect(fuzzyFilter(entries, "nvim").map(\.label) == ["config/nvim", "personal/novim"])
    #expect(fuzzyFilter(entries, "").count == 3)
    #expect(fuzzyFilter(entries, "zzz").isEmpty)
  }
}
