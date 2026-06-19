#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let size = 1024

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-icon.swift /path/to/output.png\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255.0
    let green = CGFloat((hex >> 8) & 0xff) / 255.0
    let blue = CGFloat(hex & 0xff) / 255.0
    return CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawPhone(
    in context: CGContext,
    center: CGPoint,
    width: CGFloat,
    height: CGFloat,
    angle: CGFloat,
    accentY: CGFloat = 0.30
) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: angle)

    let body = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let bodyPath = roundedRect(body, radius: width * 0.24)

    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: color(0x000000, alpha: 0.35))
    context.setFillColor(color(0xf6f7fb, alpha: 0.96))
    context.addPath(bodyPath)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    context.setStrokeColor(color(0xffffff, alpha: 0.82))
    context.setLineWidth(7)
    context.addPath(bodyPath)
    context.strokePath()

    let screen = body.insetBy(dx: width * 0.16, dy: height * 0.14)
    context.setFillColor(color(0x101116, alpha: 0.88))
    context.addPath(roundedRect(screen, radius: width * 0.14))
    context.fillPath()

    let accent = CGRect(
        x: screen.minX + width * 0.12,
        y: screen.minY + screen.height * accentY,
        width: screen.width - width * 0.24,
        height: max(8, height * 0.045)
    )
    context.setFillColor(color(0x0A84FF, alpha: 0.95))
    context.addPath(roundedRect(accent, radius: accent.height / 2))
    context.fillPath()

    let speaker = CGRect(x: -width * 0.16, y: body.maxY - height * 0.11, width: width * 0.32, height: 7)
    context.setFillColor(color(0xd7dbe4, alpha: 0.85))
    context.addPath(roundedRect(speaker, radius: 3.5))
    context.fillPath()

    context.restoreGState()
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let graphicsContext = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = graphicsContext

let context = graphicsContext.cgContext
let bounds = CGRect(x: 0, y: 0, width: size, height: size)
context.clear(bounds)
context.interpolationQuality = .high
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let iconRect = bounds.insetBy(dx: 42, dy: 42)
let iconPath = roundedRect(iconRect, radius: 222)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 48, color: color(0x000000, alpha: 0.50))
context.setFillColor(color(0x000000, alpha: 1.0))
context.addPath(iconPath)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(iconPath)
context.clip()

let background = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x1C1C1F), color(0x07080A), color(0x000000)] as CFArray,
    locations: [0.0, 0.46, 1.0]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: bounds.midX, y: bounds.maxY),
    end: CGPoint(x: bounds.midX, y: bounds.minY),
    options: []
)

let blueGlow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x0A84FF, alpha: 0.48), color(0x0A84FF, alpha: 0.12), color(0x0A84FF, alpha: 0.0)] as CFArray,
    locations: [0.0, 0.42, 1.0]
)!
context.drawRadialGradient(
    blueGlow,
    startCenter: CGPoint(x: 512, y: 675),
    startRadius: 18,
    endCenter: CGPoint(x: 512, y: 655),
    endRadius: 440,
    options: [.drawsAfterEndLocation]
)

let topLight = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xffffff, alpha: 0.17), color(0xffffff, alpha: 0.00)] as CFArray,
    locations: [0.0, 1.0]
)!
context.drawLinearGradient(
    topLight,
    start: CGPoint(x: 512, y: 948),
    end: CGPoint(x: 512, y: 480),
    options: []
)

let center = CGPoint(x: 512, y: 512)
let phones: [(CGPoint, CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (CGPoint(x: 512, y: 742), 112, 184, 0.0, 0.25),
    (CGPoint(x: 280, y: 535), 106, 176, -0.40, 0.54),
    (CGPoint(x: 744, y: 535), 106, 176, 0.40, 0.54),
    (CGPoint(x: 512, y: 286), 108, 178, .pi, 0.30)
]

context.setStrokeColor(color(0xcfd5df, alpha: 0.78))
context.setLineWidth(16)
context.setLineCap(.round)
context.setLineJoin(.round)
for phone in phones {
    context.move(to: center)
    let target = CGPoint(
        x: center.x + (phone.0.x - center.x) * 0.72,
        y: center.y + (phone.0.y - center.y) * 0.72
    )
    context.addLine(to: target)
    context.strokePath()
}

context.setStrokeColor(color(0x0A84FF, alpha: 0.72))
context.setLineWidth(6)
for phone in phones {
    context.move(to: center)
    let target = CGPoint(
        x: center.x + (phone.0.x - center.x) * 0.58,
        y: center.y + (phone.0.y - center.y) * 0.58
    )
    context.addLine(to: target)
    context.strokePath()
}

for phone in phones {
    drawPhone(in: context, center: phone.0, width: phone.1, height: phone.2, angle: phone.3, accentY: phone.4)
}

let outerNode = CGRect(x: center.x - 80, y: center.y - 80, width: 160, height: 160)
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 32, color: color(0x0A84FF, alpha: 0.38))
context.setFillColor(color(0x0A84FF, alpha: 0.98))
context.addPath(roundedRect(outerNode, radius: 46))
context.fillPath()
context.setShadow(offset: .zero, blur: 0, color: nil)

let innerNode = CGRect(x: center.x - 41, y: center.y - 41, width: 82, height: 82)
context.setFillColor(color(0xf8fbff, alpha: 0.98))
context.addEllipse(in: innerNode)
context.fillPath()

context.setStrokeColor(color(0xffffff, alpha: 0.28))
context.setLineWidth(4)
context.addPath(iconPath)
context.strokePath()

context.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}

do {
    try data.write(to: outputURL, options: .atomic)
} catch {
    fputs("failed to write \(outputURL.path): \(error)\n", stderr)
    exit(1)
}
