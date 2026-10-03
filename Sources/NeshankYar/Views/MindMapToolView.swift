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
    /// کارت راهنمای اتصال سرویس هوش مصنوعی — بار اول خودکار باز، بعد از تأیید بسته
    @State private var showAISetup = false

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
        .onAppear {
            bridge.onMapChange = { model.canvasDidChange($0) }
            // اولین بار که سرویس وصل نیست، راهنمای اتصال همان‌جا باز است
            if showAISetup == false, !AIConfig.load().isConfigured { showAISetup = true }
        }
        .onChange(of: model.apiProblem) { problem in
            // خطای سرویس هوش مصنوعی → راهنمای اتصال دوباره باز می‌شود
            if problem { showAISetup = true }
        }
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
            // رندر با MindMapWebView.updateNSView انجام می‌شود؛ رندر دوباره از این‌جا
            // چرخهٔ «رندر → به‌روزرسانی → رندر» می‌ساخت و با تعویض تب قفل می‌کرد.
            if json.isEmpty { bridge.clear() }
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

            Spacer(minLength: 10)

            // اقدامات اصلی — هر دکمه با آیکون و برچسب
            HStack(spacing: 10) {
                Button {
                    if model.hasResult, model.phase == .result {
                        model.start(forceRegenerate: true)
                    } else {
                        model.start()
                    }
                } label: {
                    Label(model.hasResult ? L.tr("Generate") : L.tr("Start"), systemImage: "play.fill")
                        .padding(.horizontal, 2)
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
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(model.isBusy)
                .help(L.tr("Ignore cache and build again"))

                Button { model.saveCurrentMap() } label: {
                    Label(L.tr("Save"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
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
                        .font(.system(size: 12))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!model.hasResult)
                .help(L.tr("Export the map in different formats"))

                Button {
                    if let url = model.sourceURL { NSWorkspace.shared.open(url) }
                } label: {
                    Label(L.tr("Source Page"), systemImage: "safari")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(L.tr("Open source page in browser"))

                Button { MindMapToolWindow.shared.close() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(L.tr("Close Window (⌘W)"))
            }
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: تب‌های نما

    private var tabBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(MindMapToolModel.Tab.allCases) { tab in
                    let active = model.tab == tab
                    Button {
                        model.tab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(tab.label)
                                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background {
                            Capsule().fill(active
                                           ? AnyShapeStyle(Color.accentColor.opacity(0.22))
                                           : AnyShapeStyle(Color.primary.opacity(0.04)))
                        }
                        .overlay {
                            Capsule().strokeBorder(active
                                                   ? Color.accentColor.opacity(0.5)
                                                   : Color.primary.opacity(0.06))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.04)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))

            Spacer()

            if model.phase == .result, !bridge.renderError.isNilOrBlank {
                Label(bridge.renderError ?? "", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
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
            if showAISetup {
                AISetupCard(problemHint: model.apiProblem) {
                    withAnimation { showAISetup = false }
                    model.apiProblem = false
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
                // میانبر تنظیمات سرویس هوش مصنوعی — همان‌جا، بدون رفتن به تنظیمات
                Button {
                    withAnimation { showAISetup.toggle() }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help(L.tr("AI Setup"))
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
            // هر چهار نما زنده می‌مانند (فقط مخفی می‌شوند) تا وب‌ویو با تعویض تب
            // نابود و دوباره بارگذاری نشود — همان که اسپینر ابدی می‌ساخت.
            ZStack {
                mapPane
                    .opacity(model.tab == .map ? 1 : 0)
                    .allowsHitTesting(model.tab == .map)
                treePane
                    .opacity(model.tab == .tree ? 1 : 0)
                    .allowsHitTesting(model.tab == .tree)
                markdownPane
                    .opacity(model.tab == .markdown ? 1 : 0)
                    .allowsHitTesting(model.tab == .markdown)
                jsonPane
                    .opacity(model.tab == .json ? 1 : 0)
                    .allowsHitTesting(model.tab == .json)
            }
        }
    }

    private var mapPane: some View {
        ZStack {
            MindMapWebView(bridge: bridge, json: model.mapJSON, dark: dark)
            if bridge.nodeCount == 0 {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(L.tr("Rendering map…")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var treePane: some View {
        ScrollView {
            Text(model.treeText)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(16)
        }
    }

    private var markdownPane: some View {
        ScrollView {
            Text(model.markdownForExport)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(16)
        }
    }

    private var jsonPane: some View {
        ScrollView {
            Text(prettyJSON(model.mapJSON))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(16)
        }
    }

    private var graphToolbar: some View {
        HStack(spacing: 0) {
            // نوار ابزار با برچسب — در پنجرهٔ باریک اسکرول افقی می‌شود
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    // گروه ویرایش گره‌ها
                    labeledTool(L.tr("New Child Node"), "plus.circle") { bridge.addChild() }
                        .help(L.tr("Add Child Node (Tab)"))
                    labeledTool(L.tr("New Sibling Node"), "plus.square.on.square") { bridge.addSibling() }
                        .help(L.tr("Add Sibling Node (Enter)"))
                    labeledTool(L.tr("Delete Node"), "xmark.circle") { bridge.deleteSelected() }
                        .help(L.tr("Delete Selected Node with Subtree (Delete)"))

                    toolDivider

                    // گروه نمایش شاخه‌ها
                    labeledTool(L.tr("Expand All"), "rectangle.expand.vertical") { bridge.expandAll() }
                        .help(L.tr("Expand All Branches"))
                    labeledTool(L.tr("Collapse All"), "rectangle.compress.vertical") { bridge.collapseAll() }
                        .help(L.tr("Collapse All Branches"))

                    toolDivider

                    // گروه نما
                    labeledTool(L.tr("Fit View"), "arrow.down.right.and.arrow.up.left") { bridge.fit() }
                        .help(L.tr("Fit to Window (0)"))
                    labeledTool(L.tr("Zoom In"), "plus.magnifyingglass") { bridge.zoomIn() }
                        .help(L.tr("Zoom In (+)"))
                    labeledTool(L.tr("Zoom Out"), "minus.magnifyingglass") { bridge.zoomOut() }
                        .help(L.tr("Zoom Out (-)"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }

            // منوی نمایش و جستجو — همیشه‌نمایان (بیرون از اسکرول)
            Divider().frame(height: 18)
            displayMenu
            Divider().frame(height: 18)

            Button { bridge.openSearch() } label: {
                Label(L.tr("Search"), systemImage: "magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 10)
            .help(L.tr("Search node text and highlight results"))
        }
        .background(Color.primary.opacity(0.025))
    }

    /// دکمهٔ ابزار با آیکون و برچسب
    private func labeledTool(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.045)))
        }
        .buttonStyle(.plain)
    }

    private var toolDivider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 4)
    }

    /// حاشیهٔ گرادیان نئونی متحرک — دور دکمهٔ «قالب‌های مایند مپ»
    private struct AnimatedNeonBorder: View {
        var cornerRadius: CGFloat = 9
        var lineWidth: CGFloat = 1.6

        var body: some View {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3) / 3 * 360
                let angle = Angle.degrees(t)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: [.cyan, .purple, .pink, .orange, .yellow, .green, .cyan],
                            center: .center,
                            startAngle: angle,
                            endAngle: angle + .degrees(360)
                        ),
                        lineWidth: lineWidth
                    )
                    .shadow(color: Color.cyan.opacity(0.55), radius: 3)
            }
            .allowsHitTesting(false)
        }
    }

    /// منوی یکپارچهٔ قالب‌ها: چیدمان، تم رنگی و جهت ریشه — با حاشیهٔ نئونی متحرک
    private var displayMenu: some View {
        Menu {
            Section(L.tr("Layout")) {
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
            }
            Section(L.tr("Map Theme")) {
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
            }
            Section(L.tr("Direction")) {
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
            }
        } label: {
            Label(L.tr("Mind Map Templates"), systemImage: "paintpalette")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .overlay {
            AnimatedNeonBorder()
        }
        .help(L.tr("Mind map templates: layout, color theme and root direction"))
    }

    /// حالت خطا
    private var errorState: some View {
        VStack(spacing: 14) {
            // خطای سرویس هوش مصنوعی → کارت راهنمای اتصال همین‌جا باز می‌شود
            if model.apiProblem {
                AISetupCard(problemHint: true) {
                    model.apiProblem = false
                }
                .transition(.opacity)
            }
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
