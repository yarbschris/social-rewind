// Draws the 1024×1024 app icon: two rounded "rewind" chevrons on a flat background.
// Run from the repo root:  swift scripts/make-app-icon.swift
// Writes ios/SocialRewind/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png (opaque, no alpha).
import AppKit

let size = 1024
let out = "ios/SocialRewind/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Couldn't create the bitmap context")
}

// Background: deep teal, slightly lighter towards the top.
let gradient = CGGradient(colorsSpace: space, colors: [color(0x2A6B78), color(0x173F4A)] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

/// A left-pointing triangle with rounded corners, its tip at `tipX`.
func chevron(tipX: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat) -> CGPath {
    let midY = CGFloat(size) / 2
    let tip = CGPoint(x: tipX, y: midY)
    let top = CGPoint(x: tipX + width, y: midY + height / 2)
    let bottom = CGPoint(x: tipX + width, y: midY - height / 2)
    let path = CGMutablePath()
    path.move(to: CGPoint(x: (top.x + bottom.x) / 2, y: (top.y + bottom.y) / 2))
    path.addArc(tangent1End: top, tangent2End: tip, radius: radius)
    path.addArc(tangent1End: tip, tangent2End: bottom, radius: radius)
    path.addArc(tangent1End: bottom, tangent2End: top, radius: radius)
    path.closeSubpath()
    return path
}

let width: CGFloat = 330, height: CGFloat = 430, radius: CGFloat = 56
// Two chevrons, overlapping a little. Each one's visual weight sits towards its flat side, so the
// pair is nudged left of geometric centre to look centred.
let pairWidth = width * 2 - 70
let left = (CGFloat(size) - pairWidth) / 2 - 36
ctx.setFillColor(color(0xF4EBDD))
ctx.addPath(chevron(tipX: left, width: width, height: height, radius: radius))
ctx.fillPath()
ctx.addPath(chevron(tipX: left + width - 70, width: width, height: height, radius: radius))
ctx.fillPath()

guard let image = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("Couldn't encode the PNG")
}
try FileManager.default.createDirectory(atPath: (out as NSString).deletingLastPathComponent,
                                        withIntermediateDirectories: true)
try png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
