import Foundation
import AppKit
import WebKit

// MARK: - عکس‌برداری واقعی از صفحه (به‌جای فاوآیکون)

@MainActor
enum Screenshotter {
    static let size = CGSize(width: 1280, height: 800)

    /// صفحه را بارگذاری می‌کند و از بالای آن عکس می‌گیرد؛ در صورت شکست nil برمی‌گرداند.
    static func capture(_ url: URL, key: String, timeout: TimeInterval = 14) async -> String? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }

        let webView = WKWebView(frame: NSRect(origin: .zero, size: size))
        webView.load(URLRequest(url: url))

        // انتظار برای پایان بارگذاری
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if !webView.isLoading { break }
        }
        // فرصت برای جاافتادن محتوا و اسکریپت‌ها
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !webView.isLoading else {
            webView.stopLoading()
            return nil
        }
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0,0)")

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)

        let image: NSImage? = await withCheckedContinuation { cont in
            webView.takeSnapshot(with: config) { img, _ in
                cont.resume(returning: img)
            }
        }
        webView.stopLoading()
        webView.navigationDelegate = nil

        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              !looksBlank(rep),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        else { return nil }

        return AppPaths.save(jpeg, folder: "Screenshots", key: key, ext: "jpg")
    }

    /// تشخیص عکس خالی/سفید (صفحهٔ خطا یا بارگذاری‌نشده)
    private static func looksBlank(_ rep: NSBitmapImageRep) -> Bool {
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0 else { return true }

        var minV: Double = 1
        var maxV: Double = 0
        var samples = 0
        for i in 0..<24 {
            for j in 0..<12 {
                let x = Int(Double(w) * (Double(i) + 0.5) / 24)
                let y = Int(Double(h) * (Double(j) + 0.5) / 12)
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let v = (c.redComponent + c.greenComponent + c.blueComponent) / 3
                minV = min(minV, v)
                maxV = max(maxV, v)
                samples += 1
            }
        }
        guard samples > 0 else { return true }
        // اگر کل تصویر تقریباً یکدست باشد بی‌محتواست
        return (maxV - minV) < 0.04
    }
}
