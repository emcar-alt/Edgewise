// Composes docs/images/hero.png from the popover snapshots.
//
//   build/Edgewise.app/Contents/MacOS/Edgewise --snapshot build/snapshots
//   swift scripts/make-readme-art.swift build/snapshots docs/images
import AppKit

let arguments = CommandLine.arguments.dropFirst()
let input = URL(fileURLWithPath: arguments.first ?? "build/snapshots")
let output = URL(fileURLWithPath: arguments.dropFirst().first ?? "docs/images")

func image(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: input.appendingPathComponent(name)) else { fatalError("missing \(name)") }
    return image
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let size = NSSize(width: 1600, height: 900)
let scale: CGFloat = 1
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: the icon's gradient, with rounded corners.
let canvas = NSRect(origin: .zero, size: size)
let clip = NSBezierPath(roundedRect: canvas, xRadius: 36, yRadius: 36)
clip.addClip()
NSGradient(colors: [color(0x3B2FD1), color(0x1C8FD6), color(0x2BD4C0)], atLocations: [0, 0.62, 1], colorSpace: .sRGB)!
    .draw(in: canvas, angle: -28)
NSGradient(colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)])!
    .draw(fromCenter: NSPoint(x: 800, y: 980), radius: 0, toCenter: NSPoint(x: 800, y: 980), radius: 900, options: [])

func drawShadowed(_ image: NSImage, in rect: NSRect, blur: CGFloat = 40, alpha: CGFloat = 0.35) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

// The snapshots include 24pt of transparent padding around the card.
let light = image("popover-linked-right-light.png")
let dark = image("popover-linked-left-dark.png")
let popoverHeight: CGFloat = 760
let popoverWidth = popoverHeight * light.size.width / light.size.height
drawShadowed(dark, in: NSRect(x: 1600 - 120 - popoverWidth, y: 70, width: popoverWidth, height: popoverHeight))
drawShadowed(light, in: NSRect(x: 600, y: 40, width: popoverWidth, height: popoverHeight))

// Title block on the left.
let icon = NSImage(contentsOf: output.deletingLastPathComponent().appendingPathComponent("logo.png"))!
drawShadowed(icon, in: NSRect(x: 76, y: 560, width: 200, height: 200), blur: 24, alpha: 0.25)
let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 4
NSAttributedString(string: "Edgewise", attributes: [
    .font: NSFont.systemFont(ofSize: 76, weight: .bold), .foregroundColor: NSColor.white,
]).draw(at: NSPoint(x: 96, y: 440))
NSAttributedString(string: "Your iPad, on whichever side\nyou put it.", attributes: [
    .font: NSFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.9), .paragraphStyle: paragraph,
]).draw(in: NSRect(x: 98, y: 300, width: 520, height: 120))
NSAttributedString(string: "Automatic left/right placement\nfor Universal Control.", attributes: [
    .font: NSFont.systemFont(ofSize: 24, weight: .regular), .foregroundColor: NSColor(white: 1, alpha: 0.75), .paragraphStyle: paragraph,
]).draw(in: NSRect(x: 98, y: 190, width: 520, height: 90))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("hero.png"))
print("wrote \(output.appendingPathComponent("hero.png").path)")
