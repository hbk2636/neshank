import Foundation
import AppKit
import WebKit

// MARK: - Quality gate for cleaned Markdown

struct PageContentQuality: Codable, Equatable, Sendable {
    var characterCount: Int
    var wordCount: Int
    var uniqueWordCount: Int
    var lineCount: Int
    var headingCount: Int
    var paragraphCount: Int
    var score: Double
    var isUsable: Bool
    var explanation: String

    /// 250 useful chars OR 40 words OR one heading and two paragraphs.
    /// A short title/menu shell is rejected even if it repeats the page title.
    static func assess(_ raw: String, title: String = "") -> PageContentQuality {
        let text = normalize(raw)
        let words = tokens(text)
        let unique = Set(words).count
        let usefulChars = text.filter { !$0.isWhitespace && !$0.isNewline }.count
        let lines = text.components(separatedBy: .newlines).filter { !$0.isBlank }.count
        let headings = text.components(separatedBy: .newlines).filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        }.count
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.isBlank }.count
        let titleWords = Set(tokens(normalize(title)))
        let overlap = titleWords.isEmpty ? 0.0 :
            Double(titleWords.intersection(Set(words)).count) / Double(titleWords.count)

        let enough = usefulChars >= 250 || words.count >= 40 || (headings >= 1 && paragraphs >= 2)
        let titleOnly = overlap >= 0.9 && words.count < 40
        let menuLike = words.count < 40 && lines < 5 && headings == 0
        let usable = enough && !titleOnly && !menuLike
        let score = min(1, Double(usefulChars) / 1_800) * 0.25
            + min(1, Double(words.count) / 260) * 0.35
            + min(1, Double(unique) / 100) * 0.30
            + min(1, Double(lines) / 18) * 0.10

        let explanation: String
        if usable { explanation = L.tr("Enough text was found to build the mind map.") }
        else if titleOnly { explanation = L.tr("Only the page title was extracted; a mind map is not built from the title alone.") }
        else if menuLike { explanation = L.tr("The extracted text looks like a menu/site shell, not main content.") }
        else { explanation = L.tr("Not enough content was extracted from this page; paste the text manually or try a longer delay.") }

        return PageContentQuality(characterCount: usefulChars,
                                  wordCount: words.count,
                                  uniqueWordCount: unique,
                                  lineCount: lines,
                                  headingCount: headings,
                                  paragraphCount: paragraphs,
                                  score: score,
                                  isUsable: usable,
                                  explanation: explanation)
    }

    /// Arabic/Persian spelling and ZWNJ normalization for quality checks and hashes.
    static func normalize(_ source: String) -> String {
        var output = ""
        output.reserveCapacity(source.count)
        for scalar in source.unicodeScalars {
            switch scalar.value {
            case 0x064A, 0x0649: output.append("ی")
            case 0x0643: output.append("ک")
            case 0x200C, 0x200D, 0x200E, 0x200F: output.append(" ")
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output.replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { $0.count >= 2 }
    }
}

// MARK: - Extracted page value

struct RenderedPage: Sendable {
    var title: String
    var finalURL: URL
    var description: String
    var byline: String
    var siteName: String
    var language: String
    var markdown: String
    var contentHTML: String
    var headings: [String]
    var selectedRegion: String
    var usedReadability: Bool

    /// Compatibility with existing reader/archive UI; content is now cleaned Markdown.
    var text: String { markdown }
}

enum PageContentReadError: LocalizedError {
    case unsupportedURL
    case assets(String)
    case navigation(String)
    case httpStatus(Int)
    case timedOut
    case empty(title: String, region: String, markdownChars: Int, htmlChars: Int,
               headings: Int, readability: Bool)

    var errorDescription: String? {
        switch self {
        case .unsupportedURL: return L.tr("The link is not valid; only http and https addresses are accepted.")
        case .assets(let reason): return L.tf("Failed to load page extractor local files: %@", reason)
        case .navigation(let detail): return detail.isBlank ? L.tr("The browser could not load the page.") : L.tf("Page load error: %@", detail)
        case .httpStatus(let status): return L.tf("The page returned HTTP status %@.", Digits.fa(status))
        case .timedOut: return L.tr("Loading the page took too long; try the “Retry with longer delay” option.")
        case .empty(let title, let region, let markdownChars, let htmlChars, let headings, let readability):
            return L.tf("Not enough content was extracted from this page; you can paste the text manually. " +
                "Technical details: title=%@, region=%@, markdown=%d, html=%d, headings=%d, readability=%@.",
                title, region, markdownChars, htmlChars, headings, String(readability))
        }
    }
}

/// WKWebView's completion-handler result is not Sendable on current SDKs. This tiny box only
/// transports the callback result back onto the main actor where WebKit is owned.
private final class JavaScriptOutcome: @unchecked Sendable {
    let value: Any?
    let error: Error?
    init(_ result: Result<Any, Error>) {
        switch result {
        case .success(let value): self.value = value; self.error = nil
        case .failure(let error): self.value = nil; self.error = error
        }
    }
}

// MARK: - Isolated WebKit + Readability + Turndown

@MainActor
enum WebPageReader {
    static let maxTextCharacters = 180_000

    /// This bootstrap and the two library files are bundled local code. Page HTML is only
    /// read from the DOM and returned as data; no page string is ever evaluated as code.
    private static let extractionBootstrap = #"""
    return await (async function(quietIntervalMs, idleCapMs, maxTextChars) {
      const waitForDOMQuiet = () => new Promise(resolve => {
        let settled = false;
        let lastMutation = Date.now();
        let observer;
        let capTimer;
        const finish = value => {
          if (settled) return;
          settled = true;
          try { observer && observer.disconnect(); } catch (_) {}
          clearTimeout(capTimer);
          resolve(value);
        };
        const check = () => {
          if (document.readyState === 'complete' && Date.now() - lastMutation >= quietIntervalMs) {
            finish(true); return;
          }
          if (!settled) setTimeout(check, Math.min(80, quietIntervalMs));
        };
        try {
          observer = new MutationObserver(() => { lastMutation = Date.now(); });
          observer.observe(document.documentElement || document, {
            subtree: true, childList: true, attributes: true, characterData: true
          });
        } catch (_) {}
        capTimer = setTimeout(() => finish(false), idleCapMs);
        if (document.readyState === 'complete') check();
        else document.addEventListener('readystatechange', check);
      });

      await waitForDOMQuiet();
      const useful = s => (s || '').replace(/\s/g, '').length;
      const words = s => (s || '').trim().split(/\s+/u).filter(Boolean).length;
      const enough = s => useful(s) >= 250 || words(s) >= 40;
      const headingsOf = root => [...root.querySelectorAll('h1,h2,h3,h4,h5,h6')]
        .map(e => (e.innerText || e.textContent || '').trim()).filter(Boolean);
      const removeUnambiguous = root => root.querySelectorAll(
        'script,style,noscript,iframe,form,button,input,select,textarea'
      ).forEach(el => el.remove());

      const originalTitle = (document.querySelector('meta[property="og:title"]')?.content ||
        document.title || document.querySelector('h1')?.innerText || '').trim();
      const description = (document.querySelector('meta[property="og:description"]')?.content ||
        document.querySelector('meta[name="description"]')?.content || '').trim();
      const byline = (document.querySelector('[rel="author"]')?.innerText ||
        document.querySelector('[itemprop="author"]')?.innerText || '').trim();
      const siteName = (document.querySelector('meta[property="og:site_name"]')?.content ||
        location.hostname || '').trim();
      const language = (document.documentElement.lang ||
        document.querySelector('meta[http-equiv="content-language"]')?.content || '').trim();

      let contentHTML = '';
      let selectedRegion = 'readability';
      let usedReadability = false;
      let articleTitle = originalTitle;
      let articleExcerpt = description;
      let articleByline = byline;

      // Path A: Readability works on a document clone. No class/id purge before this pass.
      try {
        const readabilityDoc = document.cloneNode(true);
        removeUnambiguous(readabilityDoc);
        const parsed = new Readability(readabilityDoc, { keepClasses: true }).parse();
        if (parsed && parsed.content && enough(parsed.textContent || '')) {
          contentHTML = parsed.content;
          articleTitle = (parsed.title || originalTitle).trim();
          articleExcerpt = (parsed.excerpt || description).trim();
          articleByline = (parsed.byline || byline).trim();
          selectedRegion = 'readability';
          usedReadability = true;
        }
      } catch (_) {}

      // Path B: only if Readability returned empty/unusable content.
      if (!contentHTML) {
        const root = document.cloneNode(true);
        removeUnambiguous(root);
        const AD_FAMILY = /(^|[\s_-])(ad|ads|advert|advertorial|sponsor|sponsored|promo)([\s_-]|$)/i;
        const OTHER = /(^|[\s_-])(cookie|consent|popup|modal|newsletter|subscribe|social|share|related|comment|comments|sidebar|banner)([\s_-]|$)/i;
        const hasFamilyToken = (el, regex) => {
          const names = ((el.getAttribute('class') || '') + ' ' + (el.getAttribute('id') || ''))
            .split(/[\s]+/).filter(Boolean);
          return names.some(name => regex.test(name));
        };
        root.querySelectorAll('*').forEach(el => {
          if (hasFamilyToken(el, AD_FAMILY) || hasFamilyToken(el, OTHER)) el.remove();
        });
        root.querySelectorAll('nav,footer,aside,[role="navigation"],[role="banner"],[role="contentinfo"]')
          .forEach(el => el.remove());

        const selectors = ['article','main','[role="main"]','#main','#content',
          '.post-content','.article-content','.entry-content','.article-body'];
        let chosen = null;
        for (const selector of selectors) {
          const el = root.querySelector(selector);
          if (!el) continue;
          if (enough(el.innerText || el.textContent || '')) { chosen = el; selectedRegion = selector; break; }
        }
        if (!chosen) {
          let best = null, bestScore = -Infinity;
          for (const el of root.querySelectorAll('article,main,section,div,table,ul')) {
            const text = (el.innerText || el.textContent || '').trim();
            if (!enough(text)) continue;
            const chars = useful(text);
            const links = [...el.querySelectorAll('a')].reduce((n,a) => n + useful(a.innerText || ''), 0);
            const paras = el.querySelectorAll('p,li,blockquote,dd').length;
            const heads = el.querySelectorAll('h1,h2,h3,h4').length;
            const score = chars + paras * 90 + heads * 110 - Math.min(links, chars) * 0.85;
            if (score > bestScore) { best = el; bestScore = score; }
          }
          chosen = best;
          selectedRegion = 'largest-text-block';
        }
        if (chosen) contentHTML = chosen.innerHTML || '';
      }

      if (!contentHTML) return { title: originalTitle, url: location.href, empty: true,
        description, byline, siteName, language, markdown: '', contentHTML: '',
        headings: [], region: selectedRegion, usedReadability };

      // Local Turndown; media controls are removed before conversion.
      const container = document.createElement('div');
      container.innerHTML = contentHTML;
      container.querySelectorAll('img,video,audio,iframe,form,button,input,select,textarea').forEach(e => e.remove());
      const turndown = new TurndownService({ headingStyle: 'atx', bulletListMarker: '-', codeBlockStyle: 'fenced' });
      turndown.addRule('removeUnsafeMedia', {
        filter: ['img','video','audio','iframe','form','button','input','select','textarea'],
        replacement: () => ''
      });
      let markdown = turndown.turndown(container.innerHTML);
      markdown = markdown.replace(/<\/?[a-z][^>]*>/gi, '')
        .replace(/\n[ \t]+/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
      if (markdown.length > maxTextChars) markdown = markdown.slice(0, maxTextChars);
      const articleHeadings = headingsOf(container);
      const mainElement = document.querySelector('main,[role="main"],#content,#main') || document.body;
      const sourceHeadings = articleHeadings.length ? articleHeadings : headingsOf(mainElement);
      const uniqueHeadings = [...new Set(sourceHeadings)].filter(h => h.length <= 140).slice(0, 100);
      return { title: articleTitle, url: location.href, description: articleExcerpt,
        byline: articleByline, siteName, language, markdown, contentHTML,
        headings: uniqueHeadings, region: selectedRegion,
        usedReadability, empty: !markdown };
    })(quietIntervalMs, idleCapMs, maxTextChars)
    """#

    static func read(_ url: URL,
                     timeout: TimeInterval = 20,
                     quietIntervalMilliseconds: Int = 500,
                     idleCap: TimeInterval = 10,
                     localLibraries: (readability: String, turndown: String)? = nil,
                     onInitialLoad: (@MainActor () -> Void)? = nil) async throws -> RenderedPage {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw PageContentReadError.unsupportedURL
        }
        let (readabilitySource, turndownSource) = try extractorSources(override: localLibraries)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 850), configuration: config)
        let delegate = ReadNavigationDelegate(initialHost: url.host?.lowercased() ?? "")
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate

        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1100, height: 850),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.alphaValue = 0.01
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = webView
        window.orderBack(nil)
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            window.orderOut(nil)
            window.close()
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(PageMeta.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("fa,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        webView.load(request)
        let deadline = Date().addingTimeInterval(timeout)
        // حداقل منتظر commit می‌مانیم (دریافت HTML اصلی)؛ وگرنه تا سقف زمان، خطای تأخیر
        while !delegate.didCommit, !delegate.didFinish, delegate.failure == nil {
            try Task.checkCancellation()
            if Date() >= deadline { throw PageContentReadError.timedOut }
            try await Task.sleep(nanoseconds: 80_000_000)
        }
        if let status = delegate.httpStatus, !(200..<400).contains(status) {
            throw PageContentReadError.httpStatus(status)
        }
        if let failure = delegate.failure { throw PageContentReadError.navigation(failure) }
        // صفحات سنگین گاهی تا finish بسیار طول می‌دهند (تبلیغ، آنالیتیکس، منابع درازمدت)؛
        // ۳ ثانیه فرجه می‌دهیم و بعد به استخراج می‌رویم — «سکوت DOM» داخل اسکریپت استخراج
        // خودش منتظر رندر محتوای جاوااسکریپتی می‌ماند (تا سقف بودجهٔ باقی‌مانده).
        let finishGrace = Date().addingTimeInterval(min(3, max(0.5, deadline.timeIntervalSinceNow)))
        while !delegate.didFinish, delegate.failure == nil, Date() < finishGrace {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if let failure = delegate.failure { throw PageContentReadError.navigation(failure) }
        onInitialLoad?()

        let remaining = max(0.5, deadline.timeIntervalSinceNow)
        let idleMs = min(Int(idleCap * 1000), Int(remaining * 1000))
        // `readability` and `turndown` below are bundled code. The page itself never contributes
        // executable source; only the fixed bootstrap runs inside this isolated WebView.
        let script = """
        return await (async function(quietIntervalMs, idleCapMs, maxTextChars) {
          \(readabilitySource)
          \(turndownSource)
          \(extractionBootstrap)
        })(quietIntervalMs, idleCapMs, maxTextChars)
        """
        let value: Any?
        do {
            value = try await evaluate(webView, script: script,
                                       arguments: ["quietIntervalMs": quietIntervalMilliseconds,
                                                   "idleCapMs": idleMs,
                                                   "maxTextChars": maxTextCharacters])
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw PageContentReadError.navigation(error.localizedDescription)
        }
        try Task.checkCancellation()
        if let status = delegate.httpStatus, !(200..<400).contains(status) {
            throw PageContentReadError.httpStatus(status)
        }
        guard let dict = value as? [String: Any] else {
            throw PageContentReadError.navigation(L.tf("The extractor did not return a structured response (response type: %@).", String(describing: type(of: value))))
        }
        let markdown = dict["markdown"] as? String ?? ""
        guard !markdown.trimmed.isEmpty, dict["empty"] as? Bool != true else {
            throw PageContentReadError.empty(title: dict["title"] as? String ?? "",
                                             region: dict["region"] as? String ?? "unknown",
                                             markdownChars: markdown.count,
                                             htmlChars: (dict["contentHTML"] as? String ?? "").count,
                                             headings: (dict["headings"] as? [String] ?? []).count,
                                             readability: dict["usedReadability"] as? Bool ?? false)
        }
        guard let finalURL = URL(string: dict["url"] as? String ?? "") ?? webView.url else {
            throw PageContentReadError.navigation(L.tr("The extractor did not return a final URL."))
        }
        return RenderedPage(title: (dict["title"] as? String ?? "").trimmed,
                            finalURL: finalURL,
                            description: (dict["description"] as? String ?? "").trimmed,
                            byline: (dict["byline"] as? String ?? "").trimmed,
                            siteName: (dict["siteName"] as? String ?? "").trimmed,
                            language: (dict["language"] as? String ?? "").trimmed,
                            markdown: markdown,
                            contentHTML: dict["contentHTML"] as? String ?? "",
                            headings: dict["headings"] as? [String] ?? [],
                            selectedRegion: dict["region"] as? String ?? "unknown",
                            usedReadability: dict["usedReadability"] as? Bool ?? false)
    }

    @MainActor
    private static func evaluate(_ webView: WKWebView, script: String,
                                 arguments: [String: Any]) async throws -> Any? {
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<JavaScriptOutcome, Never>) in
            webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
                let outcome = JavaScriptOutcome(result)
                Task { @MainActor in
                    continuation.resume(returning: outcome)
                }
            }
        }
        if let error = outcome.error { throw error }
        return outcome.value
    }

    private static func extractorSources(override: (readability: String, turndown: String)?) throws -> (String, String) {
        if let override {
            guard !override.readability.isEmpty, !override.turndown.isEmpty else {
                throw PageContentReadError.assets(L.tr("Readability.js or Turndown.js file is empty"))
            }
            return (override.readability, override.turndown)
        }
        #if SWIFT_PACKAGE
        guard let base = Bundle.module.url(forResource: "Readability", withExtension: "js",
                                           subdirectory: "Extractor")?.deletingLastPathComponent(),
              let readability = try? String(contentsOf: base.appendingPathComponent("Readability.js"), encoding: .utf8),
              let turndown = try? String(contentsOf: base.appendingPathComponent("Turndown.js"), encoding: .utf8)
        else { throw PageContentReadError.assets(L.tr("Readability.js or Turndown.js was not found")) }
        return (readability, turndown)
        #else
        throw PageContentReadError.assets(L.tr("This test build does not include SwiftPM resources"))
        #endif
    }

    @MainActor
    private final class ReadNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
        let initialHost: String
        var didFinish = false
        var didCommit = false
        var failure: String?
        var httpStatus: Int?

        init(initialHost: String) { self.initialHost = initialHost }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { didFinish = true }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { didCommit = true }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failure = error.localizedDescription
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failure = error.localizedDescription
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.isForMainFrame,
               let http = navigationResponse.response as? HTTPURLResponse { httpStatus = http.statusCode }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let frame = navigationAction.targetFrame, frame.isMainFrame,
                  let address = navigationAction.request.url,
                  let scheme = address.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                decisionHandler(.cancel) // popup/non-http is always blocked
                return
            }
            if didFinish, address.host?.lowercased() != initialHost {
                decisionHandler(.cancel) // client-side cross-domain navigation after initial load
                return
            }
            decisionHandler(.allow) // server redirect chain before didFinish is allowed
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
            completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
            completionHandler(false)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            completionHandler(nil)
        }
    }
}
