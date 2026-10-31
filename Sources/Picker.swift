import SwiftUI

@MainActor
@Observable
final class PickerModel {
  var entries: [Entry] = [] {
    didSet { filtered = fuzzyFilter(entries, query) }
  }

  var configDir = ""
  var backend = ""
  var query = "" {
    // Return re-commits the same text; only a real edit refilters and resets the selection
    didSet {
      guard query != oldValue else { return }
      filtered = fuzzyFilter(entries, query)
      selection = 0
    }
  }

  var selection = 0
  var error: String?
  private(set) var filtered: [Entry] = []

  func move(_ delta: Int) {
    let count = filtered.count
    guard count > 0 else { return }
    selection = (selection + delta + count) % count
  }

  func open() {
    let matches = filtered
    guard matches.indices.contains(selection) else { return }
    do {
      if backend == "rex" {
        try openRexEntry(matches[selection], configDir: configDir)
      } else {
        try openEntry(matches[selection], configDir: configDir)
      }
      exit(0)
    } catch {
      self.error = "\(error)"
    }
  }
}

/// Gruvbox dark, hard contrast.
enum Gruvbox {
  static let bg = Color(red: 0x1D / 255, green: 0x20 / 255, blue: 0x21 / 255)
  static let fg = Color(red: 0xEB / 255, green: 0xDB / 255, blue: 0xB2 / 255)
  static let gray = Color(red: 0x92 / 255, green: 0x83 / 255, blue: 0x74 / 255)
  static let yellow = Color(red: 0xFA / 255, green: 0xBD / 255, blue: 0x2F / 255)
  static let orange = Color(red: 0xFE / 255, green: 0x80 / 255, blue: 0x19 / 255)
  static let red = Color(red: 0xFB / 255, green: 0x49 / 255, blue: 0x34 / 255)
}

/// Fits the search field and 8 visible rows; further matches scroll.
let pickerSize = NSSize(width: 560, height: 450)

struct PickerView: View {
  @Bindable var model: PickerModel
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField("", text: $model.query, prompt: Text("Open a session").foregroundStyle(Gruvbox.gray))
        .textFieldStyle(.plain)
        .font(.system(size: 28))
        .foregroundStyle(Gruvbox.fg)
        .tint(Gruvbox.orange)
        .padding(20)
        .focused($focused)
        .onSubmit { model.open() }
        .onKeyPress(.upArrow) { model.move(-1); return .handled }
        .onKeyPress(.downArrow) { model.move(1); return .handled }
        .onExitCommand { exit(0) }

      if let error = model.error {
        Text(error)
          .foregroundStyle(Gruvbox.red)
          .padding(.horizontal, 18)
          .padding(.bottom, 8)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(Array(model.filtered.enumerated()), id: \.element.path) { i, entry in
              row(entry, selected: i == model.selection)
                .onTapGesture {
                  model.selection = i
                  model.open()
                }
            }
          }
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        // rows are identified by path; an extra `.id(index)` made LazyVStack keep stale rows
        .onChange(of: model.selection) { _, i in
          if model.filtered.indices.contains(i) { proxy.scrollTo(model.filtered[i].path) }
        }
      }
    }
    .frame(width: pickerSize.width, height: pickerSize.height)
    // a dark tint keeps the text readable over bright windows
    .glassEffect(.regular.tint(Gruvbox.bg.opacity(0.6)), in: .rect(cornerRadius: 26))
    .onAppear {
      focused = true
      logTiming("first frame")
    }
  }

  private func row(_ entry: Entry, selected: Bool) -> some View {
    HStack {
      Text(entry.label)
        .font(.system(size: 20))
        .foregroundStyle(selected ? Gruvbox.yellow : Gruvbox.fg)
      Spacer()
      Text(entry.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        .font(.system(size: 15))
        .foregroundStyle(Gruvbox.gray)
        .lineLimit(1)
        .truncationMode(.head)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(
      selected ? Gruvbox.yellow.opacity(0.15) : .clear,
      in: .rect(cornerRadius: 12)
    )
    .contentShape(.rect)
  }
}
