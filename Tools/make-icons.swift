#!/usr/bin/env swift
// Renders the PuggleSlides app icon at every size macOS needs.
// Usage: swift Tools/make-icons.swift PuggleSlides/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outputFolder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Draws the icon in a 1024x1024 design space with a top-left origin.
func drawIcon() {
    // Body: light amber rounded square following the macOS icon grid (824pt body, 100pt margin).
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x7A4E00, 0.30)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0xFFE79A).setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xFFF2C6), ending: color(0xFFD873))!.draw(in: bodyPath, angle: 90)

    // White page with a folded corner, shifted right to leave room for the paw.
    let page = NSRect(x: 318, y: 206, width: 452, height: 592)
    let fold: CGFloat = 132
    let pagePath = NSBezierPath()
    pagePath.move(to: NSPoint(x: page.minX + 36, y: page.minY))
    pagePath.line(to: NSPoint(x: page.maxX - fold, y: page.minY))
    pagePath.line(to: NSPoint(x: page.maxX, y: page.minY + fold))
    pagePath.line(to: NSPoint(x: page.maxX, y: page.maxY - 36))
    pagePath.appendArc(withCenter: NSPoint(x: page.maxX - 36, y: page.maxY - 36), radius: 36, startAngle: 0, endAngle: 90)
    pagePath.line(to: NSPoint(x: page.minX + 36, y: page.maxY))
    pagePath.appendArc(withCenter: NSPoint(x: page.minX + 36, y: page.maxY - 36), radius: 36, startAngle: 90, endAngle: 180)
    pagePath.line(to: NSPoint(x: page.minX, y: page.minY + 36))
    pagePath.appendArc(withCenter: NSPoint(x: page.minX + 36, y: page.minY + 36), radius: 36, startAngle: 180, endAngle: 270)
    pagePath.close()
    NSGraphicsContext.saveGraphicsState()
    let pageShadow = NSShadow()
    pageShadow.shadowColor = color(0x7A4E00, 0.28)
    pageShadow.shadowBlurRadius = 20
    pageShadow.shadowOffset = NSSize(width: 0, height: -10)
    pageShadow.set()
    NSColor.white.setFill()
    pagePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: page.maxX - fold, y: page.minY))
    foldPath.line(to: NSPoint(x: page.maxX - fold, y: page.minY + fold - 28))
    foldPath.appendArc(withCenter: NSPoint(x: page.maxX - fold + 28, y: page.minY + fold - 28), radius: 28, startAngle: 180, endAngle: 90, clockwise: true)
    foldPath.line(to: NSPoint(x: page.maxX, y: page.minY + fold))
    foldPath.close()
    color(0xFFE8A6).setFill()
    foldPath.fill()

    // An amber slide: a landscape frame around a white screen with a title bar and a rising bar chart.
    let amber = color(0xF4A300)
    let slide = NSRect(x: page.minX + 50, y: page.minY + 196, width: page.width - 100, height: 252)
    amber.setFill()
    NSBezierPath(roundedRect: slide, xRadius: 22, yRadius: 22).fill()
    let screen = slide.insetBy(dx: 30, dy: 30)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: screen, xRadius: 8, yRadius: 8).fill()
    amber.setFill()
    NSBezierPath(roundedRect: NSRect(x: screen.minX + 24, y: screen.minY + 22, width: screen.width * 0.55, height: 26),
                 xRadius: 13, yRadius: 13).fill()
    let barWidth: CGFloat = 34, gap: CGFloat = 18
    let heights: [CGFloat] = [40, 70, 100]
    for (index, height) in heights.enumerated() {
        let x = screen.maxX - 24 - CGFloat(heights.count - index) * barWidth - CGFloat(heights.count - 1 - index) * gap
        color(index == 2 ? 0xF4A300 : (index == 1 ? 0xF8C24D : 0xFBD98A)).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: screen.maxY - 18 - height, width: barWidth, height: height), xRadius: 6, yRadius: 6).fill()
    }
    // The stand under the slide.
    amber.setFill()
    NSBezierPath(rect: NSRect(x: slide.midX - 10, y: slide.maxY, width: 20, height: 52)).fill()
    NSBezierPath(roundedRect: NSRect(x: slide.midX - 70, y: slide.maxY + 44, width: 140, height: 18), xRadius: 9, yRadius: 9).fill()

    // Paw print badge on the left, overlapping the page's lower-left corner.
    let center = NSPoint(x: 330, y: 716)
    let pads: [NSRect] = [
        NSRect(x: center.x - 92, y: center.y - 30, width: 184, height: 150),
        NSRect(x: center.x - 152, y: center.y - 112, width: 70, height: 88),
        NSRect(x: center.x - 82, y: center.y - 168, width: 72, height: 92),
        NSRect(x: center.x + 10, y: center.y - 168, width: 72, height: 92),
        NSRect(x: center.x + 82, y: center.y - 112, width: 70, height: 88),
    ]
    NSGraphicsContext.saveGraphicsState()
    let pawShadow = NSShadow()
    pawShadow.shadowColor = color(0x7C2D12, 0.25)
    pawShadow.shadowBlurRadius = 12
    pawShadow.shadowOffset = NSSize(width: 0, height: -6)
    pawShadow.set()
    NSColor.white.setFill()
    for pad in pads { NSBezierPath(ovalIn: pad.insetBy(dx: -18, dy: -18)).fill() }
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFB020).setFill()
    for pad in pads { NSBezierPath(ovalIn: pad).fill() }
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let transform = NSAffineTransform()
    transform.translateX(by: 0, yBy: CGFloat(size))
    transform.scaleX(by: CGFloat(size) / 1024, yBy: -CGFloat(size) / 1024)
    transform.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! render(size: points * scale).write(to: outputFolder.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outputFolder.appendingPathComponent("Contents.json"))
print("Wrote \(sizes.count) icons to \(outputFolder.path)")
