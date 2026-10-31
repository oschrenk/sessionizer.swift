import Foundation
@testable import Sessionizer
import Testing

private func tempDir() -> String {
  let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString).path
  try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
  return dir
}

private func mkdir(_ path: String) {
  try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
}

private func touch(_ path: String) {
  FileManager.default.createFile(atPath: path, contents: Data("windows: []".utf8))
}

struct ResolveLayoutPathTests {
  let sessionDir = tempDir()
  let configDir = tempDir()
  let directLayout: String
  let namedLayout: String
  var localLayout: String { sessionDir + "/.sessionizer.yml" }

  init() {
    mkdir(configDir + "/layouts")
    namedLayout = configDir + "/layouts/work.yml"
    touch(namedLayout)
    directLayout = tempDir() + "/default.yml"
    touch(directLayout)
  }

  func resolve(layout: String = "", layoutPath: String = "") -> String? {
    resolveLayoutPath(
      sessionPath: sessionDir, layout: layout, layoutPath: layoutPath, configDir: configDir
    )
  }

  @Test func `none configured returns nil`() {
    #expect(resolve() == nil)
  }

  @Test func `direct layoutPath is used when it exists`() {
    #expect(resolve(layoutPath: directLayout) == directLayout)
  }

  @Test func `missing layoutPath falls through to none`() {
    #expect(resolve(layoutPath: tempDir() + "/missing.yml") == nil)
  }

  @Test func `named layout is resolved from configDir layouts`() {
    #expect(resolve(layout: "work") == namedLayout)
  }

  @Test func `local sessionizer yml wins over layoutPath`() {
    touch(localLayout)
    #expect(resolve(layoutPath: directLayout) == localLayout)
  }

  @Test func `local sessionizer yml wins over named layout`() {
    touch(localLayout)
    #expect(resolve(layout: "work") == localLayout)
  }

  @Test func `layoutPath wins over named layout`() {
    #expect(resolve(layout: "work", layoutPath: directLayout) == directLayout)
  }
}

struct BuildEntriesDefaultLayoutTests {
  let base: Config

  init() {
    let searchDir = tempDir()
    mkdir(searchDir + "/walked/.git")
    base = Config(
      startupName: "startup",
      startupPath: tempDir(),
      defaultLayout: "global",
      searchDirs: [searchDir],
      searchEntries: [
        SearchEntry(path: "/tmp/bare", name: "bare"),
        SearchEntry(path: "/tmp/own", name: "own", layout: "entry-own"),
      ],
      rooterPatterns: [".git"]
    )
  }

  func entry(_ entries: [Entry], _ label: String) throws -> Entry {
    try #require(entries.first { $0.label == label })
  }

  @Test func `default layout reaches walked, manual and startup entries`() throws {
    let entries = buildEntries(base)
    for label in ["startup", "walked", "bare"] {
      #expect(try entry(entries, label).layout == "global")
    }
  }

  @Test func `entry layout wins over default layout`() throws {
    #expect(try entry(buildEntries(base), "own").layout == "entry-own")
  }

  @Test func `startup layout wins over default layout`() throws {
    var config = base
    config.startupLayout = "startup-own"
    #expect(try entry(buildEntries(config), "startup").layout == "startup-own")
  }

  @Test func `startup layout path wins over default layout`() throws {
    var config = base
    config.startupLayoutPath = "/tmp/startup.yml"
    let startup = try entry(buildEntries(config), "startup")
    #expect(startup.layout == "")
    #expect(startup.layoutPath == "/tmp/startup.yml")
  }

  @Test func `no default layout leaves entries untouched`() throws {
    var config = base
    config.defaultLayout = ""
    let entries = buildEntries(config)
    for label in ["startup", "walked", "bare"] {
      #expect(try entry(entries, label).layout == "")
    }
  }

  @Test func `no startup name drops the startup entry`() {
    var config = base
    config.startupName = ""
    #expect(!buildEntries(config).contains { $0.label == "startup" })
  }
}

struct BuildEntriesDeduplicatesTests {
  let searchDir = tempDir()
  let project: String
  let base: Config

  init() {
    project = searchDir + "/ops/dotfiles"
    mkdir(project + "/.git")
    base = Config(searchDirs: [searchDir], rooterPatterns: [".git"])
  }

  @Test func `startup wins over the walked directory`() {
    var config = base
    config.startupName = "dotfiles"
    config.startupPath = project
    #expect(buildEntries(config).map(\.label) == ["dotfiles"])
  }

  @Test func `a manual entry wins over the walked directory`() {
    var config = base
    config.searchEntries = [SearchEntry(path: project, name: "config/dotfiles")]
    #expect(buildEntries(config).map(\.label) == ["config/dotfiles"])
  }

  @Test func `startup wins over a manual entry`() {
    var config = base
    config.searchDirs = []
    config.startupName = "dotfiles"
    config.startupPath = project
    config.searchEntries = [SearchEntry(path: project, name: "config/dotfiles")]
    #expect(buildEntries(config).map(\.label) == ["dotfiles"])
  }

  @Test func `a trailing slash is still the same path`() {
    var config = base
    config.startupName = "dotfiles"
    config.startupPath = project + "/"
    #expect(buildEntries(config).count == 1)
  }

  @Test func `distinct paths are all kept`() {
    let otherDir = tempDir()
    mkdir(otherDir + "/tools/sessionizer/.git")
    var config = base
    config.searchDirs = [searchDir, otherDir]
    config.searchEntries = [SearchEntry(path: tempDir())]
    #expect(buildEntries(config).count == 3)
  }
}

struct WalkTests {
  @Test func `walk is byte ordered, nested, and skips ignored and project subdirs`() {
    let dir = tempDir()
    mkdir(dir + "/b/.git")
    mkdir(dir + "/b/sub/.git")
    mkdir(dir + "/a/nested/.git")
    mkdir(dir + "/node_modules/pkg/.git")
    mkdir(dir + "/Z/.git")
    let labels = entriesFromDir(dir, ignore: ["node_modules"], rooterPatterns: [".git"])
      .map(\.label)
    #expect(labels == ["Z", "a/nested", "b"])
  }

  @Test func `a missing search dir gives no entries`() {
    #expect(entriesFromDir("/nonexistent/x", ignore: [], rooterPatterns: [".git"]).isEmpty)
  }
}

struct ConfigTests {
  @Test func `search entries accept strings, inline tables and arrays of tables`() throws {
    let inline = try parseConfig("""
    [search]
    entries = ["$HOME/a", { path = "/b", name = "bee", layout = "l" }]
    """)
    #expect(inline.searchEntries == [
      SearchEntry(path: NSHomeDirectory() + "/a"),
      SearchEntry(path: "/b", name: "bee", layout: "l"),
    ])

    let tables = try parseConfig("""
    [[search.entries]]
    name = "config/nvim"
    path = "/c"
    """)
    #expect(tables.searchEntries == [SearchEntry(path: "/c", name: "config/nvim")])
  }

  @Test func `an entry table without path is an error`() {
    #expect(throws: ConfigError.self) {
      try parseConfig("[search]\nentries = [{ name = \"x\" }]")
    }
  }

  @Test func `legacy default keys are an error`() {
    #expect(throws: ConfigError.self) {
      try parseConfig("[default]\nname = \"x\"")
    }
  }

  @Test func `expandEnv matches Go os ExpandEnv`() {
    let env = ["A": "1", "B_2": "two"]
    #expect(expandEnv("$A/${B_2}/$UNSET/x$", env: env) == "1/two//x$")
  }
}
