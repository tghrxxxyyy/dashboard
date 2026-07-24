import AppKit
import Foundation

/// 将十六进制 RGB 色值转换为 AppKit 颜色。
/// - Parameter value: 形如 `0xRRGGBB` 的色值。
/// - Returns: sRGB 色彩空间中的不透明颜色。
private func color(_ value: UInt32) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

/// 构造 Workbench 的前卫几何品牌图标。
/// - Parameter size: 母版画布边长。
/// - Returns: 带透明外边距的 macOS 应用图标。
private func makeWorkbenchIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: image.size).fill()

    let scale = size / 1024
    let baseRect = NSRect(x: 72 * scale, y: 72 * scale, width: 880 * scale, height: 880 * scale)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: 206 * scale, yRadius: 206 * scale)

    // 外投影仅用于在 Finder 与 Dock 背景上分离图标轮廓。
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.48)
    shadow.shadowBlurRadius = 34 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
    shadow.set()
    color(0x090C0A).setFill()
    basePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    color(0x090C0A).setFill()
    basePath.fill()
    color(0x303832).withAlphaComponent(0.78).setStroke()
    basePath.lineWidth = 2 * scale
    basePath.stroke()

    NSGraphicsContext.saveGraphicsState()
    basePath.addClip()

    // 低对比工程网格呼应应用内部的工作台画布。
    color(0xFFFFFF).withAlphaComponent(0.055).setStroke()
    for coordinate in stride(from: 160, through: 880, by: 120) {
        let vertical = NSBezierPath()
        vertical.move(to: NSPoint(x: CGFloat(coordinate) * scale, y: 90 * scale))
        vertical.line(to: NSPoint(x: CGFloat(coordinate) * scale, y: 934 * scale))
        vertical.lineWidth = 1 * scale
        vertical.stroke()

        let horizontal = NSBezierPath()
        horizontal.move(to: NSPoint(x: 90 * scale, y: CGFloat(coordinate) * scale))
        horizontal.line(to: NSPoint(x: 934 * scale, y: CGFloat(coordinate) * scale))
        horizontal.lineWidth = 1 * scale
        horizontal.stroke()
    }

    // 几何 W 使用大面积荧光绿，保证 16px 尺寸仍具有辨识度。
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 188 * scale, y: 702 * scale))
    mark.line(to: NSPoint(x: 306 * scale, y: 702 * scale))
    mark.line(to: NSPoint(x: 402 * scale, y: 408 * scale))
    mark.line(to: NSPoint(x: 486 * scale, y: 604 * scale))
    mark.line(to: NSPoint(x: 562 * scale, y: 604 * scale))
    mark.line(to: NSPoint(x: 654 * scale, y: 408 * scale))
    mark.line(to: NSPoint(x: 744 * scale, y: 702 * scale))
    mark.line(to: NSPoint(x: 854 * scale, y: 702 * scale))
    mark.line(to: NSPoint(x: 716 * scale, y: 312 * scale))
    mark.line(to: NSPoint(x: 620 * scale, y: 312 * scale))
    mark.line(to: NSPoint(x: 524 * scale, y: 500 * scale))
    mark.line(to: NSPoint(x: 430 * scale, y: 312 * scale))
    mark.line(to: NSPoint(x: 326 * scale, y: 312 * scale))
    mark.close()
    color(0xB0FF4F).setFill()
    mark.fill()

    // 珊瑚状态点与青色切线建立多色语义，不让图标退化为单一荧光色。
    color(0xFF645D).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 738 * scale, y: 744 * scale, width: 112 * scale, height: 112 * scale),
        xRadius: 34 * scale,
        yRadius: 34 * scale
    ).fill()

    color(0x38E1FF).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 184 * scale, y: 226 * scale, width: 350 * scale, height: 25 * scale),
        xRadius: 12.5 * scale,
        yRadius: 12.5 * scale
    ).fill()
    NSBezierPath(
        roundedRect: NSRect(x: 558 * scale, y: 226 * scale, width: 94 * scale, height: 25 * scale),
        xRadius: 12.5 * scale,
        yRadius: 12.5 * scale
    ).fill()

    NSGraphicsContext.restoreGraphicsState()
    return image
}

/// 将 AppKit 图像编码为 PNG 母版。
/// - Parameters:
///   - image: 要编码的应用图标。
///   - destination: PNG 输出地址。
private func writePNG(_ image: NSImage, to destination: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiffData),
          let pngData = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try pngData.write(to: destination, options: [.atomic])
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("用法：swift GenerateAppIcon.swift <output.png>\n".utf8))
    exit(64)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
do {
    try writePNG(makeWorkbenchIcon(size: 1024), to: destination)
} catch {
    FileHandle.standardError.write(Data("生成应用图标失败：\(error.localizedDescription)\n".utf8))
    exit(1)
}
