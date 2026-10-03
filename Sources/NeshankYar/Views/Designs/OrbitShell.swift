import SwiftUI
import AppKit

// MARK: - طراحی «مدار» (Orbit)
// لانچر تایل‌بزرگ: صفحه‌بندی عمودی با نقاط صفحه، جستجوی مرکزی،
// داک بخش‌ها پایین پنجره و تایل‌های آیکون‌محور (فاوآیکون/تصویر بالای عنوان).

struct OrbitShell: View {
    @ObservedObject private var lib = Library.shared
    @FocusState private var searchFocused: Bool
    @State private var page = 0

    private let perRow = 5
    private let rows = 3
    private var perPage: Int { perRow * rows }

    var body: some View {
        VStack(spacing: 0) {
            topSearch
            Spacer(minLength: 0)
            tileArea
            Spacer(minLength: 0)
            bottomDock
        }
        .overlay(alignment: .leading) { detailOverlay }
        .animation(.easeInOut(duration: 0.2), value: lib.selectedId)
        .animation(.easeInOut(duration: 0.2), value: lib.selectedMindMapId)
    }

    // MARK: جستجوی مرکزی

    private var topSearch: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: lib.scope == .mindMaps ? "brain.head.profile" : "bookmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                TextField(lib.scope == .mindMaps
                          ? L.tr("Search mind maps by name, URL or text…")
                          : L.tr("Search in title, URL, tag and note…"),
                          text: $lib.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($searchFocused)
                if !lib.query.isEmpty {
                    Button { lib.query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button { newAction() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text(lib.scope == .mindMaps ? L.tr("New Map") : L.tr("New Bookmark"))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor.opacity(0.95), Color.accentColor],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                }
                .buttonStyle(.plain)
                .help(lib.scope == .mindMaps ? L.tr("New Map") : L.tr("New Bookmark (⌘N)"))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .frame(maxWidth: 640)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1.5)
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.horizontal, 24)
    }

    // MARK: محدودهٔ تایل‌ها + صفحه‌بندی

    private var items: [Bookmark] { lib.results }
    private var maps: [MindMapRecord] { lib.mindMaps }
    private var isMapMode: Bool { lib.scope == .mindMaps }
    private var pageCount: Int {
        let count = isMapMode ? maps.count : items.count
        return max(1, Int(ceil(Double(count) / Double(perPage))))
    }

    private var tileArea: some View {
        let empty = isMapMode ? maps.isEmpty : items.isEmpty
        return VStack(spacing: 14) {
            if empty {
                orbitEmpty
            } else {
                tilesGrid
                pageDots
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var tilesGrid: some View {
        let currentPage = min(page, pageCount - 1)
        let sliceStart = currentPage * perPage

        return VStack(spacing: 18) {
            if isMapMode {
                let visible = Array(maps.dropFirst(sliceStart).prefix(perPage))
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 18) {
                        ForEach(0..<perRow, id: \.self) { c in
                            let i = r * perRow + c
                            if i < visible.count {
                                OrbitMapTile(record: visible[i],
                                             selected: lib.selectedMindMapId == visible[i].id,
                                             onSelect: { lib.selectedMindMapId = visible[i].id })
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            } else {
                let visible = Array(items.dropFirst(sliceStart).prefix(perPage))
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 18) {
                        ForEach(0..<perRow, id: \.self) { c in
                            let i = r * perRow + c
                            if i < visible.count {
                                OrbitTile(bookmark: visible[i],
                                          selected: lib.selectedId == visible[i].id,
                                          onSelect: { lib.selectedId = visible[i].id },
                                          onOpen: { ShellSupport.openURL(visible[i].url) })
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .id(currentPage) // انیمیشن ورود هنگام تعویض صفحه
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
        .animation(.easeInOut(duration: 0.2), value: currentPage)
    }

    private var pageDots: some View {
        HStack(spacing: 10) {
            if pageCount > 1 {
                Button {
                    page = max(0, page - 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(page > 0 ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
                .disabled(page == 0)
            }

            ForEach(0..<pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .onTapGesture { page = i }
            }

            if pageCount > 1 {
                Button {
                    page = min(pageCount - 1, page + 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(page < pageCount - 1 ? .primary : .tertiary)
                }
                .buttonStyle(.plain)
                .disabled(page >= pageCount - 1)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: page)
        .padding(.bottom, 10)
    }

    // MARK: داک پایین (بخش‌ها + ابزار)

    private var bottomDock: some View {
        HStack(spacing: 14) {
            dockItem(.all, icon: "square.grid.3x3.fill", label: L.tr("All"))
            dockItem(.starred, icon: "star.fill", label: L.tr("Starred"))
            dockItem(.unfiled, icon: "tray.fill", label: L.tr("Unfiled"))
            dockItem(.mindMaps, icon: "brain.head.profile", label: L.tr("Mind Maps"))
            dockItem(.trash, icon: "trash.fill", label: L.tr("Trash"))

            Divider().frame(height: 30).opacity(0.5)

            dockMenu(L.tr("Folders"), icon: "folder.fill") {
                Section(L.tr("Folders")) {
                    ForEach(lib.folders) { folder in
                        Button(folder.name) {
                            lib.scope = .folder(folder.id)
                            lib.selectedId = nil
                            page = 0
                        }
                    }
                }
                if !lib.savedFilters.isEmpty {
                    Section(L.tr("Saved Filters")) {
                        ForEach(lib.savedFilters) { filter in
                            Button(filter.name) {
                                lib.apply(filter)
                                lib.selectedId = nil
                                page = 0
                            }
                        }
                    }
                }
            }

            dockMenu(L.tr("More"), icon: "ellipsis.circle") {
                ShellToolsSection()

                Divider()

                Picker(L.tr("Sort"), selection: Binding(
                    get: { lib.sort },
                    set: { lib.sort = $0 }
                )) {
                    ForEach(Library.Sort.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }

                if lib.scope == .trash {
                    Divider()
                    Button(L.tr("Restore All")) { lib.restore(ids: lib.results.map(\.id)) }
                        .disabled(lib.results.isEmpty)
                    Button(L.tr("Empty Trash"), role: .destructive) { lib.emptyTrash() }
                        .disabled(lib.counts.trash == 0)
                }

                Divider()
                Button {
                    Task { await lib.checkAllLinks() }
                } label: {
                    Text(lib.isChecking ? L.tr("Checking…") : L.tr("Check All Links"))
                }
                .disabled(lib.isChecking)
                Button(L.tr("Import from Browser File…")) {
                    FilePanels.pickImport { url in
                        Task { await lib.importHTML(from: url) }
                    }
                }
                Button(L.tr("Export HTML…")) {
                    FilePanels.pickExport { url in
                        lib.exportHTML(to: url)
                    }
                }
            }

            Divider().frame(height: 30).opacity(0.5)

            dockFeatured("arrow.down.circle.fill", L.tr("Video Downloader")) {
                ShellTools.openVideoDownload()
            }

            dockAction("bubble.left.and.bubble.right.fill", L.tr("Chats (⌘⇧C)")) {
                NotificationCenter.default.post(name: .showChats, object: nil)
            }
            dockAction("gearshape.fill", L.tr("Settings (⌘,)")) {
                AppActions.openSettings()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color.primary.opacity(0.001), Color.primary.opacity(0.05)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// آیتم داک با منو (پوشه‌ها/ابزارها)
    private func dockMenu(_ label: String, icon: String,
                          @ViewBuilder content: () -> some View) -> some View {
        Menu {
            content()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 24)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 52)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(label)
    }

    private func dockItem(_ scope: Library.Scope, icon: String, label: String) -> some View {
        let active = lib.scope == scope
        return Button {
            lib.scope = scope
            lib.selectedId = nil
            lib.selectedMindMapId = nil
            page = 0
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                    .frame(height: 24)
                    .scaleEffect(active ? 1.08 : 1)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(active ? Color.primary : .secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 52)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    /// دکمهٔ ویژهٔ داک: آیکون در دایرهٔ رنگی + عنوان — برای ابزاری که باید برجسته و مرتب باشد
    private func dockFeatured(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(LinearGradient(colors: [Color.accentColor,
                                                              Color.accentColor.opacity(0.72)],
                                                     startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: Color.accentColor.opacity(0.32), radius: 6, y: 3)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
            }
            .frame(minWidth: 60)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.accentColor.opacity(0.09))
            )
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func dockAction(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: حالت خالی

    private var orbitEmpty: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1.5)
                    .frame(width: 92, height: 92)
                Circle()
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1.5)
                    .frame(width: 64, height: 64)
                Image(systemName: isMapMode ? "brain.head.profile" : "bookmark")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            Text(lib.query.isBlank ? L.tr("No bookmarks here") : L.tr("No results found"))
                .font(.system(size: 15, weight: .medium))
            Text(lib.query.isBlank ? L.tr("Press ⌘N to add your first bookmark.") : L.tr("Try different words or type a domain."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if lib.query.isBlank {
                Button { newAction() } label: {
                    Label(lib.scope == .mindMaps ? L.tr("New Map") : L.tr("New Bookmark"),
                          systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newAction() {
        if isMapMode {
            MindMapToolWindow.shared.show(url: "")
        } else {
            lib.editing = .new(folderId: ShellSupport.currentFolderId(lib))
        }
    }

    // MARK: جزئیات — کشوی لبهٔ چپ

    @ViewBuilder
    private var detailOverlay: some View {
        if lib.selectedId != nil || lib.selectedMindMapId != nil {
            VStack(spacing: 0) {
                DetailView()
                    .frame(width: 440)
                    .frame(maxHeight: .infinity)
                    .background(.regularMaterial)
                    .opaquePanelBacking()
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    lib.selectedId = nil
                    lib.selectedMindMapId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                .buttonStyle(.plain)
                .help(L.tr("Close"))
            }
            .transition(.move(edge: .leading))
            .shadow(color: .black.opacity(0.18), radius: 26, x: -4)
        }
    }
}

// MARK: - تایل نشانک

private struct OrbitTile: View {
    @ObservedObject private var lib = Library.shared
    let bookmark: Bookmark
    let selected: Bool
    var onSelect: () -> Void
    var onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // تصویر یا فاوآیکون بزرگ داخل دایرهٔ رنگی
                if let img = ImageStore.shared.image(path: bookmark.screenshot ?? bookmark.thumb) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08)))
                } else {
                    FaviconView(path: bookmark.favicon, size: 44)
                        .padding(15)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }

                if bookmark.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .offset(x: -4, y: -4)
                }
                if bookmark.isDead {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: 4)
                }
            }
            .frame(height: 78)

            Text(bookmark.title.isBlank ? bookmark.domain : bookmark.title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(bookmark.domain)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // اکشن‌های هاور: باز کردن + ویرایش
            HStack(spacing: 6) {
                tileAction("arrow.up.forward", help: L.tr("Open")) { onOpen() }
                tileAction("square.and.pencil", help: L.tr("Edit Bookmark")) {
                    lib.editing = .edit(bookmark)
                }
            }
            .frame(height: 22)
            .opacity(hovered ? 1 : 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.accentColor.opacity(0.10))
                               : AnyShapeStyle(Color.primary.opacity(0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.06),
                              lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) { onOpen() }
        .onHover { inside in hovered = inside }
        .contextMenu { ShellBookmarkMenu(bookmark: bookmark) }
    }

    private func tileAction(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 22)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - تایل نقشهٔ ذهنی

private struct OrbitMapTile: View {
    @ObservedObject private var lib = Library.shared
    let record: MindMapRecord
    let selected: Bool
    var onSelect: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.purple)
                .frame(width: 74, height: 74)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.purple.opacity(0.12))
                )
                .frame(height: 78)

            Text(record.displayTitle)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(record.sourceURL)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.purple.opacity(0.10))
                               : AnyShapeStyle(Color.primary.opacity(0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? Color.purple.opacity(0.8) : Color.primary.opacity(0.06),
                              lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { onSelect() }
        .contextMenu { ShellMindMapMenu(record: record) }
    }
}
