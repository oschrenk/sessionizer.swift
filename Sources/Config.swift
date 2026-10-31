import Foundation
import TOMLKit

struct SearchEntry: Equatable {
  var path: String
  var name = ""
  var layout = ""
}

struct Config {
  var backend = ""
  var startupName = ""
  var startupPath = ""
  var startupLayout = ""
  var startupLayoutPath = ""
  var defaultLayout = ""
  var searchDirs: [String] = []
  var searchEntries: [SearchEntry] = []
  var ignore: [String] = []
  var rooterPatterns: [String] = []
}

struct ConfigError: Error, CustomStringConvertible {
  let description: String
}

/// Same lookup order as viper in the Go CLI: `$XDG_CONFIG_HOME` first, then `~/.config`.
func findConfigFile() -> String? {
  let env = ProcessInfo.processInfo.environment
  let home = NSHomeDirectory()
  return [
    env["XDG_CONFIG_HOME"].map { "\($0)/sessionizer/config.toml" },
    "\(home)/.config/sessionizer/config.toml",
  ]
  .compactMap(\.self)
  .first { FileManager.default.fileExists(atPath: $0) }
}

/// The `[default]` keys that described the startup session before `[default]`
/// was re-taken for the global layout fallback. Ignoring them would silently
/// drop the startup entry.
let legacyKeys = ["name", "path", "layout_path"]

func parseConfig(_ text: String) throws -> Config {
  let toml = try TOMLTable(string: text)

  let legacy = legacyKeys.filter { toml["default"]?[$0] != nil }
  if !legacy.isEmpty {
    throw ConfigError(description: """
    Obsolete config key(s): \(legacy.map { "default.\($0)" }.joined(separator: ", "))
    The startup session moved from [default] to [startup].
    """)
  }

  func string(_ section: String, _ key: String) -> String {
    toml[section]?[key]?.string ?? ""
  }
  func strings(_ section: String, _ key: String) -> [String] {
    (toml[section]?[key]?.array).map { $0.compactMap(\.string) } ?? []
  }

  let backend = string("base", "backend")
  guard ["", "ghostty", "rex"].contains(backend) else {
    throw ConfigError(description: "Unknown backend \"\(backend)\", want \"ghostty\" or \"rex\"")
  }

  return try Config(
    backend: backend,
    startupName: string("startup", "name"),
    startupPath: expandEnv(string("startup", "path")),
    startupLayout: string("startup", "layout"),
    startupLayoutPath: string("startup", "layout_path"),
    defaultLayout: string("default", "layout"),
    searchDirs: strings("search", "directories").map { expandEnv($0) },
    searchEntries: parseSearchEntries(toml["search"]?["entries"]?.array),
    ignore: strings("base", "ignore"),
    rooterPatterns: strings("base", "rooter_patterns")
  )
}

/// `search.entries` mixes plain path strings with tables holding `path` and
/// optional `name` and `layout`. `[[search.entries]]` arrives as the same array.
func parseSearchEntries(_ raw: TOMLArray?) throws -> [SearchEntry] {
  guard let raw else { return [] }
  return try raw.enumerated().map { i, item in
    if let path = item.string {
      return SearchEntry(path: expandEnv(path))
    }
    guard let table = item.table else {
      throw ConfigError(description: "search.entries[\(i)]: expected string or object")
    }
    guard let path = table["path"]?.string else {
      throw ConfigError(description: "search.entries[\(i)]: missing or invalid 'path'")
    }
    return SearchEntry(
      path: expandEnv(path),
      name: table["name"]?.string ?? "",
      layout: table["layout"]?.string ?? ""
    )
  }
}

/// Port of Go's `os.ExpandEnv`: `$VAR` and `${VAR}`, unset variables become "".
func expandEnv(_ s: String, env: [String: String] = ProcessInfo.processInfo.environment) -> String {
  var out = ""
  var rest = Substring(s)
  while let dollar = rest.firstIndex(of: "$") {
    out += rest[..<dollar]
    let after = rest[rest.index(after: dollar)...]
    if after.first == "{", let close = after.firstIndex(of: "}") {
      out += env[String(after[after.index(after: after.startIndex) ..< close])] ?? ""
      rest = after[after.index(after: close)...]
    } else {
      let name = after.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
      out += name.isEmpty ? "$" : env[String(name)] ?? ""
      rest = after[name.endIndex...]
    }
  }
  return out + rest
}

/// Port of `tmuxp.ExpandPath`: a leading `~/` becomes the home directory, then `expandEnv`.
func expandPath(_ path: String) -> String {
  let path = path.hasPrefix("~/") ? NSHomeDirectory() + path.dropFirst() : path
  return expandEnv(path)
}
