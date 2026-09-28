import SwiftUI
import AppKit
import WebKit

// MARK: - پل فراخوانی صفحهٔ رندر

/// فراخوانی توابع صفحهٔ رندر. همهٔ ورودی‌ها از راه `arguments` می‌روند؛
/// یعنی رشتهٔ محتوا هرگز به‌صورت کد جاوااسکریپت ارزیابی نمی‌شود (فقط داده).
@MainActor
final class MindMapRenderBridge: ObservableObject {
    weak var webView: WKWebView?
    @Published private(set) var loaded = false
    @Published var renderError: String?
    @Published private(set) var nodeCount = 0
    @Published private(set) var direction = "rtl"
    /// اگر رندر قبل از ساخت/بارگذاری WebView صدا زده شود، JSON نگه داشته می‌شود و بعد از `didFinish` اجرا می‌شود.
    private var pendingJSON: String?
    private var renderGeneration = 0
    /// یک‌بار خودترمیمی: اگر اسکریپت صفحه بار نشده بود، صفحه ری‌لود و رندر تکرار می‌شود
    private var healedOnce = false
    var onMapChange: ((String) -> Void)?

    func markLoaded() {
        loaded = true
        if let json = pendingJSON, !json.isEmpty {
            pendingJSON = nil
            render(json)
        }
    }

    /// با ساختن WebView تازه (تعویض تب/بازسازی نما) وضعیت پلِ وب‌ویو قبلی باطل می‌شود؛
    /// وگرنه `loaded` کهنه می‌ماند و رندر روی صفحهٔ خالیِ تازه انجام می‌شود.
    func resetForNewView() {
        loaded = false
        nodeCount = 0
        pendingJSON = nil
        renderError = nil
        renderGeneration += 1
    }

    enum RenderError: LocalizedError {
        case noWebView
        case notLoaded
        var errorDescription: String? {
            switch self {
            case .noWebView: return L.tr("The render page has not been created yet.")
            case .notLoaded: return L.tr("The render page has not loaded yet.")
            }
        }
    }

    /// رندر نقشه با JSON — مقدار از `arguments` می‌رود؛ هرگز به‌صورت کد جاوااسکریپت ارزیابی نمی‌شود.
    func render(_ json: String) {
        guard !json.isEmpty else { return }
        guard let webView else { pendingJSON = json; return }
        guard loaded else { pendingJSON = json; return }
        renderGeneration += 1
        let generation = renderGeneration
        // فقط اگر واقعا خطایی هست پاکش کن — نوشتن بی‌دلیل @Published چرخهٔ رندر می‌سازد
        if renderError != nil { renderError = nil }

        // خطاها درون JS می‌آیند تا علت واقعی (و نه پیام عمومی WebKit) نمایش داده شود؛
        // خروجی `renderMindMap` یک رشتهٔ JSON است.
        let script = """
        try {
          if (typeof window.renderMindMap === 'function') return window.renderMindMap(json);
          var errs = (window.__errors || []).join(' | ');
          return JSON.stringify({ok:false, error:'\(L.tr("Render script failed to run"))' + (errs ? (' — ' + errs) :
            (' [diagnose: renderMindMap=' + typeof window.renderMindMap +
             ', errors=' + JSON.stringify(window.__errors || null) +
             ', readyState=' + document.readyState +
             ', href=' + String(location.href).slice(-60) + ']'))});
        } catch (e) {
          return JSON.stringify({ok:false, error: String((e && e.message) || e)});
        }
        """
        webView.callAsyncJavaScript(script,
                                    arguments: ["json": json],
                                    in: nil, in: .page) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                guard self.renderGeneration == generation else { return }
                switch result {
                case .failure(let error):
                    self.renderError = error.localizedDescription
                case .success(let value):
                    var dict: [String: Any]?
                    if let text = value as? String,
                       let data = text.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        dict = parsed
                    } else if let obj = value as? [String: Any] {
                        dict = obj
                    }
                    guard let dict else { return }
                    if let ok = dict["ok"] as? Bool, ok {
                        self.healedOnce = false
                        self.renderError = nil
                        self.nodeCount = dict["nodes"] as? Int ?? 0
                        self.direction = dict["dir"] as? String ?? "rtl"
                    } else {
                        let message = dict["error"] as? String ?? L.tr("Rendering failed.")
                        // خودترمیمی: اگر اسکریپت صفحه بار نشده بود (تعویض وب‌ویو/شکست بارگذاری)،
                        // یک‌بار صفحه ری‌لود و رندر بعد از بارگذاری تکرار می‌شود.
                        if !self.healedOnce, message.contains("renderMindMap=undefined") {
                            self.healedOnce = true
                            self.loaded = false
                            self.nodeCount = 0
                            self.pendingJSON = json
                            self.webView?.reload()
                            return
                        }
                        self.renderError = message
                    }
                }
            }
        }
    }

    /// Remove all old map nodes before another URL/map is opened. This prevents a prior map
    /// from being visible while a new request is loading or if the next request fails.
    func clear() {
        renderGeneration += 1
        pendingJSON = nil
        nodeCount = 0
        renderError = nil
        guard loaded else { return }
        callJS("clearMap")
    }

    /// فراخوانی تابع صفحه با آرگومان‌های نام‌دار (مقادیر از `arguments` می‌آیند، نه از درون رشتهٔ کد).
    /// مثلاً callJS("setThemeName", ["name": "forest"]) می‌شود: return window.setThemeName(name)
    func callJS(_ fn: String, arguments: [String: Any] = [:]) {
        guard let webView, loaded else { return }
        let params = arguments.keys.sorted().joined(separator: ",")
        webView.callAsyncJavaScript("return window.\(fn)(\(params))",
                                    arguments: arguments,
                                    in: nil, in: .page) { _ in }
    }

    func setTheme(dark: Bool) { setThemeName(dark ? MindMapTheme.dark.rawValue : MindMapTheme.light.rawValue) }
    func setThemeName(_ name: String) { callJS("setThemeName", arguments: ["name": name]) }
    /// زبان رابط صفحهٔ رندر (placeholder، منوی راست‌کلیک، راهنما و…) را ست می‌کند
    func setUILanguage(_ lang: String) { callJS("setUILanguage", arguments: ["lang": lang]) }
    func setLayout(_ name: String) { callJS("setLayout", arguments: ["name": name]) }
    func setDirection(_ direction: MindMapDirection) { callJS("setDirection", arguments: ["d": direction.rawValue]) }
    func zoomIn() { callJS("zoomIn") }
    func zoomOut() { callJS("zoomOut") }
    func fit() { callJS("fit") }
    func expandAll() { callJS("expandAll") }
    func collapseAll() { callJS("collapseAll") }
    func addChild() { callJS("addChild") }
    func addSibling() { callJS("addSibling") }
    func deleteSelected() { callJS("deleteSelected") }
    func openSearch() { callJS("openSearch") }
    func search(_ query: String) { callJS("search", arguments: ["q": query]) }

    /// عکس فوری از نقشهٔ رندرشده برای خروجی‌های تصویری
    func snapshot(_ receive: @escaping (NSImage) -> Void) {
        guard let webView, loaded else { return }
        webView.takeSnapshot(with: WKSnapshotConfiguration()) { image, _ in
            Task { @MainActor in if let image { receive(image) } }
        }
    }
}

// MARK: - WebView رندر (فقط منابع محلی باندل)

struct MindMapWebView: NSViewRepresentable {
    let bridge: MindMapRenderBridge
    let json: String
    let dark: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // دادهٔ ناپایدار: بدون کوکی/نشست مشترک با اپ یا مرورگر کاربر
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        config.userContentController.add(context.coordinator, name: "mindMapChange")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        bridge.webView = webView
        bridge.resetForNewView()

        guard let index = Bundle.module.url(forResource: "canvas",
                                            withExtension: "html",
                                            subdirectory: "MindMap") else {
            bridge.renderError = L.tr("The mind map render file was not found in the app bundle.")
            return webView
        }
        // فقط فایل‌های داخل پوشهٔ MindMap خوانده می‌شوند؛ هیچ منبع ریموت مجاز نیست.
        webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // فقط با تغییر JSON رندر کن. شرط «nodeCount == 0» حذف شد: هر بار رندر،
        // نوشتن `renderError` (منتشرشده) دوباره updateNSView را صدا می‌زد و
        // چرخهٔ بی‌پایانِ «رندر → به‌روزرسانی → رندر» پاسخ‌های تکمیل را گرسنه
        // می‌کرد و رابط برای همیشه روی «در حال رندر نقشه…» قفل می‌شد.
        if bridge.loaded, !json.isEmpty, json != context.coordinator.lastJSON {
            context.coordinator.lastJSON = json
            bridge.render(json)
        }
        if dark != context.coordinator.dark {
            context.coordinator.dark = dark
            bridge.setTheme(dark: dark)
        }
        let lang = AppLanguage.current.rawValue
        if lang != context.coordinator.uiLang {
            context.coordinator.uiLang = lang
            bridge.setUILanguage(lang)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let bridge: MindMapRenderBridge
        var lastJSON = ""
        var dark = false
        var uiLang = AppLanguage.current.rawValue

        init(bridge: MindMapRenderBridge) { self.bridge = bridge }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            bridge.markLoaded()
            bridge.setTheme(dark: dark)
            bridge.setUILanguage(AppLanguage.current.rawValue)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "mindMapChange",
                  let json = message.body as? String,
                  !json.isEmpty else { return }
            Task { @MainActor in
                // The HTML canvas already applied this data; do not feed it back to render()
                // (which would reset the user's pan/zoom after every node drag).
                lastJSON = json
                bridge.onMapChange?(json)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            // فقط file: محلیِ همان پوشه مجاز است؛ هر ناوبری دیگری (ریموت/جاسازی‌شده) لغو می‌شود.
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.isFileURL || navigationAction.navigationType == .other {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            bridge.renderError = error.localizedDescription
        }
    }
}
