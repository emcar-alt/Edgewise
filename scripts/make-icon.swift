// Renders the Edgewise app icon.
//
//   swift scripts/make-icon.swift Resources   # writes Resources/AppIcon.icns and docs/logo.png
import AppKit

let outputFolder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")
let docsFolder = outputFolder.deletingLastPathComponent().appendingPathComponent("docs")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws the icon into a 1024×1024 coordinate space (origin bottom-left).
func drawIcon(in context: CGContext) {
    // Body: the macOS icon grid's 824pt squircle-ish tile with a drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = roundedRect(body, 186)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.28))
    context.addPath(bodyPath)
    context.setFillColor(color(0x1B1F3B))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x3B2FD1), color(0x1C8FD6), color(0x2BD4C0)] as CFArray,
                              locations: [0, 0.6, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 160, y: 924), end: CGPoint(x: 880, y: 120), options: [])
    // Soft light from the top.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0, endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])
    context.restoreGState()

    let white = color(0xFFFFFF)

    // Laptop, centred slightly left.
    let screen = CGRect(x: 238, y: 432, width: 400, height: 270)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x0A0F2E, 0.35))
    context.addPath(roundedRect(screen, 26))
    context.setFillColor(white)
    context.fillPath()
    context.addPath(roundedRect(CGRect(x: 196, y: 388, width: 484, height: 34), 17))
    context.fillPath()
    context.restoreGState()
    // Display glass.
    context.addPath(roundedRect(screen.insetBy(dx: 22, dy: 22), 10))
    context.setFillColor(color(0x23286B))
    context.fillPath()
    // A pointer on the glass, heading for the right edge.
    let pointer = CGMutablePath()
    pointer.move(to: CGPoint(x: 540, y: 628))
    pointer.addLine(to: CGPoint(x: 540, y: 532))
    pointer.addLine(to: CGPoint(x: 563, y: 554))
    pointer.addLine(to: CGPoint(x: 580, y: 518))
    pointer.addLine(to: CGPoint(x: 595, y: 525))
    pointer.addLine(to: CGPoint(x: 578, y: 561))
    pointer.addLine(to: CGPoint(x: 610, y: 561))
    pointer.closeSubpath()
    context.addPath(pointer)
    context.setFillColor(white)
    context.setStrokeColor(color(0x23286B))
    context.setLineWidth(7)
    context.setLineJoin(.round)
    context.drawPath(using: .fillStroke)

    // iPad on the right, docked to the laptop's edge.
    let pad = CGRect(x: 690, y: 412, width: 150, height: 210)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x0A0F2E, 0.35))
    context.addPath(roundedRect(pad, 24))
    context.setFillColor(white)
    context.fillPath()
    context.restoreGState()
    context.addPath(roundedRect(pad.insetBy(dx: 14, dy: 14), 12))
    context.setFillColor(color(0x23286B))
    context.fillPath()

    // Arc arrow sweeping over the laptop and landing on the iPad.
    let start = CGPoint(x: 236, y: 758), control = CGPoint(x: 480, y: 912), end = CGPoint(x: 712, y: 752)
    var direction = CGVector(dx: end.x - control.x, dy: end.y - control.y)
    let length = (direction.dx * direction.dx + direction.dy * direction.dy).squareRoot()
    direction = CGVector(dx: direction.dx / length, dy: direction.dy / length)
    let normal = CGVector(dx: -direction.dy, dy: direction.dx)
    let tip = CGPoint(x: end.x + direction.dx * 70, y: end.y + direction.dy * 70)

    context.saveGState()
    context.setAlpha(0.94)
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setStrokeColor(white)
    context.setFillColor(white)
    context.setLineWidth(28)
    context.setLineCap(.round)
    let arc = CGMutablePath()
    arc.move(to: start)
    arc.addQuadCurve(to: end, control: control)
    context.addPath(arc)
    context.strokePath()
    let head = CGMutablePath()
    head.move(to: tip)
    head.addLine(to: CGPoint(x: end.x + normal.dx * 52 - direction.dx * 12, y: end.y + normal.dy * 52 - direction.dy * 12))
    head.addLine(to: CGPoint(x: end.x - normal.dx * 52 - direction.dx * 12, y: end.y - normal.dy * 52 - direction.dy * 12))
    head.closeSubpath()
    context.addPath(head)
    context.setLineJoin(.round)
    context.setLineWidth(14)
    context.drawPath(using: .fillStroke)
    context.endTransparencyLayer()
    context.restoreGState()
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputFolder.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.createDirectory(at: docsFolder, withIntermediateDirectories: true)
try render(size: 512).write(to: docsFolder.appendingPathComponent("logo.png"))
print("wrote \(outputFolder.appendingPathComponent("AppIcon.icns").path) and docs/logo.png")
