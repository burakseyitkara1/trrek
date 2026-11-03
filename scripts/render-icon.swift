// Renders the trrek app icon (1024x1024 PNG): a dark rounded square, a lighter grey
// trackpad silhouette, and a bright blue strip along the trackpad's right edge.
// Usage: swift scripts/render-icon.swift <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <out.png>\n".utf8))
    exit(2)
}

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("cannot create bitmap context\n".utf8))
    exit(1)
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ path: CGPath, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
    ctx.setFillColor(CGColor(colorSpace: colorSpace, components: [red, green, blue, 1])!)
    ctx.addPath(path)
    ctx.fillPath()
}

// Background: dark rounded square.
let background = CGRect(x: 0, y: 0, width: size, height: size)
fill(rounded(background, 228), 0.09, 0.10, 0.12)

// Trackpad silhouette: lighter grey rounded rectangle, centered.
let pad = CGRect(x: 192, y: 262, width: 640, height: 500)
let padPath = rounded(pad, 72)
fill(padPath, 0.62, 0.64, 0.68)

// Bright blue vertical strip on the trackpad's right edge, clipped to the silhouette.
ctx.saveGState()
ctx.addPath(padPath)
ctx.clip()
let strip = CGRect(x: pad.maxX - 112, y: pad.minY, width: 112, height: pad.height)
fill(CGPath(rect: strip, transform: nil), 0.10, 0.52, 1.0)
ctx.restoreGState()

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL,
          UTType.png.identifier as CFString, 1, nil
      )
else {
    FileHandle.standardError.write(Data("cannot create image destination\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("cannot write png\n".utf8))
    exit(1)
}
