// Generates App/Assets.xcassets/AppIcon.appiconset from code, so the icon is
// reproducible and reviewable: `swift tools/make-icon.swift`.
// Design: a day on a track. Indigo-to-violet tile, three lanes (sleep, work,
// nature's call) as rounded bars, food as dots, and a "now" line.
import AppKit
import CoreGraphics

let out = URL(filePath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    // macOS icon grid: 824×824 tile centred, ~185 corner radius, soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(color(0x3B2F9E))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x5B4BE0), color(0x7A3CC8), color(0x2A1F6E)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    // Glass sheen on the top half.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    // Lanes.
    func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: CGColor) {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
        ctx.setFillColor(c)
        ctx.fillPath()
    }
    bar(190, 650, 300, 70, color(0xE7C6FF))           // sleep
    bar(540, 520, 220, 70, color(0xFFFFFF))           // work
    bar(250, 520, 230, 70, color(0xFFFFFF, 0.92))     // work
    bar(495, 395, 110, 70, color(0x7FE3E0))            // nature's call
    for x: CGFloat in [300, 470, 650, 760] {          // food
        ctx.addEllipse(in: CGRect(x: x - 22, y: 268, width: 44, height: 44))
        ctx.setFillColor(color(0xFFB65C))
        ctx.fillPath()
    }
    // "Now" line.
    ctx.setStrokeColor(color(0xFF6B6B))
    ctx.setLineWidth(12)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 600, y: 230))
    ctx.addLine(to: CGPoint(x: 600, y: 760))
    ctx.strokePath()
    ctx.restoreGState()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(points * scale).write(to: out.appending(path: name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: out.appending(path: "Contents.json"))
let catalog = out.deletingLastPathComponent().appending(path: "Contents.json")
if !FileManager.default.fileExists(atPath: catalog.path) {
    try Data(#"{"info":{"author":"xcode","version":1}}"#.utf8).write(to: catalog)
}
print("wrote \(images.count) icon images to \(out.path)")
