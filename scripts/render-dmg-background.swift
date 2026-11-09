// Renders the background of trrek's disk image window (640x400 points): a soft light gradient, a chevron from where
// the app sits to where the Applications shortcut sits, and a short instruction below. Writes a 1x and a 2x PNG.
// Usage: swift scripts/render-dmg-background.swift <out-1x.png> <out-2x.png>
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: render-dmg-background.swift <out-1x.png> <out-2x.png>\n".utf8))
    exit(2)
}

/// The window's layout in points, from the top left; `scripts/make-dmg-layout.sh` places the icons at these centres.
let width: CGFloat = 640
let height: CGFloat = 400
let appCentre = CGPoint(x: 160, y: 190)
let applicationsCentre = CGPoint(x: 480, y: 190)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [red, green, blue, alpha])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

/// A light, slightly cool vertical gradient with a soft halo behind each icon.
func drawBackdrop(_ ctx: CGContext) {
    ctx.drawLinearGradient(
        gradient([color(0.975, 0.978, 0.985), color(0.918, 0.926, 0.942)], [0, 1]),
        start: .zero, end: CGPoint(x: 0, y: height), options: []
    )
    for centre in [appCentre, applicationsCentre] {
        ctx.drawRadialGradient(
            gradient([color(1, 1, 1, 0.9), color(1, 1, 1, 0)], [0, 1]),
            startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 120, options: []
        )
    }
}

/// The chevron between the two icons.
func drawChevron(_ ctx: CGContext) {
    let mid = CGPoint(x: (appCentre.x + applicationsCentre.x) / 2, y: appCentre.y)
    ctx.setStrokeColor(color(0.20, 0.22, 0.26, 0.85))
    ctx.setLineWidth(9)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: mid.x - 14, y: mid.y - 30))
    ctx.addLine(to: CGPoint(x: mid.x + 16, y: mid.y))
    ctx.addLine(to: CGPoint(x: mid.x - 14, y: mid.y + 30))
    ctx.strokePath()
}

/// The instruction under the icons, centred.
func drawInstruction(_ ctx: CGContext) {
    let font = CTFontCreateUIFontForLanguage(.system, 14, nil)!
    let attributes = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color(0.42, 0.44, 0.48)
    ] as CFDictionary
    let text = CFAttributedStringCreate(nil, "Drag trrek to Applications" as CFString, attributes)!
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.saveGState()
    ctx.translateBy(x: (width - bounds.width) / 2 - bounds.minX, y: 352)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func render(scale: CGFloat, to path: String) {
    guard let ctx = CGContext(
        data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }
    ctx.scaleBy(x: scale, y: scale)
    // Top-left origin, as Finder positions icons from the top left.
    ctx.translateBy(x: 0, y: height)
    ctx.scaleBy(x: 1, y: -1)
    drawBackdrop(ctx)
    drawChevron(ctx)
    drawInstruction(ctx)

    guard let image = ctx.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
          )
    else { exit(1) }
    let dpi = 72 * scale
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
}

render(scale: 1, to: CommandLine.arguments[1])
render(scale: 2, to: CommandLine.arguments[2])
