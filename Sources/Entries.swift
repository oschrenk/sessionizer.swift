import Foundation

struct Entry: Equatable, Hashable {
  var label: String
  var path: String
  /// names a layout resolved from configDir/layouts/<name>.yml
  var layout = ""
  /// a direct path to a layout file, `~` and env expanded at resolve time
  var layoutPath = ""
}

let layoutFileName = ".sessionizer.yml"

/// Finds the project directories within `dir` that hold a rooter pattern.
/// Matches Go's `filepath.WalkDir`: children in byte order, symlinks never
/// followed, a project is not descended into, and the first error ends the walk
/// with what was found so far.
func entriesFromDir(_ dir: String, ignore: [String], rooterPatterns: [String]) -> [Entry] {
  let fm = FileManager.default
  var entries: [Entry] = []

  // returns false once the walk must stop
  func visit(_ url: URL, path: String) -> Bool {
    let hasRooter = rooterPatterns.contains { fm.fileExists(atPath: join(path, $0)) }
    if hasRooter {
      entries.append(Entry(label: path.replacingOccurrences(of: dir + "/", with: ""), path: path))
      return true
    }
    if ignore.contains(url.lastPathComponent) { return true }

    guard let children = try? fm.contentsOfDirectory(
      at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []
    ) else { return false }
    let dirs = children
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .sorted { $0.lastPathComponent.utf8.lexicographicallyPrecedes($1.lastPathComponent.utf8) }
    for child in dirs where !visit(child, path: join(path, child.lastPathComponent)) {
      return false
    }
    return true
  }

  // the root is checked with lstat, like WalkDir: a symlinked root yields nothing
  let rootType = try? fm.attributesOfItem(atPath: dir)[.type] as? FileAttributeType
  if rootType == .typeDirectory {
    _ = visit(URL(fileURLWithPath: dir, isDirectory: true), path: dir)
  }
  return entries
}

private func join(_ parent: String, _ name: String) -> String {
  parent.hasSuffix("/") ? parent + name : parent + "/" + name
}

/// The label is the custom name, or the base of the path.
func entryFromSearchEntry(_ se: SearchEntry) -> Entry {
  Entry(
    label: se.name.isEmpty ? (se.path as NSString).lastPathComponent : se.name,
    path: se.path,
    layout: se.layout
  )
}

/// Seeds the global default layout onto an entry that names no layout of its own.
func applyDefaultLayout(_ entry: Entry, _ defaultLayout: String) -> Entry {
  var entry = entry
  if entry.layout.isEmpty, entry.layoutPath.isEmpty {
    entry.layout = defaultLayout
  }
  return entry
}

func startupEntry(_ config: Config) -> Entry {
  applyDefaultLayout(
    Entry(
      label: config.startupName,
      path: config.startupPath,
      layout: config.startupLayout,
      layoutPath: config.startupLayoutPath
    ),
    config.defaultLayout
  )
}

/// Entry sources, ordered from most to least explicit.
enum Source: Int, Comparable {
  case startup, manual, walked

  static func < (a: Source, b: Source) -> Bool { a.rawValue < b.rawValue }
}

/// Collapses entries that name the same path. The most explicit source wins,
/// and it takes the position of the first mention of that path.
func dedupe(_ sourced: [(entry: Entry, source: Source)]) -> [Entry] {
  var kept: [(entry: Entry, source: Source)] = []
  var positions: [String: Int] = [:]
  for candidate in sourced {
    let key = URL(fileURLWithPath: candidate.entry.path).standardized.path
    guard let position = positions[key] else {
      positions[key] = kept.count
      kept.append(candidate)
      continue
    }
    if candidate.source < kept[position].source {
      kept[position] = candidate
    }
  }
  return kept.map(\.entry)
}

func buildEntries(_ config: Config) -> [Entry] {
  var sourced: [(entry: Entry, source: Source)] = []
  if !config.startupName.trimmingCharacters(in: .whitespaces).isEmpty {
    sourced.append((startupEntry(config), .startup))
  }
  for dir in config.searchDirs {
    sourced += entriesFromDir(dir, ignore: config.ignore, rooterPatterns: config.rooterPatterns)
      .map { ($0, .walked) }
  }
  sourced += config.searchEntries.map { (entryFromSearchEntry($0), .manual) }

  return dedupe(sourced).map { applyDefaultLayout($0, config.defaultLayout) }
}

/// The layout file to apply, or nil. Precedence: local `.sessionizer.yml` >
/// direct layoutPath > named layout from configDir/layouts/.
func resolveLayoutPath(
  sessionPath: String,
  layout: String,
  layoutPath: String,
  configDir: String
) -> String? {
  let fm = FileManager.default
  let local = join(sessionPath, layoutFileName)
  if fm.fileExists(atPath: local) { return local }
  if !layoutPath.isEmpty {
    let direct = expandPath(layoutPath)
    if fm.fileExists(atPath: direct) { return direct }
  }
  if !layout.isEmpty {
    let named = join(configDir, "layouts/\(layout).yml")
    if fm.fileExists(atPath: named) { return named }
  }
  return nil
}
