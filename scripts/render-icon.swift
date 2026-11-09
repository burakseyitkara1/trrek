// Renders the trrek app icon (1024x1024 PNG) in the macOS 26 style: a rounded-square body on the standard icon
// grid with a deep blue gradient and a soft drop shadow, a frosted glass trackpad on it, and a glowing blue strip
// along the trackpad's right edge, with a specular highlight across the top of the body.
// Usage: swift scripts/render-icon.swift <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <out.png>\n".utf8))
    exit(2)
}

let size: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("cannot create bitmap context\n".utf8))
    exit(1)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [red, green, blue, alpha])!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

// The body sits on the standard 1024 grid: 824 points square, centred, slightly above centre to leave room for
// the shadow. Core Graphics has its origin at the bottom left.
let body = CGRect(x: 100, y: 108, width: 824, height: 824)
let bodyRadius: CGFloat = 186
let bodyPath = rounded(body, bodyRadius)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0, 0, 0, 0.38))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0.06, 0.09, 0.20))
ctx.fillPath()
ctx.restoreGState()

// Body: a deep blue to indigo gradient, top to bottom.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0.18, 0.44, 0.96), color(0.10, 0.22, 0.62), color(0.05, 0.10, 0.32)], [0, 0.55, 1]),
    start: CGPoint(x: body.midX, y: body.maxY),
    end: CGPoint(x: body.midX, y: body.minY),
    options: []
)
// A cool glow rising from behind the trackpad's right edge.
ctx.drawRadialGradient(
    gradient([color(0.30, 0.78, 1.0, 0.55), color(0.30, 0.78, 1.0, 0)], [0, 1]),
    startCenter: CGPoint(x: 760, y: 520), startRadius: 0,
    endCenter: CGPoint(x: 760, y: 520), endRadius: 420,
    options: []
)
ctx.restoreGState()

// The trackpad: a frosted glass slab with a light rim.
let pad = CGRect(x: 214, y: 300, width: 596, height: 424)
let padRadius: CGFloat = 64
let padPath = rounded(pad, padRadius)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0, 0, 0.12, 0.45))
ctx.addPath(padPath)
ctx.setFillColor(color(1, 1, 1, 0.18))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(padPath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0.86, 0.94, 1.0, 0.46), color(0.70, 0.84, 1.0, 0.20), color(0.60, 0.78, 1.0, 0.12)], [0, 0.55, 1]),
    start: CGPoint(x: pad.midX, y: pad.maxY),
    end: CGPoint(x: pad.midX, y: pad.minY),
    options: []
)
ctx.restoreGState()
// Rim: brighter along the top, where the light comes from.
ctx.saveGState()
ctx.addPath(padPath)
ctx.setLineWidth(5)
ctx.replacePathWithStrokedPath()
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(1, 1, 1, 0.85), color(1, 1, 1, 0.30)], [0, 1]),
    start: CGPoint(x: pad.midX, y: pad.maxY),
    end: CGPoint(x: pad.midX, y: pad.minY),
    options: []
)
ctx.restoreGState()

// The glowing right edge strip, inside the trackpad.
let strip = CGRect(x: pad.maxX - 92, y: pad.minY + 34, width: 58, height: pad.height - 68)
let stripPath = rounded(strip, 29)
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: color(0.25, 0.75, 1.0, 0.95))
ctx.addPath(stripPath)
ctx.setFillColor(color(0.25, 0.72, 1.0))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(stripPath)
ctx.clip()
ctx.drawLinearGradient(
    gradient([color(0.72, 0.93, 1.0), color(0.20, 0.62, 1.0)], [0, 1]),
    start: CGPoint(x: strip.midX, y: strip.maxY),
    end: CGPoint(x: strip.midX, y: strip.minY),
    options: []
)
ctx.restoreGState()

// A soft light from the top of the body (no hard edge), and a thin light rim around it.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawRadialGradient(
    gradient([color(1, 1, 1, 0.30), color(1, 1, 1, 0.08), color(1, 1, 1, 0)], [0, 0.45, 1]),
    startCenter: CGPoint(x: body.midX, y: body.maxY + 260), startRadius: 0,
    endCenter: CGPoint(x: body.midX, y: body.maxY + 260), endRadius: 760,
    options: []
)
ctx.restoreGState()
ctx.addPath(rounded(body.insetBy(dx: 2, dy: 2), bodyRadius - 2))
ctx.setStrokeColor(color(1, 1, 1, 0.24))
ctx.setLineWidth(4)
ctx.strokePath()

guard let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else {
    FileHandle.standardError.write(Data("cannot write the image\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("cannot write the image\n".utf8))
    exit(1)
}
