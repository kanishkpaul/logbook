// Generates App/Assets.xcassets/AppIcon.appiconset from code, so the icon is
// reproducible and reviewable: `swift tools/make-icon.swift`.
// Design: a monogram L built from the day's blocks, on graphite. The upright
// is sleep (indigo), the foot is work (amber) then a break (teal), and the
// coral dot is "now". Same colours as the app's lanes.
import AppKit
import CoreGraphics

let out = URL(filePath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Superellipse tile on the macOS grid (824 px in a 1024 canvas).
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = r.midY + r.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)
    func linear(_ colors: [CGColor], _ from: CGPoint, _ to: CGPoint) {
        let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    /// A rounded block with a soft top highlight, so it reads as a shape, not a sticker.
    func block(_ r: CGRect, _ c: UInt32) {
        let path = CGPath(roundedRect: r, cornerWidth: min(r.width, r.height) / 2, cornerHeight: min(r.width, r.height) / 2, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: color(0x000000, 0.35))
        ctx.addPath(path); ctx.setFillColor(color(c)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        linear([color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)], CGPoint(x: 0, y: r.maxY), CGPoint(x: 0, y: r.midY))
        ctx.restoreGState()
    }
    // Tile with a soft drop shadow.
    let tile = squircle(CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.4))
    ctx.addPath(tile); ctx.setFillColor(color(0x1B1C24)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    linear([color(0x2C2F3D), color(0x14151C)], CGPoint(x: 0, y: 924), CGPoint(x: 0, y: 100))
    linear([color(0xFFFFFF, 0.08), color(0xFFFFFF, 0)], CGPoint(x: 0, y: 924), CGPoint(x: 0, y: 640))
    // The L: upright = sleep, foot = work then a break; the dot is now.
    let t: CGFloat = 150, x0: CGFloat = 270, y0: CGFloat = 250
    block(CGRect(x: x0, y: y0 + t + 22, width: t, height: 390), 0x6267F0)
    block(CGRect(x: x0, y: y0, width: 300, height: t), 0xF5A524)
    block(CGRect(x: x0 + 322, y: y0, width: 150, height: t), 0x2EC4B6)
    block(CGRect(x: 638, y: 498, width: 124, height: 124), 0xFF6B5B)
    // Hairline rim.
    ctx.addPath(tile); ctx.setStrokeColor(color(0xFFFFFF, 0.08)); ctx.setLineWidth(4); ctx.strokePath()
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
