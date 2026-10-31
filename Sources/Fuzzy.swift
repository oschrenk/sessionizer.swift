/// Scores `text` against `query` as a case-insensitive subsequence, or nil when
/// it does not match. Consecutive characters and word starts score higher.
/// ponytail: not go-fuzzyfinder's ranking; port its algorithm if the order feels off.
func fuzzyScore(_ query: String, _ text: String) -> Int? {
  let q = Array(query.lowercased())
  let t = Array(text.lowercased())
  var qi = 0
  var score = 0
  var previous = -2
  for (ti, c) in t.enumerated() where qi < q.count && c == q[qi] {
    score += 1
    if ti == previous + 1 { score += 5 }
    if ti == 0 || "/-_. ".contains(t[ti - 1]) { score += 3 }
    previous = ti
    qi += 1
  }
  return qi == q.count ? score : nil
}

/// Entries matching `query`, best first. Ties keep the configured order.
func fuzzyFilter(_ entries: [Entry], _ query: String) -> [Entry] {
  if query.isEmpty { return entries }
  return entries.enumerated()
    .compactMap { i, e in fuzzyScore(query, e.label).map { (i, e, $0) } }
    .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
    .map(\.1)
}
