// Renders the 1024 px app icon: an italic s on the selected row of a list, on a Gruvbox squircle.
// Usage: swift Scripts/icon.swift <out.png> <MapleMonoNormal-NF-Italic.ttf>
import AppKit

func gruvbox(_ hex: Int, _ alpha: Double = 1) -> NSColor {
  NSColor(
    red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
    blue: Double(hex & 0xFF) / 255, alpha: alpha
  )
}

let fontName = "MapleMonoNormal-NF-Italic"
// registered for this process only, so the font need not be installed
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, .process, nil)
// Core Text silently substitutes a missing font, which would ship the wrong letter
guard CTFontCopyPostScriptName(CTFontCreateWithName(fontName as CFString, 100, nil)) as String == fontName
else { fatalError("font \(fontName) did not load from \(CommandLine.arguments[2])") }

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
  // the macOS icon grid: an 824 px rounded square centred in the 1024 canvas
  let squircle = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185
  )
  NSGradient(starting: gruvbox(0x3C3836), ending: gruvbox(0x1D2021))!.draw(in: squircle, angle: -90)

  // list rows, the middle one selected like in the picker
  for (i, y) in stride(from: 250.0, through: 730, by: 120).enumerated() {
    let row = NSBezierPath(
      roundedRect: NSRect(x: 220, y: y, width: 584, height: 44), xRadius: 22, yRadius: 22
    )
    (i == 2 ? gruvbox(0xFABD2F, 0.28) : gruvbox(0x504945, 0.9)).setFill()
    row.fill()
  }

  // the glyph outline, scaled so its ink fills a 280 px box centred on the yellow row
  let font = CTFontCreateWithName(fontName as CFString, 100, nil)
  var glyph = CGGlyph()
  CTFontGetGlyphsForCharacters(font, Array("s".utf16), &glyph, 1)
  let outline = CTFontCreatePathForGlyph(font, glyph, nil)!
  let ink = outline.boundingBoxOfPath
  let scale = 280 / max(ink.width, ink.height)
  var transform = CGAffineTransform(translationX: size / 2, y: size / 2)
    .scaledBy(x: scale, y: scale)
    .translatedBy(x: -ink.midX, y: -ink.midY)
  let path = outline.copy(using: &transform)!

  let cg = NSGraphicsContext.current!.cgContext
  cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: gruvbox(0x1D2021, 0.8).cgColor)
  cg.addPath(path)
  cg.setFillColor(gruvbox(0xFABD2F).cgColor)
  cg.fillPath()
  return true
}

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
  .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
