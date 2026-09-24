// Renders the 1024×1024 app icon PNG. Usage: swift MakeIcon.swift <output.png>
import AppKit

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt body centred on a 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(
    starting: NSColor(srgbRed: 0.42, green: 0.20, blue: 0.86, alpha: 1),
    ending: NSColor(srgbRed: 0.10, green: 0.45, blue: 0.95, alpha: 1)
)!.draw(in: shape, angle: -60)

// Window frame with a title bar, hinting at a Windows app.
let window = NSRect(x: 230, y: 420, width: 564, height: 380)
NSColor.white.withAlphaComponent(0.22).setFill()
NSBezierPath(roundedRect: window, xRadius: 36, yRadius: 36).fill()
NSColor.white.withAlphaComponent(0.35).setFill()
NSBezierPath(roundedRect: NSRect(x: window.minX, y: window.maxY - 80, width: window.width, height: 80),
             xRadius: 36, yRadius: 36).fill()

// Play triangle inside the window.
let play = NSBezierPath()
play.move(to: NSPoint(x: 455, y: 480))
play.line(to: NSPoint(x: 455, y: 700))
play.line(to: NSPoint(x: 625, y: 590))
play.close()
NSColor.white.setFill()
play.fill()

let label = NSAttributedString(string: "EXEKI", attributes: [
    .font: NSFont.systemFont(ofSize: 150, weight: .heavy),
    .foregroundColor: NSColor.white,
    .kern: 6,
])
let labelSize = label.size()
label.draw(at: NSPoint(x: (CGFloat(size) - labelSize.width) / 2, y: 175))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
