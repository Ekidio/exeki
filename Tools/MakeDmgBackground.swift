// Renders the DMG window background. Usage: swift MakeDmgBackground.swift <out.png> <scale>
// Layout must match Tools/dmg-settings.py (window 680×460, icons at y=170).
import AppKit

let out = CommandLine.arguments[1]
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let W: CGFloat = 680, H: CGFloat = 460

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

/// Finder coordinates (origin top-left) → AppKit (origin bottom-left).
func y(_ top: CGFloat) -> CGFloat { H - top }

NSGradient(starting: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
           ending: NSColor(srgbRed: 0.95, green: 0.94, blue: 0.99, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

let ink = NSColor(srgbRed: 0.13, green: 0.12, blue: 0.2, alpha: 1)
let muted = NSColor(srgbRed: 0.4, green: 0.39, blue: 0.48, alpha: 1)
let accent = NSColor(srgbRed: 0.31, green: 0.27, blue: 0.9, alpha: 1)

func text(_ s: String, _ font: NSFont, _ color: NSColor, centerX: CGFloat? = nil, x: CGFloat = 0, top: CGFloat, width: CGFloat = 0) {
    let para = NSMutableParagraphStyle()
    para.lineSpacing = 2
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
    if let cx = centerX {
        let size = str.size()
        str.draw(at: NSPoint(x: cx - size.width / 2, y: y(top) - size.height))
    } else {
        let rect = str.boundingRect(with: NSSize(width: width, height: 200), options: [.usesLineFragmentOrigin])
        str.draw(with: NSRect(x: x, y: y(top) - rect.height, width: width, height: rect.height), options: [.usesLineFragmentOrigin])
    }
}

text("EXEKI", .systemFont(ofSize: 24, weight: .bold), ink, centerX: W / 2, top: 26)
text("Windows és DOS programok futtatása Macen", .systemFont(ofSize: 13), muted, centerX: W / 2, top: 60)

// Arrow from the app icon (x=180) to Applications (x=500), icon centres at y=170.
let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.move(to: NSPoint(x: 262, y: y(170)))
arrow.line(to: NSPoint(x: 410, y: y(170)))
accent.setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 420, y: y(170)))
head.line(to: NSPoint(x: 400, y: y(158)))
head.line(to: NSPoint(x: 400, y: y(182)))
head.close()
accent.setFill()
head.fill()

// Steps card.
let card = NSRect(x: 30, y: y(440), width: W - 60, height: 172)
NSColor.white.withAlphaComponent(0.85).setFill()
NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
NSColor(srgbRed: 0.85, green: 0.83, blue: 0.95, alpha: 1).setStroke()
let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
border.lineWidth = 1
border.stroke()

let steps: [(String, String)] = [
    ("1", "Húzd az EXEKI ikont az Alkalmazások mappába."),
    ("2", "Nyisd meg. Ha a Mac nem engedi, kattints a „Kész” gombra, majd:\nRendszerbeállítások → Adatvédelem és biztonság → görgess le →\n„Megnyitás mindenképp” (Open Anyway). Ezt csak egyszer kell."),
    ("3", "Kész! Első indításkor az app mindent magától beállít."),
]
var top: CGFloat = 288
for (number, body) in steps {
    let badge = NSRect(x: 52, y: y(top) - 22, width: 22, height: 22)
    accent.setFill()
    NSBezierPath(ovalIn: badge).fill()
    text(number, .systemFont(ofSize: 12, weight: .bold), .white, centerX: badge.midX, top: top + 3.5)
    text(body, .systemFont(ofSize: 13), ink, x: 88, top: top + 2, width: W - 140)
    top += body.contains("\n") ? 70 : 34
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
