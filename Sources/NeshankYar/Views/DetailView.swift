import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct DetailView: View {
    @ObservedObject private var lib = Library.shared
    @State private var noteDraft = ""
    @State private var newTag = ""
    @State private var confirmDelete = false
    @State private var confirmPurge = false
    @State private var showAssistant = false
    /// پل رندر نقشهٔ ذخیره‌شده در همین پنل (جدا از پنجرهٔ ابزار)
    @StateObject private var mapBridge = MindMapRenderBridge()
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkScheme: Bool { colorScheme == .dark }

    /// نمایش نقشهٔ ذخیره‌شده در پنل جزئیات، دقیقاً مثل پیش‌نمایش مرورگر.
    private func renderMap(_ map: MindMapRecord) {
        guard !map.mindMapJSON.isEmpty else { return }
        mapBridge.clear()
        mapBridge.render(map.mindMapJSON)
        mapBridge.setTheme(dark: isDarkScheme)
        // جابه‌جایی/ویرایش/افزودن و حذف گره در همین پنل، بی‌درنگ در همان رکورد ذخیره می‌شود
        mapBridge.onMapChange = { [map] json in
            guard lib.selectedMindMapId == map.id, !json.isEmpty else { return }
            _ = lib.updateMindMap(id: map.id, title: map.displayTitle, sourceURL: map.sourceURL,
                                  markdown: map.rawMarkdown, json: json,
                                  model: map.model, language: map.language)
        }
    }

    private var bookmark: Bookmark? {
        guard let id = lib.selectedId else { return nil }
        return lib.bookmark(id: id)
    }

    private var selectedMindMap: MindMapRecord? {
        guard lib.scope == .mindMaps, let id = lib.selectedMindMapId else { return nil }
        return lib.mindMap(id: id)
    }

    var body: some View {
        Group {
            if let map = selectedMindMap {
                mindMapDetail(map)
            } else if let b = bookmark {
                detail(b)
            } else {
                placeholder
            }
        }
        .onAppear { syncNote() }
        .onChange(of: lib.selectedId) { _ in syncNote() }
    }

    private func syncNote() {
        noteDraft = bookmark?.note ?? ""
        newTag = ""
    }

    // MARK: حالت خالی

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L.tr("Select a bookmark from the list"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: جزئیات نقشهٔ ذخیره‌شده (نقشه‌ها در جدول مستقل mind_maps هستند)

    private func mindMapDetail(_ map: MindMapRecord) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(map.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(map.sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 6)
                Button { lib.selectedMindMapId = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(L.tr("Close Map Details"))
            }
            .padding(14)
            Divider()

            // نوار ابزار نقشه: زوم، جمع/باز، افزودن/حذف گره و خروجی‌ها
            HStack(spacing: 6) {
                toolButton(L.tr("Zoom Out"), "minus.magnifyingglass") { mapBridge.zoomOut() }
                toolButton(L.tr("Zoom In"), "plus.magnifyingglass") { mapBridge.zoomIn() }
                toolButton(L.tr("Fit to Window"), "arrow.down.right.and.arrow.up.left") { mapBridge.fit() }
                toolButton(L.tr("Expand All"), "rectangle.expand.vertical") { mapBridge.expandAll() }
                toolButton(L.tr("Collapse All"), "rectangle.compress.vertical") { mapBridge.collapseAll() }

                Divider().frame(height: 16)

                toolButton(L.tr("Add Child Node"), "plus.rectangle.on.rectangle") { mapBridge.addChild() }
                toolButton(L.tr("Delete Selected Node"), "minus.rectangle") { mapBridge.deleteSelected() }

                Divider().frame(height: 16)

                Menu {
                    Button(L.tr("JSON File")) { exportMapJSON(map) }
                    Button(L.tr("Markdown File")) { exportMapMarkdown(map) }
                    Divider()
                    Button(L.tr("PNG Image")) { exportMapImage(map, jpeg: false) }
                    Button(L.tr("JPEG Image")) { exportMapImage(map, jpeg: true) }
                    Divider()
                    Button(L.tr("Standalone HTML Page")) { exportMapHTML(map) }
                } label: {
                    Label(L.tr("Export"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L.tr("Export map (JSON, Markdown, image, HTML)"))
                .disabled(mapBridge.nodeCount == 0)

                Spacer()

                Button {
                    mapBridge.openSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help(L.tr("Search in nodes"))

                Label(L.tf("%@ nodes", Digits.fa(map.nodeCount)), systemImage: "circle.grid.3x3")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider()

            // نقشهٔ ذخیره‌شده همانند مرورگر در همین پنل رندر می‌شود.
            ZStack {
                MindMapWebView(bridge: mapBridge, json: map.mindMapJSON, dark: isDarkScheme)
                    .id(map.id)
                if mapBridge.nodeCount == 0 {
                    ProgressView()
                }
            }
            .frame(maxHeight: .infinity)
            .onAppear { renderMap(map) }
            .onChange(of: map.id) { _ in renderMap(map) }

            Divider()
            HStack(spacing: 8) {
                Button {
                    MindMapToolWindow.shared.show(record: map)
                } label: {
                    Label(L.tr("Open Map"), systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(.borderedProminent)
                .help(L.tr("View and edit the saved mind map"))

                Button {
                    MindMapToolWindow.shared.show(url: map.sourceURL, title: map.displayTitle)
                } label: {
                    Label(L.tr("New Map from This Page"), systemImage: "arrow.clockwise")
                }
                .help(L.tr("Saves as a separate record; the previous map is kept"))

                Spacer()

                Button(role: .destructive) {
                    lib.deleteMindMaps(ids: [map.id])
                } label: {
                    Label(L.tr("Delete Map"), systemImage: "trash")
                }
                .help(L.tr("Deletes only this map; the bookmark stays untouched"))
            }
            .controlSize(.small)
            .padding(12)
        }
    }

    private func toolButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.borderless)
            .help(title)
    }

    // MARK: خروجی نقشهٔ ذخیره‌شده

    private func savePanel(_ name: String, _ type: UTType?) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        if let type { panel.allowedContentTypes = [type] }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func exportMapJSON(_ map: MindMapRecord) {
        guard let url = savePanel("\(MindMapExport.safeFileName(map.displayTitle)).json", .json) else { return }
        try? prettyMapJSON(map.mindMapJSON).write(to: url, atomically: true, encoding: .utf8)
        lib.notify(L.tr("JSON export saved"))
    }

    private func exportMapMarkdown(_ map: MindMapRecord) {
        guard let url = savePanel("\(MindMapExport.safeFileName(map.displayTitle)).md", .plainText) else { return }
        try? map.rawMarkdown.write(to: url, atomically: true, encoding: .utf8)
        lib.notify(L.tr("Markdown export saved"))
    }

    private func exportMapImage(_ map: MindMapRecord, jpeg: Bool) {
        mapBridge.snapshot { image in
            let data = jpeg ? MindMapExport.jpegData(from: image) : MindMapExport.pngData(from: image)
            guard let data,
                  let url = savePanel("\(MindMapExport.safeFileName(map.displayTitle)).\(jpeg ? "jpg" : "png")",
                                      jpeg ? .jpeg : .png) else { return }
            try? data.write(to: url)
            lib.notify(L.tf("Image %@ saved", jpeg ? "JPEG" : "PNG"))
        }
    }

    private func exportMapHTML(_ map: MindMapRecord) {
        guard let files = MindMapExport.bundleFiles(),
              let html = MindMapExport.standaloneHTML(indexHTML: files.index, css: files.css,
                                                      libraryJS: files.js, mapJSON: map.mindMapJSON,
                                                      pageTitle: map.displayTitle),
              let url = savePanel("\(MindMapExport.safeFileName(map.displayTitle)).html", .html) else { return }
        try? html.write(to: url, atomically: true, encoding: .utf8)
        lib.notify(L.tr("Standalone HTML page saved"))
    }

    private func prettyMapJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj,
                                                       options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return json }
        return text
    }

    // MARK: جزئیات

    private func detail(_ b: Bookmark) -> some View {
        VStack(spacing: 0) {
            header(b)
            Divider()
            metaBar(b)
            if b.isTrashed {
                Divider()
                trashBanner(b)
            }
            if b.isDead {
                Divider()
                deadBanner(b)
            }
            Divider()
            noteArea(b)
            Divider()
            previewSection(b)
            Divider()
            footer(b)
        }
        .confirmationDialog(L.tr("Move this bookmark to Trash?"), isPresented: $confirmDelete) {
            Button(L.tr("Move to Trash"), role: .destructive) {
                lib.delete(ids: [b.id])
            }
        } message: {
            Text(L.tr("You can undo with ⌘Z."))
        }
        .confirmationDialog(L.tr("Delete this bookmark permanently?"), isPresented: $confirmPurge) {
            Button(L.tr("Delete Permanently"), role: .destructive) {
                lib.purge(ids: [b.id])
            }
        } message: {
            Text(L.tr("Also erased from the Trash; this cannot be undone."))
        }
        .sheet(isPresented: $showAssistant) {
            AssistantSheet(bookmark: b)
        }
    }

    // MARK: سربرگ

    private func header(_ b: Bookmark) -> some View {
        HStack(alignment: .top, spacing: 12) {
            FaviconView(path: b.favicon, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(b.displayTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 7) {
                    Text(b.domain)
                    Text("·")
                    Text(Dates.persian(b.createdAt))
                    if !b.isRead {
                        Text("·")
                        Text(L.tr("Unread"))
                            .foregroundStyle(.orange)
                    }
                    if b.isArchived {
                        Text("·")
                        Text(L.tr("Archived"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button {
                    showAssistant = true
                } label: {
                    Image(systemName: "sparkles")
                }
                .help(L.tr("Assistant: is this page useful for me? (⌘⇧D)"))
                .foregroundStyle(AppTheme.accent ?? .accentColor)
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button {
                    lib.open(b)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help(L.tr("Open"))

                Button {
                    lib.copyURL(b)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help(L.tr("Copy URL"))

                Button {
                    lib.setStarred(b.id, !b.starred)
                } label: {
                    Image(systemName: b.starred ? "star.fill" : "star")
                }
                .help(L.tr("Toggle Star"))
                .foregroundStyle(b.starred ? Color.yellow : Color.primary)

                Menu {
                    if b.isTrashed {
                        Button(L.tr("Restore from Trash")) {
                            lib.restore(ids: [b.id])
                        }
                        Button(L.tr("Delete Permanently"), role: .destructive) {
                            confirmPurge = true
                        }
                        Divider()
                    }
                    Button(L.tr("Edit…")) {
                        lib.editing = .edit(b)
                    }
                    Divider()
                    Button(L.tr("Ask the Assistant…")) {
                        showAssistant = true
                    }
                    Divider()
                    Button(L.tr("Recheck")) {
                        Task { await lib.recheck(id: b.id) }
                    }
                    if b.screenshot == nil, b.isWebPage {
                        Button(L.tr("Capture Page Screenshot")) {
                            Task { await lib.captureScreenshot(id: b.id) }
                        }
                    }
                    if !b.isTrashed {
                        Divider()
                        Button(L.tr("Delete (Move to Trash)"), role: .destructive) {
                            confirmDelete = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }

                Button {
                    lib.selectedId = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .help(L.tr("Close Panel"))
                .accessibilityLabel(L.tr("Close Details Panel"))
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: پوشه و برچسب‌ها

    private func metaBar(_ b: Bookmark) -> some View {
        HStack(spacing: 10) {
            Picker(L.tr("Folder"), selection: folderBinding(b)) {
                ForEach(lib.folderOptions()) { option in
                    Text(option.label).tag(Optional(option.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 190)

            Divider()
                .frame(height: 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(b.tags, id: \.self) { tag in
                        TagChip(name: tag) {
                            lib.removeTag(bookmarkId: b.id, name: tag)
                        }
                    }
                    TextField(L.tr("Add Tag"), text: $newTag)
                        .textFieldStyle(.plain)
                        .frame(width: 100)
                        .onSubmit {
                            lib.addTag(bookmarkId: b.id, name: newTag)
                            newTag = ""
                        }
                }
                .padding(.vertical, 2)
            }

            Spacer()

            Button {
                lib.editing = .edit(b)
            } label: {
                Image(systemName: "pencil")
            }
            .help(L.tr("Edit Bookmark"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private func folderBinding(_ b: Bookmark) -> Binding<Int64?> {
        Binding(
            get: { Optional(b.folderId ?? 0) },   // ۰ = گزینهٔ «بدون پوشه» تا ردیف خالی نمایش داده نشود
            set: { newValue in
                lib.setFolder([b.id], folderId: newValue == 0 ? nil : newValue)
            }
        )
    }

    // MARK: هشدار لینک مرده

    private func deadBanner(_ b: Bookmark) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(L.tr("This link appears to be dead"))
                .font(.callout)
            Spacer()
            Button(L.tr("Recheck")) {
                Task { await lib.recheck(id: b.id) }
            }
            .controlSize(.small)
            Button(L.tr("Open in Browser")) {
                lib.open(b)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: یادداشت

    private func noteArea(_ b: Bookmark) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(L.tr("Note"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
                .padding(.top, 3)

            TextField(L.tr("Write your note…"), text: $noteDraft, axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.plain)
                .textSelection(.enabled)

            if noteDraft.trimmed != b.note.trimmed {
                Button(L.tr("Save")) {
                    lib.updateNote(b.id, noteDraft)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: پیش‌نمایش وب

    private func previewSection(_ b: Bookmark) -> some View {
        VStack(spacing: 0) {
            previewBar(b)
            Divider()
            previewBody(b)
        }
    }

    private func previewBar(_ b: Bookmark) -> some View {
        HStack(spacing: 10) {
            Spacer()

            if b.isWebPage, b.screenshot == nil {
                Button(L.tr("Capture Page Screenshot")) { capture(b) }
                    .controlSize(.small)
                    .help(L.tr("Captures a real screenshot of the page and shows it on cards"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private func capture(_ b: Bookmark) {
        Task { await lib.captureScreenshot(id: b.id) }
    }

    @ViewBuilder
    private func previewBody(_ b: Bookmark) -> some View {
        if b.isWebPage, let url = URL(string: b.url) {
            WebView(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(b.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L.tr("Preview is only available for web pages"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(b.url)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: زباله‌دان

    private func trashBanner(_ b: Bookmark) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(.secondary)
            Text(L.tr("This bookmark is in the Trash"))
                .font(.callout)
            if let d = b.deletedAt {
                Text(L.tf("In Trash since %@", Dates.persian(d)))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(L.tr("Restore")) {
                lib.restore(ids: [b.id])
            }
            Button(L.tr("Delete Permanently"), role: .destructive) {
                confirmPurge = true
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    // MARK: پاورقی

    private func footer(_ b: Bookmark) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.tf("Added: %@", Dates.persianDateTime(b.createdAt)))
                if let checked = b.checkedAt {
                    Text(L.tf("Last checked: %@", Dates.persianDateTime(checked)))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Spacer()

            Button(L.tr("Open in Browser")) {
                lib.open(b)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - پیش‌نمایش وب

struct WebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let target = url.absoluteString
        guard context.coordinator.loaded != target else { return }
        context.coordinator.loaded = target
        webView.load(URLRequest(url: url))
    }

    final class Coordinator {
        var loaded: String?
    }
}
