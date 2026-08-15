// 生成 HealthReaderLite 应用图标（1024x1024 PNG）
// 用法: swift Scripts/gen_icon.swift [输出路径]
import AppKit
import Foundation

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Scripts/icon_1024.png"

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("无法创建图形上下文")
}
ctx.interpolationQuality = .high

// ---- 圆角矩形背景 ----
let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
let path = NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: 225, yRadius: 225)
path.addClip()

// ---- Liquid Glass 渐变（蓝→青，带光泽）----
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.98, alpha: 1.0),
    NSColor(calibratedRed: 0.22, green: 0.72, blue: 0.78, alpha: 1.0),
    NSColor(calibratedRed: 0.32, green: 0.82, blue: 0.62, alpha: 1.0)
])!
gradient.draw(in: path, angle: -70)

// ---- 顶部玻璃高光 ----
let gloss = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.40),
    NSColor.white.withAlphaComponent(0.05)
])!
gloss.draw(in: path, angle: 90)

// ---- 内部细描边 ----
NSColor.white.withAlphaComponent(0.35).setStroke()
let border = NSBezierPath(roundedRect: rect.insetBy(dx: 10, dy: 10), xRadius: 222, yRadius: 222)
border.lineWidth = 4
border.stroke()

// ---- 中央叶子符号（palette 白色着染，直接绘制）----
let symbolSize: CGFloat = 430
let symbolImageSize = NSSize(width: symbolSize, height: symbolSize)
let symbolRect = NSRect(x: (1024 - symbolSize) / 2, y: (1024 - symbolSize) / 2 + 30,
                        width: symbolSize, height: symbolSize)
if let base = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: symbolSize * 0.52, weight: .medium)) {
    // 经典 template 着色：白底 + destinationIn 用符号 alpha 抠出白色叶子
    let whiteSymbol = NSImage(size: symbolImageSize)
    whiteSymbol.lockFocus()
    NSColor.white.set()
    let inner = NSRect(origin: .zero, size: symbolImageSize)
    inner.fill()
    base.draw(in: inner, from: inner, operation: .destinationIn, fraction: 1.0)
    whiteSymbol.unlockFocus()
    whiteSymbol.draw(in: symbolRect)
} else {
    // 兜底：白色圆
    NSColor.white.withAlphaComponent(0.92).setFill()
    NSBezierPath(ovalIn: symbolRect).fill()
}

// ---- 叶子下方小圆点（“焦点”装饰）----
NSColor.white.withAlphaComponent(0.92).setFill()
NSBezierPath(ovalIn: NSRect(x: 470, y: 196, width: 84, height: 84)).fill()

image.unlockFocus()

// ---- 写入 PNG ----
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG 编码失败")
}
try! png.write(to: URL(fileURLWithPath: output))
print("图标已生成: \(output)")