import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let base = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 212, yRadius: 212)
        NSColor(white: 0.12, alpha: 1).setFill()
        base.fill()
        let rear = NSBezierPath(roundedRect: NSRect(x: 210, y: 300, width: 540, height: 440), xRadius: 48, yRadius: 48)
        NSColor(white: 0.4, alpha: 1).setFill()
        rear.fill()
        let card = NSBezierPath(roundedRect: NSRect(x: 274, y: 230, width: 540, height: 440), xRadius: 48, yRadius: 48)
        NSColor(white: 0.94, alpha: 1).setFill()
        card.fill()
        NSColor(white: 0.18, alpha: 1).setStroke()
        let line = NSBezierPath()
        line.lineWidth = 30
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 380, y: 495))
        line.line(to: NSPoint(x: 704, y: 495))
        line.move(to: NSPoint(x: 380, y: 405))
        line.line(to: NSPoint(x: 580, y: 405))
        line.stroke()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not render application icon")
        }
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png.write(to: output.appendingPathComponent(name))
    }
}
