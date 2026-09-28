// ساخت لوگوی «نشانک» — بدون وابستگی خارجی.
// usage: swift Scripts/make_logo.swift <output.png> [size]
// طرح: پس‌زمینهٔ تیرهٔ بنفش با گوشه‌های گرد، نشانک خطی سفید، نوشتهٔ NESHANAK
import AppKit

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "Resources/logo.png"
let side = args.count > 2 ? (Double(args[2]) ?? 1024) : 1024
let S = CGFloat(side)

let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()

// پس‌زمینهٔ تیرهٔ بنفش با گوشه‌های گرد
let bgRadius = S * 0.225
let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: S, height: S),
                      xRadius: bgRadius, yRadius: bgRadius)
NSColor(calibratedRed: 0.113, green: 0.059, blue: 0.129, alpha: 1).setFill()
bg.fill()

// نشانک (فقط خط سفید با گوشه‌های نرم و بریدگی V در پایین)
let bw = S * 0.225
let bh = S * 0.305
let x = (S - bw) / 2
let bottomY = S * 0.375
let topY = bottomY + bh
let notch = S * 0.105
let topR = S * 0.020
let lineWidth = S * 0.014
let cx = S / 2

let mark = NSBezierPath()
mark.lineWidth = lineWidth
mark.lineJoinStyle = .round
mark.lineCapStyle = .round

func roundedCorner(_ path: NSBezierPath, center: CGPoint, radius: CGFloat,
                   start: CGFloat, end: CGFloat, clockwise: Bool) {
    path.appendArc(withCenter: center, radius: radius,
                   startAngle: start, endAngle: end, clockwise: clockwise)
}

// نقطهٔ شروع: پایین-چپ
mark.move(to: CGPoint(x: x, y: bottomY + topR * 0.6))
// لبهٔ چپ
mark.line(to: CGPoint(x: x, y: topY - topR))
// گوشهٔ بالا-چپ
roundedCorner(mark, center: CGPoint(x: x + topR, y: topY - topR),
              radius: topR, start: 180, end: 90, clockwise: true)
// لبهٔ بالا
mark.line(to: CGPoint(x: x + bw - topR, y: topY))
// گوشهٔ بالا-راست
roundedCorner(mark, center: CGPoint(x: x + bw - topR, y: topY - topR),
              radius: topR, start: 90, end: 0, clockwise: true)
// لبهٔ راست
mark.line(to: CGPoint(x: x + bw, y: bottomY + topR * 0.6))
// بریدگی V پایین
mark.line(to: CGPoint(x: cx, y: bottomY + notch))
mark.line(to: CGPoint(x: x, y: bottomY + topR * 0.6))
mark.close()

NSColor.white.setStroke()
mark.stroke()

// نوشتهٔ NESHANAK
let text = "NESHANAK"
let font = NSFont(name: "AvenirNext-Bold", size: S * 0.082)
    ?? NSFont(name: "HelveticaNeue-Bold", size: S * 0.082)
    ?? NSFont.boldSystemFont(ofSize: S * 0.082)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .kern: S * 0.011
]
let attributed = NSAttributedString(string: text, attributes: attrs)
let textSize = attributed.size()
let textRect = NSRect(x: (S - textSize.width) / 2,
                      y: S * 0.215,
                      width: textSize.width,
                      height: textSize.height)
attributed.draw(in: textRect)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("logo rendering failed\n".data(using: .utf8)!)
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: outPath))
    print("ok: \(outPath)")
} catch {
    FileHandle.standardError.write("logo write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
