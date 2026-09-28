import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

// MARK: - پنجرهٔ نیتیو «طراحی نقشه ذهنی»

@MainActor
final class MindMapToolWindow: NSObject, NSWindowDelegate {
    static let shared = MindMapToolWindow()

    private var window: NSWindow?
    let model = MindMapToolModel()
    let bridge = MindMapRenderBridge()

    /// باز کردن از آیتم سایدبار (یا هر ورودی دیگر)
    func show(bookmark: Bookmark?) {
        if window == nil { makeWindow() }
        model.prepare(selectedBookmark: bookmark)
        bridge.clear()
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        bridge.render(model.mapJSON)
    }

    /// باز کردن یک نقشهٔ ذخیره‌شده؛ بدون تولید مجدد و بدون اشتراک state با نقشهٔ قبلی.
    func show(record: MindMapRecord) {
        if window == nil { makeWindow() }
        model.prepare(savedMap: record)
        bridge.clear()
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        bridge.render(model.mapJSON)
    }

    /// شروع نقشهٔ تازه از یک آدرس/عنوان؛ رکوردهای قبلی دست‌نخورده می‌مانند.
    func show(url: String, title: String = "") {
        if window == nil { makeWindow() }
        model.prepare(url: url, title: title)
        bridge.clear()
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.performClose(nil)
    }

    private func makeWindow() {
        let view = MindMapToolView(model: model, bridge: bridge)
            .environment(\.layoutDirection, L.direction)
            .preferredColorScheme(AppTheme.appearance)

        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = L.tr("Mind Map Designer")
        // تیتربار و چراغ‌های استاندارد مک (بالا سمت چپ)؛ بدون chrome سفارشی
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 1000, height: 720))
        w.contentMinSize = NSSize(width: 760, height: 560)
        w.isReleasedWhenClosed = false
        w.center()
        w.setFrameAutosaveName("MindMapToolWindow")
        w.delegate = self
        w.appearance = nil
        window = w
    }

    // MARK: ⌘W و بستن

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.isBusy {
            model.stop()
            return false
        }
        if model.unsavedChanged {
            let alert = NSAlert()
            alert.messageText = L.tr("Mind map is not saved. Close anyway?")
            alert.informativeText = L.tr("Unsaved changes will be lost.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L.tr("Close Without Saving"))
            alert.addButton(withTitle: L.tr("Keep Editing"))
            if alert.runModal() == .alertFirstButtonReturn {
                model.unsavedChanged = false
                return true
            }
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        model.cancel()
    }
}

// MARK: - رابط کاربری

struct MindMapToolView: View {
    @ObservedObject var model: MindMapToolModel
    @ObservedObject var bridge: MindMapRenderBridge
    @Environment(\.colorScheme) private var scheme

    @State private var themeName = MindMapTheme.dark.rawValue
    @State private var layoutName = MindMapLayout.tree.rawValue
    @State private var rootLeft = true

    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabBar
            Divider()
            content
            Divider()
            statusBar
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            themeName = MindMapTheme.forColorScheme(dark: dark).rawValue
            bridge.setThemeName(themeName)
        }
        .onAppear { bridge.onMapChange = { model.canvasDidChange($0) } }
        .onChange(of: scheme) { _ in
            // فقط وقتی کاربر روی تم‌های خودکار (تیره/روشن) است، با رنگ‌سیستم عوض شود؛
            // تم‌های دستی انتخاب‌شده (غروب، بنفشه و…) حفظ می‌شوند.
            guard let current = MindMapTheme(rawValue: themeName),
                  current == .light || current == .dark
            else { return }
            themeName = MindMapTheme.forColorScheme(dark: dark).rawValue
            bridge.setThemeName(themeName)
        }
        .onChange(of: model.mapJSON) { json in
            if json.isEmpty { bridge.clear() }
            else if bridge.nodeCount == 0 { bridge.render(json) }
            if let saved = MindMapLayout.fromJSON(json) { layoutName = saved.rawValue }
        }
    }

    // MARK: هدر

    private var header: some View {
        HStack(spacing: 10) {
            if !model.faviconPath.isNilOrBlank {
                FaviconView(path: model.faviconPath, size: 22)
            } else {
                Image(systemName: "circle.hexagongrid")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(model.pageTitle.isEmpty ? L.tr("Mind Map Designer") : model.pageTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !model.urlText.isEmpty {
                    HStack(spacing: 6) {
                        Text(model.urlText)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.urlText, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc").font(.system(size: 9))
                        }
                        .buttonStyle(.borderless)
                        .help(L.tr("Copy URL"))
                    }
                }
            }

            Spacer()

            Button {
                if model.hasResult, model.phase == .result {
                    model.start(forceRegenerate: true)
                } else {
                    model.start()
                }
            } label: {
                Label(model.hasResult ? L.tr("Generate") : L.tr("Start"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!model.canStart)
            .help(L.tr("Run the full pipeline"))

            if model.isBusy {
                Button { model.stop() } label: {
                    Label(L.tr("Stop"), systemImage: "stop.fill")
                }
                .controlSize(.small)
                .help(L.tr("Cancel network and AI requests"))
            }

            Button { model.start(forceRegenerate: true) } label: {
                Label(L.tr("Regenerate"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            .disabled(model.isBusy)
            .help(L.tr("Ignore cache and build again"))

            Button { model.saveCurrentMap() } label: {
                Label(L.tr("Save"), systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)
            .disabled(!model.hasResult || model.isBusy)
            .help(model.currentRecordID == nil ? L.tr("Save this map as a separate record in the library") : L.tr("Save changes to this map"))

            Menu {
                Button(L.tr("JSON File")) { exportJSON() }
                Button(L.tr("Markdown File")) { exportMarkdown() }
                Divider()
                Button(L.tr("PNG Image")) { exportSnapshotJPEG(false) }
                Button(L.tr("JPEG Image")) { exportSnapshotJPEG(true) }
                Divider()
                Button(L.tr("Standalone HTML Page")) { exportStandaloneHTML() }
            } label: {
                Label(L.tr("Export"), systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!model.hasResult)

            Button {
                if let url = model.sourceURL { NSWorkspace.shared.open(url) }
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help(L.tr("Open source page in browser"))

            Button { MindMapToolWindow.shared.close() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(L.tr("Close Window (⌘W)"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: تب‌ها

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MindMapToolModel.Tab.allCases) { tab in
                Button {
                    model.tab = tab
                } label: {
                    Label(tab.label, systemImage: tab.icon)
                        .font(.system(size: 11, weight: model.tab == tab ? .semibold : .regular))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.tab == tab ? Color.accentColor.opacity(0.20) : .clear)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if model.phase == .result, !bridge.renderError.isNilOrBlank {
                Label(bridge.renderError ?? "", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: محتوا بر اساس حالت

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .ready:      readyState
        case .processing: processingState
        case .result:     resultState
        case .failed:     errorState
        case .paste:      pasteState
        }
    }

    /// حالت آماده: فیلد URL + توضیح + دکمهٔ شروع
    private var readyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L.tr("Design a Mind Map from Page Content"))
                .font(.title3.weight(.semibold))
            Text(L.tr("Enter a page URL or use the selected bookmark. Five steps run: fetch page, extract content, convert to Markdown, analyze with AI, and build the map."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            HStack(spacing: 8) {
                TextField("https://example.com/page", text: $model.urlText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 420)
                    .onSubmit { model.start() }
                Button {
                    model.start()
                } label: {
                    Label(L.tr("Start"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canStart)
            }

            if !model.rawMarkdown.isEmpty {
                Label(L.tr("This bookmark has saved text that can be used if reading fails."),
                      systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// حالت پردازش: چک‌لیست ۵ مرحله + توقف
    private var processingState: some View {
        VStack(alignment: .trailing, spacing: 14) {
            Spacer()
            Text(L.tr("Processing"))
                .font(.headline)
            Text(model.urlText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .textSelection(.enabled)

            VStack(alignment: .trailing, spacing: 8) {
                ForEach(Array(MindMapToolModel.Step.allCases.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 10) {
                        Text(step.title)
                            .font(.system(size: 13,
                                          weight: model.steps[index] == .running ? .semibold : .regular))
                            .foregroundStyle(model.steps[index] == .pending ? .secondary : .primary)
                        Spacer()
                        stepIndicator(model.steps[index])
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .frame(maxWidth: 460)

            HStack {
                Button(role: .destructive) { model.stop() } label: {
                    Label(L.tr("Stop"), systemImage: "stop.fill")
                }
                .controlSize(.large)
                Spacer()
            }
            .frame(maxWidth: 460)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    @ViewBuilder
    private func stepIndicator(_ state: MindMapToolModel.StepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small).scaleEffect(0.7)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help(message)
        }
    }

    /// حالت نتیجه: تب‌ها + نوار ابزار گراف
    private var resultState: some View {
        VStack(spacing: 0) {
            if model.tab == .map {
                graphToolbar
                Divider()
            }
            switch model.tab {
            case .map:
                ZStack {
                    MindMapWebView(bridge: bridge, json: model.mapJSON, dark: dark)
                    if bridge.nodeCount == 0 {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(L.tr("Rendering map…")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            case .tree:
                ScrollView {
                    Text(model.treeText)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(16)
                }
            case .markdown:
                ScrollView {
                    Text(model.markdownForExport)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(16)
                }
            case .json:
                ScrollView {
                    Text(prettyJSON(model.mapJSON))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(16)
                }
            }
        }
    }

    private var graphToolbar: some View {
        HStack(spacing: 6) {
            toolButton(L.tr("Zoom In (+)"), "plus.magnifyingglass") { bridge.zoomIn() }
            toolButton(L.tr("Zoom Out (-)"), "minus.magnifyingglass") { bridge.zoomOut() }
            toolButton(L.tr("Fit to Window (0)"), "arrow.down.right.and.arrow.up.left") { bridge.fit() }
            Divider().frame(height: 16)
            toolButton(L.tr("Add Child Node (Tab)"), "plus.circle") { bridge.addChild() }
            toolButton(L.tr("Add Sibling Node (Enter)"), "plus.square.on.square") { bridge.addSibling() }
            toolButton(L.tr("Delete Selected Node with Subtree (Delete)"), "xmark.circle") { bridge.deleteSelected() }
            Divider().frame(height: 16)
            toolButton(L.tr("Expand All Branches"), "rectangle.expand.vertical") { bridge.expandAll() }
            toolButton(L.tr("Collapse All Branches"), "rectangle.compress.vertical") { bridge.collapseAll() }

            Menu {
                ForEach(MindMapLayout.allCases) { layout in
                    Button {
                        layoutName = layout.rawValue
                        bridge.setLayout(layout.rawValue)
                    } label: {
                        if layoutName == layout.rawValue {
                            Label(layout.label, systemImage: "checkmark")
                        } else {
                            Label(layout.label, systemImage: layout.icon)
                        }
                    }
                }
            } label: {
                Image(systemName: "rectangle.split.3x1")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L.tr("Layout: tree / org / radial / outline / both sides"))

            Menu {
                ForEach(MindMapTheme.allCases) { theme in
                    Button {
                        themeName = theme.rawValue
                        bridge.setThemeName(theme.rawValue)
                    } label: {
                        if themeName == theme.rawValue {
                            Label(theme.label, systemImage: "checkmark")
                        } else {
                            Label(theme.label, systemImage: theme.icon)
                        }
                    }
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L.tr("Map Color Theme"))

            Menu {
                Button {
                    rootLeft = true
                    bridge.setDirection(.rootLeft)
                } label: {
                    Label(MindMapDirection.rootLeft.label,
                          systemImage: rootLeft ? "checkmark" : "arrow.right.to.line")
                }
                Button {
                    rootLeft = false
                    bridge.setDirection(.rootRight)
                } label: {
                    Label(MindMapDirection.rootRight.label,
                          systemImage: !rootLeft ? "checkmark" : "arrow.left.to.line")
                }
            } label: {
                Image(systemName: rootLeft ? "arrow.right.to.line" : "arrow.left.to.line")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L.tr("Layout direction: root left (default) or root right"))

            Spacer()
            Button { bridge.openSearch() } label: {
                Label(L.tr("Search"), systemImage: "magnifyingglass")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help(L.tr("Search node text and highlight results"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func toolButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    /// حالت خطا
    private var errorState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.orange)
            Text(model.errorTitle ?? L.tr("Error"))
                .font(.headline)
                .multilineTextAlignment(.center)

            if let detail = model.errorDetail, !detail.isEmpty {
                DisclosureGroup(L.tr("Technical Details")) {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(8)
                }
                .frame(maxWidth: 560)
            }

            VStack(spacing: 8) {
                Button { model.retry(longer: false) } label: {
                    Label(L.tr("Retry"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                Button { model.retry(longer: true) } label: {
                    Label(L.tr("Retry with Longer Timeout"), systemImage: "timer")
                }
                Button { model.beginPaste() } label: {
                    Label(L.tr("Paste Text Manually"), systemImage: "doc.on.clipboard")
                }
                HStack(spacing: 8) {
                    Button {
                        if let url = model.sourceURL { NSWorkspace.shared.open(url) }
                    } label: {
                        Label(L.tr("Open in Browser"), systemImage: "safari")
                    }
                    Button { MindMapToolWindow.shared.close() } label: {
                        Label(L.tr("Close"), systemImage: "xmark")
                    }
                }
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// چسباندن دستی
    private var pasteState: some View {
        VStack(alignment: .trailing, spacing: 12) {
            Spacer()
            Text(L.tr("Paste Text Manually"))
                .font(.headline)
            Text(L.tr("Paste the text here; it enters the pipeline at the AI analysis step."))
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(L.tr("Title (Optional)"), text: $model.pasteTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $model.pasteBody)
                .font(.system(size: 12))
                .frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))

            HStack {
                Button(role: .destructive) { model.cancelPaste() } label: { Text(L.tr("Discard")) }
                Button { model.continuePaste() } label: {
                    Label(L.tr("Continue"), systemImage: "arrow.left")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.pasteBody.trimmed.isEmpty)
                Spacer()
            }
            Spacer()
        }
        .padding(24)
    }

    // MARK: نوار وضعیت

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isBusy {
                ProgressView().controlSize(.small).scaleEffect(0.65)
                Text(model.stepNote ?? L.tr("Running…"))
                    .font(.system(size: 11))
            } else if !model.statusText.isEmpty {
                Label(model.statusText, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(L.tr("Ready"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            if let warning = model.warningText {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            if let error = model.errorTitle, model.phase != .failed {
                Label(error, systemImage: "xmark.octagon")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Spacer()

            if model.hasResult {
                Text(L.tr("Drag nodes to rearrange; double-click a node to edit its text."))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(.bar)
    }

    // MARK: خروجی

    private func prettyJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return json }
        return text
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mindmap.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? prettyJSON(model.mapJSON).write(to: url, atomically: true, encoding: .utf8)
        model.statusText = L.tr("JSON export saved")
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mindmap.md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.markdownForExport.write(to: url, atomically: true, encoding: .utf8)
        model.statusText = L.tr("Markdown export saved")
    }

    // MARK: خروجی‌های تصویری و سندی

    /// عکس فوری از WebView رندر (کل نقشه پس از fit داخل دید است)
    private func withSnapshot(_ receive: @escaping (NSImage) -> Void) {
        guard let webView = bridge.webView, bridge.loaded else {
            model.errorTitle = L.tr("Render view is not ready.")
            return
        }
        let config = WKSnapshotConfiguration()
        webView.takeSnapshot(with: config) { image, _ in
            Task { @MainActor in
                guard let image else {
                    model.errorTitle = L.tr("Failed to capture the map image.")
                    return
                }
                receive(image)
            }
        }
    }

    private func baseName() -> String {
        MindMapExport.safeFileName(model.pageTitle.isEmpty ? "mindmap" : model.pageTitle)
    }

    private func exportSnapshotJPEG(_ jpeg: Bool) {
        withSnapshot { image in
            let data = jpeg ? MindMapExport.jpegData(from: image) : MindMapExport.pngData(from: image)
            guard let data else {
                model.errorTitle = L.tr("Image conversion failed.")
                return
            }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "\(baseName()).\(jpeg ? "jpg" : "png")"
            panel.allowedContentTypes = [jpeg ? .jpeg : .png]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
                model.statusText = L.tf("%@ image saved", jpeg ? "JPEG" : "PNG")
            } catch {
                model.errorTitle = L.tf("Failed to save image: %@", error.localizedDescription)
            }
        }
    }

    /// HTML مستقل: کل بوم رندر + دادهٔ نقشه داخل یک فایل (بدون هیچ منبع ریموت)
    private func exportStandaloneHTML() {
        guard let files = MindMapExport.bundleFiles() else {
            model.errorTitle = L.tr("Render files not found in the app bundle.")
            return
        }
        guard let html = MindMapExport.standaloneHTML(indexHTML: files.index, css: files.css,
                                                      libraryJS: files.js, mapJSON: model.mapJSON,
                                                      pageTitle: model.pageTitle) else {
            model.errorTitle = L.tr("Map data is not valid for HTML export.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(baseName()).html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            model.statusText = L.tr("Standalone HTML page saved (works offline)")
        } catch {
            model.errorTitle = L.tf("Failed to save HTML: %@", error.localizedDescription)
        }
    }

    private func saveToDisk() {
        model.markSaved()
        model.statusText = L.tr("Full save will be enabled in phase 4 (database)")
    }
}

// MARK: - کمکی

private extension Optional where Wrapped == String {
    var isNilOrBlank: Bool { self?.trimmed.isEmpty ?? true }
}
