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
