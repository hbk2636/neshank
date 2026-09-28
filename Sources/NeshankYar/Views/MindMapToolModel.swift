import Foundation
import SwiftUI

// MARK: - مدل پنجرهٔ «طراحی نقشه ذهنی»

@MainActor
final class MindMapToolModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case map, tree, markdown, json
        var id: String { rawValue }
        var label: String {
            switch self {
            case .map: return L.tr("Mind Map Tab")
            case .tree: return L.tr("Tree View")
            case .markdown: return L.tr("Source Markdown")
            case .json: return L.tr("JSON Structure")
            }
        }
        var icon: String {
            switch self {
            case .map: return "point.3.connected.trianglepath.dotted"
            case .tree: return "list.bullet.indent"
            case .markdown: return "doc.text"
            case .json: return "curlybraces"
            }
        }
    }

    enum Step: String, CaseIterable, Identifiable {
        case fetch = "دریافت صفحه"
        case extract = "استخراج محتوای اصلی"
        case markdown = "تبدیل به مارک‌داون"
        case analyze = "تحلیل هوش مصنوعی"
        case build = "ساخت نقشه"
        var id: String { rawValue }

        /// عنوان نمایشی ترجمه‌پذیر؛ rawValue به‌عنوان داده دست‌نخورده می‌ماند
        var title: String {
            switch self {
            case .fetch: return L.tr("Fetch Page")
            case .extract: return L.tr("Extract Main Content")
            case .markdown: return L.tr("Convert to Markdown")
            case .analyze: return L.tr("AI Analysis")
            case .build: return L.tr("Build Map")
            }
        }
    }

    enum StepState: Equatable {
        case pending, running, success
        case failed(String)
    }

    enum Phase: Equatable { case ready, processing, result, failed, paste }

    @Published var phase: Phase = .ready
    @Published var tab: Tab = .map
    @Published var urlText = ""
    @Published var pageTitle = ""
    @Published var faviconPath: String?
    @Published var steps: [StepState] = Array(repeating: .pending, count: Step.allCases.count)
    @Published var stepNote: String?
    @Published var mapJSON = ""
    @Published var rawMarkdown = ""
    @Published var contentText = ""
    @Published var statusText = ""
    @Published var warningText: String?
    @Published var errorTitle: String?
    @Published var errorDetail: String?
    @Published var pasteTitle = ""
    @Published var pasteBody = ""
    @Published var unsavedChanged = false
    @Published var longTimeout = false
    @Published var currentRecordID: Int64?

    private var task: Task<Void, Never>?

    var isBusy: Bool { phase == .processing }
    var hasResult: Bool { !mapJSON.isEmpty }
    var canStart: Bool { !urlText.trimmed.isEmpty && !isBusy }
    var sourceURL: URL? { URLNormalizer.url(urlText) }

    // MARK: Open/reset

    /// Start a new, unsaved map from an optional bookmark. No sample map is loaded.
    func prepare(selectedBookmark: Bookmark?) {
        reset()
        guard let bookmark = selectedBookmark else { return }
        urlText = bookmark.url
        pageTitle = bookmark.displayTitle
        faviconPath = bookmark.favicon
        if let saved = Library.shared.savedContent(id: bookmark.id), !saved.trimmed.isEmpty {
            contentText = saved
        }
    }

    func prepare(url: String, title: String = "") {
        reset()
        urlText = url
        pageTitle = title
    }

    /// Open a record from the main library as-is; it is not regenerated on open.
    func prepare(savedMap record: MindMapRecord) {
        reset()
        currentRecordID = record.id
        urlText = record.sourceURL
        pageTitle = record.title
        rawMarkdown = record.rawMarkdown
        contentText = record.rawMarkdown
        mapJSON = record.mindMapJSON
        phase = .result
        tab = .map
        statusText = L.tf("Saved map opened from library · %@ nodes", Digits.fa(record.nodeCount))
        unsavedChanged = false
    }

    func reset() {
        cancel()
        phase = .ready
        tab = .map
        urlText = ""
        pageTitle = ""
        faviconPath = nil
        steps = Array(repeating: .pending, count: Step.allCases.count)
        stepNote = nil
        mapJSON = ""
        rawMarkdown = ""
        contentText = ""
        statusText = ""
        warningText = nil
        errorTitle = nil
        errorDetail = nil
        pasteTitle = ""
        pasteBody = ""
        unsavedChanged = false
        currentRecordID = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: Real pipeline

    /// Always generates a NEW independent map record. `forceRegenerate` bypasses any future cache.
    func start(forceRegenerate: Bool = false) {
        guard !isBusy else { return }
        guard let url = sourceURL, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            fail(title: L.tr("Invalid URL."), detail: L.tr("Only http and https URLs are accepted."))
            return
        }
        _ = forceRegenerate // maps are independent records; we never overwrite by URL
        clearResultForNewRun()
        urlText = url.absoluteString
        phase = .processing
        statusText = L.tr("Starting the page pipeline")
        task = Task { @MainActor in
            do {
                steps[0] = .running
                stepNote = Step.fetch.title
                statusText = L.tr("Loading page in a sandboxed WebKit…")
                let page = try await WebPageReader.read(
                    url,
                    timeout: longTimeout ? 25 : 20,
                    quietIntervalMilliseconds: longTimeout ? 1_000 : 500,
                    idleCap: longTimeout ? 20 : 10,
                    onInitialLoad: { [weak self] in
                        guard let self, self.phase == .processing else { return }
                        self.steps[0] = .success
                        self.steps[1] = .running
                        self.stepNote = Step.extract.title
                        self.statusText = L.tr("Page loaded; Readability is extracting the main content…")
                    })
                try Task.checkCancellation()
                steps[0] = .success
                steps[1] = .success
                stepNote = Step.markdown.title

                let resolvedTitle = page.title.trimmed.isEmpty ? URLNormalizer.domain(page.finalURL) : page.title.trimmed
                pageTitle = resolvedTitle
                urlText = page.finalURL.absoluteString
                contentText = page.markdown
                rawMarkdown = page.markdown

                let quality = PageContentQuality.assess(page.markdown, title: resolvedTitle)
                guard quality.isUsable else {
                    steps[2] = .failed(quality.explanation)
                    fail(title: L.tr("Not enough content could be extracted from this page."), detail: quality.explanation)
                    return
                }
                steps[2] = .success
                stepNote = Step.analyze.title
                statusText = L.tf("%@ words extracted from %@; analyzing with AI…", Digits.fa(quality.wordCount), page.selectedRegion)

                steps[3] = .running
                let config = AIConfig.load()
                let result = try await MindMapAIService.generate(page: page,
                                                                 quality: quality,
                                                                 config: config,
                                                                 session: AIClient.newSession())
                try Task.checkCancellation()
                steps[3] = .success
                steps[4] = .running
                stepNote = Step.build.title
                mapJSON = result.json
                rawMarkdown = page.markdown
                contentText = page.markdown
                warningText = result.warning
                steps[4] = .success
                stepNote = nil
                phase = .result

                // هر موفقیت یک ردیف جدید در کتابخانه می‌سازد. آدرس تکراری قبلی را overwrite نمی‌کند.
                if let record = Library.shared.createMindMap(title: result.document.meta.title,
                                                              sourceURL: page.finalURL.absoluteString,
                                                              markdown: page.markdown,
                                                              json: result.json,
                                                              model: config.model,
                                                              language: result.document.meta.language) {
                    currentRecordID = record.id
                    statusText = L.tf("Map built and saved separately in Mind Maps · %@ nodes", Digits.fa(result.nodeCount))
                    unsavedChanged = false
                } else {
                    statusText = L.tf("Map built · %@ nodes; saving to library failed.", Digits.fa(result.nodeCount))
                    unsavedChanged = true
                }
            } catch is CancellationError {
                stopByUser()
            } catch {
                let detail = error.localizedDescription
                if let running = steps.firstIndex(where: { if case .running = $0 { return true }; return false }) {
                    steps[running] = .failed(detail)
                }
                fail(title: L.tr("Failed to build the map."), detail: detail)
            }
            task = nil
        }
    }

    private func clearResultForNewRun() {
        cancel()
        currentRecordID = nil
        mapJSON = ""
        rawMarkdown = ""
        contentText = ""
        warningText = nil
        errorTitle = nil
        errorDetail = nil
        steps = Array(repeating: .pending, count: Step.allCases.count)
        stepNote = nil
        unsavedChanged = false
    }

    func stop() {
        cancel()
        stopByUser()
    }

    private func stopByUser() {
        phase = .ready
        steps = Array(repeating: .pending, count: Step.allCases.count)
        stepNote = nil
        statusText = L.tr("Stopped")
    }

    func retry(longer: Bool) {
        longTimeout = longer
        start(forceRegenerate: true)
    }

    func fail(title: String, detail: String?) {
        phase = .failed
        errorTitle = title
        errorDetail = detail
        statusText = ""
        if let idx = steps.firstIndex(where: { if case .running = $0 { return true }; return false }) {
            steps[idx] = .failed(detail ?? title)
        }
    }

    // MARK: Manual paste → real AI stage

    func beginPaste() {
        pasteTitle = pageTitle
        pasteBody = contentText
        phase = .paste
    }

    func cancelPaste() { phase = hasResult ? .result : .ready }

    func continuePaste() {
        let manual = pasteBody.trimmed
        guard !manual.isEmpty else { return }
        let title = pasteTitle.trimmed.isEmpty ? pageTitle : pasteTitle.trimmed
        let quality = PageContentQuality.assess(manual, title: title)
        guard quality.isUsable else {
            fail(title: L.tr("Not enough content."), detail: quality.explanation)
            return
        }
        clearResultForNewRun()
        contentText = manual
        rawMarkdown = manual
        pageTitle = title.isEmpty ? L.tr("Pasted Text") : title
        phase = .processing
        steps[0] = .success
        steps[1] = .success
        steps[2] = .success
        steps[3] = .running
        stepNote = Step.analyze.title
        statusText = L.tr("Building map from pasted text…")

        task = Task { @MainActor in
            do {
                let url = sourceURL ?? URL(string: "https://manual.invalid/")!
                let page = RenderedPage(title: pageTitle,
                                        finalURL: url,
                                        description: "",
                                        byline: "",
                                        siteName: url.host ?? "",
                                        language: "",
                                        markdown: manual,
                                        contentHTML: "",
                                        headings: markdownHeadings(manual),
                                        selectedRegion: L.tr("Manual Text"),
                                        usedReadability: false)
                let config = AIConfig.load()
                let result = try await MindMapAIService.generate(page: page, quality: quality,
                                                                 config: config,
                                                                 session: AIClient.newSession())
                try Task.checkCancellation()
                steps[3] = .success
                steps[4] = .success
                stepNote = nil
                mapJSON = result.json
                warningText = result.warning
                phase = .result
                if let record = Library.shared.createMindMap(title: result.document.meta.title,
                                                              sourceURL: url.absoluteString,
                                                              markdown: manual,
                                                              json: result.json,
                                                              model: config.model,
                                                              language: result.document.meta.language) {
                    currentRecordID = record.id
                    statusText = L.tf("Map built from pasted text and saved to library · %@ nodes", Digits.fa(result.nodeCount))
                    unsavedChanged = false
                } else {
                    statusText = L.tr("Map built from pasted text; saving to library failed.")
                    unsavedChanged = true
                }
            } catch is CancellationError {
                stopByUser()
            } catch {
                let detail = error.localizedDescription
                steps[3] = .failed(detail)
                fail(title: L.tr("Failed to analyze pasted text."), detail: detail)
            }
            task = nil
        }
    }

    private func markdownHeadings(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("#") }
    }

    // MARK: Saved map editing

    /// Called by the canvas after a free drag or node-text edit. DB write stays explicit via Save.
    func canvasDidChange(_ json: String) {
        guard !json.isEmpty, json != mapJSON else { return }
        mapJSON = json
        unsavedChanged = true
        statusText = L.tr("Map changes not saved")
    }

    func saveCurrentMap() {
        guard hasResult else { return }
        let language = MindMapAIService.detectLanguageFromJSON(mapJSON)
        let title = MindMapAIService.titleFromJSON(mapJSON) ?? pageTitle
        let ok: Bool
        if let id = currentRecordID {
            ok = Library.shared.updateMindMap(id: id, title: title, sourceURL: urlText,
                                              markdown: rawMarkdown, json: mapJSON,
                                              model: AIConfig.load().model, language: language)
        } else if let record = Library.shared.createMindMap(title: title, sourceURL: urlText,
                                                             markdown: rawMarkdown, json: mapJSON,
                                                             model: AIConfig.load().model, language: language) {
            currentRecordID = record.id
            ok = true
        } else { ok = false }
        if ok {
            unsavedChanged = false
            statusText = L.tr("Map saved as a separate record")
        } else {
            errorTitle = L.tr("Failed to save the map.")
        }
    }

    // MARK: Tabs

    var treeText: String { treeFromJSON(mapJSON) }

    func treeFromJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = obj["root"] as? [String: Any] else { return "—" }
        var lines: [String] = []
        var stack: [(node: [String: Any], depth: Int)] = [(root, 0)]
        while let (node, depth) = stack.popLast() {
            let text = (node["text"] as? String) ?? (node["topic"] as? String) ?? ""
            lines.append(String(repeating: "  ", count: depth) + (depth == 0 ? "● " : "– ") + text)
            let kids = (node["children"] as? [[String: Any]]) ?? []
            for child in kids.reversed() { stack.append((child, depth + 1)) }
        }
        return lines.joined(separator: "\n")
    }

    var markdownForExport: String { rawMarkdown }

    func markSaved() { unsavedChanged = false }
}
