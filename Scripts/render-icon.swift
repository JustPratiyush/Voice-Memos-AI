import AppKit
import Foundation

// Original vector-drawn artwork. No artwork is copied from Apple's bundle.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let asset = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int, to url: URL, transparent: Bool = false) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.bitmapData!.initialize(repeating: 0, count: bitmap.bytesPerRow * pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    let bounds = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
    if !transparent { bounds.fill() }
    let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 34, dy: 34), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(calibratedWhite: 0.22, alpha: 1),
               ending: NSColor(calibratedWhite: 0.065, alpha: 1))!.draw(in: card, angle: -90)
    NSColor(white: 1, alpha: 0.13).setStroke()
    card.lineWidth = 2; card.stroke()
    for index in 0..<51 {
        let x = CGFloat(112 + index * 16)
        let distance = abs(index - 25)
        let envelope = (0.2 + abs(sin(Double(index) * 1.71)) * 0.8)
        let taper = 1 - Double(distance) / 33
        let height = CGFloat(30 + envelope * taper * 470)
        let line = NSBezierPath()
        line.move(to: NSPoint(x: x, y: 512 - height / 2))
        line.line(to: NSPoint(x: x, y: 512 + height / 2))
        line.lineWidth = 7
        line.lineCapStyle = .round
        (distance <= 5 ? NSColor.systemRed : NSColor(calibratedWhite: 0.94, alpha: 0.9)).setStroke()
        line.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    if transparent {
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    } else {
        // AppKit draws into RGBA; strip the alpha channel for iOS App Store icons.
        let opaque = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<pixels {
            for x in 0..<pixels {
                for channel in 0..<3 {
                    opaque.bitmapData![y * opaque.bytesPerRow + x * 3 + channel] =
                        bitmap.bitmapData![y * bitmap.bytesPerRow + x * 4 + channel]
                }
            }
        }
        try opaque.representation(using: .png, properties: [:])!.write(to: url)
    }
}

var images: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(size * scale, to: asset.appendingPathComponent(filename), transparent: true)
        try Data(contentsOf: asset.appendingPathComponent(filename)).write(to: iconset.appendingPathComponent(filename))
        images.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
for (idiom, sizes, scales) in [
    ("iphone", [20.0, 29, 40, 60], [2, 3]),
    ("ipad", [20.0, 29, 40, 76], [1, 2])
] {
    for size in sizes {
        for scale in scales {
            let length = String(format: "%.0f", size)
            let filename = "\(idiom)_\(length)@\(scale)x.png"
            try render(Int(size * Double(scale)), to: asset.appendingPathComponent(filename))
            images.append(["idiom": idiom, "size": "\(length)x\(length)", "scale": "\(scale)x", "filename": filename])
        }
    }
}
try render(167, to: asset.appendingPathComponent("ipad_83.5@2x.png"))
images.append(["idiom": "ipad", "size": "83.5x83.5", "scale": "2x", "filename": "ipad_83.5@2x.png"])
try render(1024, to: asset.appendingPathComponent("marketing.png"))
images.append(["idiom": "ios-marketing", "size": "1024x1024", "scale": "1x", "filename": "marketing.png"])
let manifest: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: asset.appendingPathComponent("Contents.json"))
try Data("{\"info\":{\"author\":\"xcode\",\"version\":1}}".utf8)
    .write(to: asset.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("Rendered original icon assets.")
