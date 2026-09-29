import SwiftUI
import AppKit

struct ListView: View {
    @ObservedObject private var lib = Library.shared
    @Binding private var selection: Set<Bookmark.ID>
    @FocusState private var searchFocused: Bool

    @AppStorage("groupBy") private var groupByRaw = GroupBy.none.rawValue

    private var groupBy: GroupBy { GroupBy(rawValue: groupByRaw) ?? .none }

    init(selection: Binding<Set<Bookmark.ID>>) {
        _selection = selection
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            if !selection.isEmpty {
                Divider()
                if lib.scope == .mindMaps { mindMapSelectionBar } else { selectionBar }
            }
        }
        .navigationTitle(scopeTitle)
        .toolbar { toolbarContent }
        .onDeleteCommand {
            if lib.scope == .mindMaps {
                lib.deleteMindMaps(ids: Array(selection))
            } else if lib.scope == .trash {
                lib.purge(ids: Array(selection))
            } else {
                lib.delete(ids: Array(selection))
            }
            selection = []
        }
        .onChange(of: selection) { newValue in
            if let last = newValue.sorted().last {
                if lib.scope == .mindMaps {
                    lib.selectedMindMapId = last
                    lib.selectedId = nil
                } else {
                    lib.selectedId = last
                    lib.selectedMindMapId = nil
                }
            }
        }
        // بستن پنل از داخل جزئیات (✕) یا حذف نشانک: انتخاب فهرست هم خالی می‌شود
        .onChange(of: lib.selectedId) { newValue in
            if newValue == nil, lib.scope != .mindMaps { selection = [] }
        }
        .onChange(of: lib.selectedMindMapId) { newValue in
            if newValue == nil, lib.scope == .mindMaps { selection = [] }
        }
        .onChange(of: lib.scope) { _ in clearAllSelection() }
        .alert(L.tr("Save Current Filter"), isPresented: $showSaveFilter) {
            TextField(L.tr("Filter Name"), text: $filterName)
            Button(L.tr("Save")) {
                lib.saveCurrentFilter(name: filterName)
                filterName = ""
            }
            Button(L.tr("Cancel"), role: .cancel) { filterName = "" }
        }
        .confirmationDialog(L.tr("Empty Trash?"), isPresented: $confirmEmptyTrash) {
            Button(L.tr("Delete All Permanently"), role: .destructive) {
                lib.emptyTrash()
            }
        } message: {
            Text(L.tf("%@ bookmarks will be permanently deleted.", Digits.fa(lib.counts.trash)))
        }
    }

    // MARK: نوار انتخاب چندتایی

    private var selectionBar: some View {
        GeometryReader { geo in
            // ستون فهرست می‌تواند تا ۳۰۰ پوینت باریک شود؛
            // بر حسب عرض واقعی، برچسب دکمه‌ها و متن شمارش جمع‌وجور می‌شوند (بدون شکستن متن).
            let w = geo.size.width
            let showTitles = w >= 660
            let showCountText = w >= 430

            HStack(spacing: showTitles ? 10 : 8) {
                Group {
                    if showCountText {
                        Text(L.tf("%@ bookmarks selected", Digits.fa(selection.count)))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(Digits.fa(selection.count))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 4)

                if lib.scope == .trash {
                    barButton(L.tr("Restore"), "arrow.uturn.backward", showTitle: showTitles) {
                        lib.restore(ids: Array(selection))
                        selection = []
                    }

                    barButton(L.tr("Delete Permanently"), "trash", showTitle: showTitles, role: .destructive) {
                        lib.purge(ids: Array(selection))
                        selection = []
                    }
                } else {
                    Menu {
                        ForEach(lib.folderOptions()) { option in
                            Button(option.label) {
                                lib.setFolder(Array(selection), folderId: option.id == 0 ? nil : option.id)
                                notifySelection(L.tr("Moved to folder"))
                            }
                        }
                    } label: {
                        barLabel(L.tr("Folder"), "folder", showTitle: showTitles)
                    }
                    .help(L.tr("Move to Folder"))

                    Menu {
                        ForEach(lib.tags) { tag in
                            Button(tag.name) {
                                lib.addTagBulk(Array(selection), name: tag.name)
                            }
                        }
                        Divider()
                        Button(L.tr("New Tag…")) { showBulkTagPrompt = true }
                    } label: {
                        barLabel(L.tr("Tag"), "tag", showTitle: showTitles)
                    }
                    .help(L.tr("Add Tag"))

                    barButton(L.tr("Delete"), "trash", showTitle: showTitles, role: .destructive) {
                        lib.delete(ids: Array(selection))
                        selection = []
                    }                }

                Button {
                    clearAllSelection()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help(L.tr("Clear Selection"))
            }
            .buttonStyle(.borderless)
            .controlSize(showTitles ? .regular : .small)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 42)
        .background(.bar)
        .alert(L.tr("Add Tag to Selected Bookmarks"), isPresented: $showBulkTagPrompt) {
            TextField(L.tr("Tag Name"), text: $bulkTagName)
            Button(L.tr("Add")) {
                lib.addTagBulk(Array(selection), name: bulkTagName)
                bulkTagName = ""
            }
            Button(L.tr("Cancel"), role: .cancel) { bulkTagName = "" }
        }
    }

    private func notifySelection(_ text: String) {
        lib.notify(text)
        selection = []
    }

    /// برچسب دکمه: در عرض کم فقط آیکون (متن هرگز شکسته نمی‌شود)
    @ViewBuilder
    private func barLabel(_ title: String, _ icon: String, showTitle: Bool) -> some View {
        if showTitle {
            Label(title, systemImage: icon)
        } else {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
        }
    }

    private func barButton(_ title: String, _ icon: String, showTitle: Bool,
                           role: ButtonRole? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            barLabel(title, icon, showTitle: showTitle)
        }
        .help(title)
    }

    // MARK: نوار جستجو + دکمهٔ همیشه‌نمایانِ افزودن

    private var searchBar: some View {
        GeometryReader { geo in
            // در ستون باریک، دکمهٔ «نشانک جدید» فقط آیکون می‌شود تا جستجو جا بماند
            let compact = geo.size.width < 420

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(lib.scope == .mindMaps
                          ? L.tr("Search mind maps by name, URL or text…")
                          : L.tr("Search in title, URL, tag and note…"),
                          text: $lib.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .keyboardShortcut("f", modifiers: .command)
                    .frame(minWidth: 60)
                if !lib.query.isEmpty {
                    Button {
                        lib.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(L.tr("Clear Search"))
                }

                Button {
                    if lib.scope == .mindMaps {
                        MindMapToolWindow.shared.show(url: "")
                    } else {
                        lib.editing = .new(folderId: currentFolderId)
                    }
                } label: {
                    if compact {
                        Image(systemName: "plus")
                    } else if lib.scope == .mindMaps {
                        Label(L.tr("New Map"), systemImage: "plus")
                    } else {
                        Label(L.tr("New Bookmark"), systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .fixedSize(horizontal: true, vertical: false)
                .keyboardShortcut("n", modifiers: .command)
                .help(lib.scope == .mindMaps ? L.tr("Create New Mind Map") : L.tr("New Bookmark (⌘N)"))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 42)
        .background(.bar)
    }

    // MARK: بدنه (سه حالت نمایش به انتخاب کاربر)

    @ViewBuilder
    private var content: some View {
        if lib.scope == .mindMaps {
            if lib.mindMaps.isEmpty { mindMapsEmptyState } else { mindMapsList }
        } else if lib.results.isEmpty {
            emptyState
        } else {
            switch lib.viewMode {
            case .list:
                listContent
            case .cards:
                cardsGrid
            case .boxes:
                boxesGrid
            }
        }
    }

    // MARK: فهرست مستقل نقشه‌های ذهنی

    private var mindMapsList: some View {
        List(selection: $selection) {
            ForEach(lib.mindMaps) { map in
                MindMapRecordRow(record: map,
                                 selected: lib.selectedMindMapId == map.id)
                    .tag(map.id)
                    .contextMenu {
                        Button(L.tr("Open Mind Map")) { lib.selectedMindMapId = map.id }
                        Button(L.tr("Open Source Page")) {
                            if let url = URL(string: map.sourceURL) { NSWorkspace.shared.open(url) }
                        }
                        Divider()
                        Button(L.tr("Delete Mind Map"), role: .destructive) { lib.deleteMindMaps(ids: [map.id]) }
                    }
            }
        }
        .listStyle(.inset)
    }

    private var mindMapsEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.tertiary)
            Text(lib.query.isBlank ? L.tr("No mind maps saved yet") : L.tr("No mind maps found"))
                .font(.title3)
            Text(lib.query.isBlank
                 ? L.tr("Select a bookmark and create a map from Tools → Mind Map Designer. Each map is saved separately in this list.")
                 : L.tr("Search by map title, URL or text."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            if lib.query.isBlank {
                Button {
                    MindMapToolWindow.shared.show(url: "")
                } label: {
                    Label(L.tr("Design New Mind Map"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var mindMapSelectionBar: some View {
        HStack(spacing: 10) {
            Text(L.tf("%@ mind maps selected", Digits.fa(selection.count)))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                lib.deleteMindMaps(ids: Array(selection))
                selection = []
            } label: {
                Label(L.tr("Delete Mind Map"), systemImage: "trash")
            }
            .help(L.tr("Deletes selected mind maps; source bookmarks are kept"))
            Button {
                clearAllSelection()
            } label: { Image(systemName: "xmark.circle") }
                .help(L.tr("Clear Selection"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.bar)
    }

    private var listContent: some View {
        List(selection: $selection) {
            if groupBy == .none {
                ForEach(lib.results) { bookmark in
                    row(bookmark)
                }
            } else {
                ForEach(rowGroups) { group in
                    Section {
                        ForEach(group.items) { bookmark in
                            row(bookmark)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
            // نشانگر انتهای محتوا (۱pt نامرئی): ضربهٔ پایین‌تر از آن = فضای خالی
            Color.clear
                .frame(height: 1)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ContentBottomKey.self,
                            value: proxy.frame(in: .global).minY
                        )
                    }
                )
        }
        .listStyle(.inset)
        // کلیک فضای خالی (بدون لینک): لغو انتخاب + بستن پنل.
        // با simultaneousGesture و فیلتر موقعیت: ضربهٔ روی ردیف‌ها نادیده گرفته
        // می‌شود، پس نیازی به دست‌کاری ژست ردیف‌ها (و شکستن انتخاب) نیست.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global).onEnded { value in
                guard isTap(value) else { return }   // اسکرول نادیده گرفته می‌شود
                if value.location.y > contentBottom {
                    clearAllSelection()
                }
            }
        )
        .onPreferenceChange(ContentBottomKey.self) { contentBottom = $0 }
    }

    private func row(_ bookmark: Bookmark) -> some View {
        BookmarkRow(bookmark: bookmark)
            .tag(bookmark.id)
    }

    // MARK: گروه‌بندی

    private struct RowGroup: Identifiable {
        let id: String
        let title: String
        let items: [Bookmark]
    }

    private var rowGroups: [RowGroup] {
        switch groupBy {
        case .none:
            return []
        case .domain:
            var map: [String: [Bookmark]] = [:]
            for b in lib.results {
                let key = b.domain.isBlank ? "—" : b.domain
                map[key, default: []].append(b)
            }
            return map.map { key, items in
                RowGroup(id: key, title: "\(key) · \(Digits.fa(items.count))", items: items)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .month:
            var map: [String: [Bookmark]] = [:]
            for b in lib.results {
                map[Dates.persianMonth(b.createdAt), default: []].append(b)
            }
            return map.map { key, items in
                RowGroup(id: key, title: "\(key) · \(Digits.fa(items.count))", items: items)
            }
            .sorted { lhs, rhs in
                (lhs.items.first?.createdAt ?? .distantPast) > (rhs.items.first?.createdAt ?? .distantPast)
            }
        case .folder:
            var map: [String: [Bookmark]] = [:]
            let names = Dictionary(
                uniqueKeysWithValues: lib.flattenFolders(lib.folders).map { ($0.id, $0.name) }
            )
            for b in lib.results {
                let key = b.folderId.flatMap { names[$0] } ?? L.tr("Unfiled")
                map[key, default: []].append(b)
            }
            return map.map { key, items in
                RowGroup(id: key, title: "\(key) · \(Digits.fa(items.count))", items: items)
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        }
    }

    /// شبکهٔ کارت‌ها: تعداد ستون‌ها از عرض واقعی محاسبه می‌شود (بدون فضای خالی انتهایی)
    private var cardsGrid: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVGrid(columns: gridColumns(width: geo.size.width, minItem: 205),
                          spacing: 14) {
                    ForEach(lib.results) { bookmark in
                        BookmarkCard(bookmark: bookmark,
                                     isSelected: selection.contains(bookmark.id))
                            .onTapGesture { select(bookmark) }
                    }
                }
                .padding(16)
                gridBottomMarker
            }
            .background(gridFrameReader)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global).onEnded { value in
                    guard isTap(value) else { return }
                    if isGridEmptyTap(value.location) { clearAllSelection() }
                }
            )
            .onPreferenceChange(ContentBottomKey.self) { contentBottom = $0 }
            .onPreferenceChange(GridFrameKey.self) { gridFrame = $0 }
        }
    }

    /// شبکهٔ باکس: حداکثر سه ستون افقی، بی‌نهایت عمودی
    private var boxesGrid: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVGrid(columns: gridColumns(width: geo.size.width, minItem: 185, maxColumns: 3),
                          spacing: 16) {
                    ForEach(lib.results) { bookmark in
                        BookmarkBox(bookmark: bookmark,
                                    isSelected: selection.contains(bookmark.id))
                            .onTapGesture { select(bookmark) }
                    }
                }
                .padding(16)
                gridBottomMarker
            }
            .background(gridFrameReader)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global).onEnded { value in
                    guard isTap(value) else { return }
                    if isGridEmptyTap(value.location) { clearAllSelection() }
                }
            )
            .onPreferenceChange(ContentBottomKey.self) { contentBottom = $0 }
            .onPreferenceChange(GridFrameKey.self) { gridFrame = $0 }
        }
    }

    private func gridColumns(width: CGFloat, minItem: CGFloat,
                             spacing: CGFloat = 14, maxColumns: Int = .max) -> [GridItem] {
        let usable = max(width - 32, 200)
        var count = Int((usable + spacing) / (minItem + spacing))
        count = max(1, min(maxColumns, count))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    /// با ⌘ یا ⇧ کلیک = افزودن/حذف از انتخاب؛ بدون آن = انتخاب تکی
    private func select(_ bookmark: Bookmark) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) || flags.contains(.shift) {
            if selection.contains(bookmark.id) {
                selection.remove(bookmark.id)
            } else {
                selection.insert(bookmark.id)
            }
            lib.selectedId = selection.sorted().last ?? bookmark.id
        } else {
            selection = [bookmark.id]
            lib.selectedId = bookmark.id
        }
    }

    /// لغو کامل انتخاب: پنل جزئیات/مرورگر هم بسته می‌شود
    private func clearAllSelection() {
        selection = []
        lib.selectedId = nil
        lib.selectedMindMapId = nil
    }

    // MARK: تشخیص ضربهٔ فضای خالی (بدون دست‌کاری ژست ردیف‌ها)

    /// انتهای محتوای فهرست/شبکه در مختصات سراسری (از نشانگر انتهایی می‌آید)
    @State private var contentBottom: CGFloat = .greatestFiniteMagnitude
    /// قاب سراسری ScrollView شبکه‌ها (برای تشخیص حاشیه‌های کناری خالی)
    @State private var gridFrame: CGRect = .zero

    /// نشانگر ۱pt نامرئی در انتهای شبکه‌ها
    private var gridBottomMarker: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ContentBottomKey.self,
                value: proxy.frame(in: .global).minY
            )
        }
        .frame(height: 1)
    }

    /// قاب ScrollView برای محاسبهٔ حاشیه‌ها
    private var gridFrameReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: GridFrameKey.self,
                value: proxy.frame(in: .global)
            )
        }
    }

    /// فقط ضربهٔ واقعی (نه اسکرول): جابه‌جایی کمتر از ۸ پوینت
    private func isTap(_ value: DragGesture.Value) -> Bool {
        abs(value.translation.width) < 8 && abs(value.translation.height) < 8
    }

    /// ضربهٔ شبکه خالی است اگر پایین‌تر از همهٔ آیتم‌ها یا در حاشیهٔ ۱۶pt کناری باشد
    private func isGridEmptyTap(_ location: CGPoint) -> Bool {
        location.y > contentBottom
            || location.x < gridFrame.minX + 16
            || location.x > gridFrame.maxX - 16
    }

    // MARK: حالت خالی

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.tertiary)
            Text(lib.query.isBlank ? L.tr("No bookmarks here") : L.tr("No results found"))
                .font(.title3)
            Text(lib.query.isBlank
                 ? L.tr("Press ⌘N to add your first bookmark.")
                 : L.tr("Try different words or type a domain."))
                .foregroundStyle(.secondary)
            if lib.query.isBlank {
                Button(L.tr("New Bookmark")) {
                    lib.editing = .new(folderId: currentFolderId)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: تولبار

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                if lib.scope == .mindMaps {
                    MindMapToolWindow.shared.show(url: "")
                } else {
                    lib.editing = .new(folderId: currentFolderId)
                }
            } label: {
                Image(systemName: "plus")
            }
            .help(lib.scope == .mindMaps ? L.tr("New Mind Map") : L.tr("New Bookmark (⌘N)"))
        }

        ToolbarItem {
            Picker(L.tr("View"), selection: $lib.viewMode) {
                ForEach(Library.ViewMode.allCases) { mode in
                    Image(systemName: mode.icon)
                        .tag(mode)
                        .help(mode.label)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 118)
            .help(L.tf("List view mode: %@", lib.viewMode.label))
        }

        ToolbarItem {
            Button {
                NotificationCenter.default.post(name: .showChats, object: nil)
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
            }
            .help(L.tr("Chats (⌘⇧C)"))
        }

        ToolbarItem {
            Button {
                AppActions.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help(L.tr("Settings (⌘,)"))
            .accessibilityLabel(L.tr("Open Settings"))
        }

        ToolbarItem {
            Menu {
                Picker(L.tr("Grouping"), selection: $groupByRaw) {
                    ForEach(GroupBy.allCases) { g in
                        Label(g.label, systemImage: g.icon).tag(g.rawValue)
                    }
                }

                Divider()

                Button(L.tr("Save Current Filter…")) {
                    filterName = lib.query.isBlank ? scopeTitle : lib.query.trimmed
                    showSaveFilter = true
                }

                Divider()

                if lib.scope == .trash {
                    Button(L.tr("Restore All")) {
                        lib.restore(ids: lib.results.map(\.id))
                    }
                    .disabled(lib.results.isEmpty)

                    Button(L.tr("Empty Trash"), role: .destructive) {
                        confirmEmptyTrash = true
                    }
                    .disabled(lib.counts.trash == 0)

                    Divider()
                }

                Picker(L.tr("Sort"), selection: $lib.sort) {
                    ForEach(Library.Sort.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                Divider()
                Button {
                    Task { await lib.checkAllLinks() }
                } label: {
                    if lib.isChecking {
                        Text(L.tr("Checking…"))
                    } else {
                        Text(L.tr("Check All Links"))
                    }
                }
                .disabled(lib.isChecking)
                Divider()
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
            } label: {
                Label(L.tr("More"), systemImage: "ellipsis.circle")
            }
            .help(L.tr("Grouping, sorting and tools"))
        }
    }

    @State private var showSaveFilter = false
    @State private var filterName = ""
    @State private var confirmEmptyTrash = false
    @State private var showBulkTagPrompt = false
    @State private var bulkTagName = ""

    // MARK: عنوان Scope

    private var scopeTitle: String {
        switch lib.scope {
        case .all: return L.tr("All Bookmarks")
        case .starred: return L.tr("Starred")
        case .trash: return L.tr("Trash")
        case .mindMaps: return L.tr("Mind Maps")
        case .unfiled: return L.tr("Unfiled")
        case .folder(let id):
            return lib.flattenFolders(lib.folders).first { $0.id == id }?.name ?? L.tr("Folder")
        case .tag(let name): return L.tf("Tag: %@", name)
        }
    }

    private var currentFolderId: Int64? {
        if case .folder(let id) = lib.scope { return id }
        return nil
    }
}

// MARK: - کلیدهای موقعیت‌یابی ضربهٔ فضای خالی

/// انتهای محتوا در مختصات سراسری (کمترین مقدار از نشانگرها)
private struct ContentBottomKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

/// قاب سراسری ScrollView شبکه‌ها
private struct GridFrameKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - ردیف فهرست

struct MindMapRecordRow: View {
    let record: MindMapRecord
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(record.domain.isEmpty ? record.sourceURL : record.domain)
                    Text("·")
                    Text(L.tf("%@ nodes", Digits.fa(record.displayNodeCount)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Dates.relative(record.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 74, alignment: .leading)
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

struct BookmarkRow: View {
    @ObservedObject private var lib = Library.shared
    @AppStorage("density") private var densityRaw = Density.comfortable.rawValue
    let bookmark: Bookmark

    private var density: Density { Density(rawValue: densityRaw) ?? .comfortable }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(bookmark.isRead ? Color.clear : Color.accentColor)
                .frame(width: 6, height: 6)

            FaviconView(path: bookmark.favicon, size: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(bookmark.displayTitle)
                        .font(.system(size: density.titleSize, weight: bookmark.isRead ? .regular : .semibold))
                        .lineLimit(1)
                    if bookmark.isDead {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .help(L.tr("This link appears to be dead"))
                    }
                    if bookmark.isTrashed {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 5) {
                    Text(bookmark.domain)
                    if !bookmark.tags.isEmpty {
                        Text("·")
                        Text(bookmark.tags.prefix(3).joined(separator: "، "))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if bookmark.starred {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
            }

            Text(Dates.relative(bookmark.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 74, alignment: .leading)
        }
        .padding(.vertical, density.rowPadding)
        .contentShape(Rectangle())
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var contextMenu: some View {
        if bookmark.isTrashed {
            Button(L.tr("Restore from Trash")) {
                lib.restore(ids: [bookmark.id])
            }
            Button(L.tr("Copy URL")) {
                lib.copyURL(bookmark)
            }
            Divider()
            Button(L.tr("Delete Permanently"), role: .destructive) {
                lib.purge(ids: [bookmark.id])
            }
        } else {
            Button(L.tr("Open")) {
                lib.open(bookmark)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button(L.tr("Copy URL")) {
                lib.copyURL(bookmark)
            }

            Divider()

            Button(bookmark.starred ? L.tr("Remove Star") : L.tr("Star")) {
                lib.setStarred(bookmark.id, !bookmark.starred)
            }



            Divider()

            Button(L.tr("Add to Folder…")) {
                lib.editing = .edit(bookmark)
            }

            if bookmark.folderId != nil {
                Button(L.tr("Remove from Folder")) { lib.setFolder([bookmark.id], folderId: nil) }
            }

            Button(L.tr("Delete (Move to Trash)"), role: .destructive) {
                lib.delete(ids: [bookmark.id])
            }
        }
    }
}

// MARK: - کارت

struct BookmarkCard: View {
    @ObservedObject private var lib = Library.shared
    let bookmark: Bookmark
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ThumbnailView(bookmark: bookmark, height: 104)
                if bookmark.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(Circle().fill(.thinMaterial))
                        .padding(7)
                }
                if bookmark.isTrashed {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Circle().fill(.thinMaterial))
                        .padding(7)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if !bookmark.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(bookmark.displayTitle)
                        .font(.system(size: 12.5, weight: bookmark.isRead ? .regular : .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                HStack {
                    Text(bookmark.domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if bookmark.isDead {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
        .contextMenu { sharedBookmarkMenu(lib, bookmark) }
    }
}

// MARK: - باکس (نمایش سه‌ستونی)

struct BookmarkBox: View {
    @ObservedObject private var lib = Library.shared
    let bookmark: Bookmark
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ThumbnailView(bookmark: bookmark, height: 132)
                HStack(spacing: 6) {
                    if bookmark.starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                            .padding(5)
                            .background(Circle().fill(.thinMaterial))
                    }
                    if bookmark.isDead {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .padding(5)
                            .background(Circle().fill(.thinMaterial))
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    if !bookmark.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(bookmark.displayTitle)
                        .font(.system(size: 13.5, weight: bookmark.isRead ? .regular : .semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if !bookmark.note.isBlank {
                    Text(bookmark.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if !bookmark.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(bookmark.tags.prefix(3), id: \.self) { tag in
                            TagChip(name: tag)
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 6) {
                    FaviconView(path: bookmark.favicon, size: 16)
                    Text(bookmark.domain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Dates.relative(bookmark.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(11)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                              lineWidth: isSelected ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
        .contextMenu { sharedBookmarkMenu(lib, bookmark) }
    }
}

// MARK: - منوی مشترک راست‌کلیک

@ViewBuilder
fileprivate func sharedBookmarkMenu(_ lib: Library, _ bookmark: Bookmark) -> some View {
    if bookmark.isTrashed {
        Button(L.tr("Restore from Trash")) { lib.restore(ids: [bookmark.id]) }
        Button(L.tr("Copy URL")) { lib.copyURL(bookmark) }
        Divider()
        Button(L.tr("Delete Permanently"), role: .destructive) { lib.purge(ids: [bookmark.id]) }
    } else {
        Button(L.tr("Open")) { lib.open(bookmark) }
        Button(L.tr("Copy URL")) { lib.copyURL(bookmark) }
        Divider()
        Button(bookmark.starred ? L.tr("Remove Star") : L.tr("Star")) {
            lib.setStarred(bookmark.id, !bookmark.starred)
        }
        Divider()
        Button(L.tr("Edit…")) { lib.editing = .edit(bookmark) }
        if bookmark.folderId != nil {
            Button(L.tr("Remove from Folder")) { lib.setFolder([bookmark.id], folderId: nil) }
        }
        Button(L.tr("Delete (Move to Trash)"), role: .destructive) { lib.delete(ids: [bookmark.id]) }
    }
}
