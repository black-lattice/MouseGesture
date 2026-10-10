// Reuse the cursor symbol and teal accent from the settings window.
// Run: swift scripts/generate-icon.swift /tmp/MouseGesture.iconset
// Then: iconutil -c icns /tmp/MouseGesture.iconset -o Resources/AppIcon.icns
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard let symbol = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 580, weight: .regular)) else {
    fatalError("缺少鼠标手势图标")
}
let teal = NSColor(srgbRed: 0.02, green: 0.82, blue: 0.86, alpha: 1)
let tinted = NSImage(size: symbol.size)
tinted.lockFocus()
symbol.draw(in: NSRect(origin: .zero, size: symbol.size))
teal.setFill()
NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
tinted.unlockFocus()

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184)
        NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.22, blue: 0.27, alpha: 1),
                   ending: NSColor(srgbRed: 0.06, green: 0.09, blue: 0.13, alpha: 1))!.draw(in: tile, angle: -90)
        let ratio = min(580 / symbol.size.width, 580 / symbol.size.height)
        let width = symbol.size.width * ratio
        let height = symbol.size.height * ratio
        tinted.draw(in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
