import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject private var lib = Library.shared

    /// شناسهٔ پوشه‌های باز (نگه‌داری بین اجراها؛ با OutlineGroup که روی هر reload جمع می‌شد جایگزین شد)
    @AppStorage("expandedFolders") private var expandedRaw = ""

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderParent: Int64 = 0
    @State private var renameTarget: Folder?
    @State private var renameText = ""
    @State private var appearanceTarget: Folder?
    @State private var showSaveFilter = false
    @State private var filterName = ""
    @State private var renameFilterTarget: Library.SavedFilter?
    @State private var renameFilterText = ""

    private var expandedIds: Set<Int64> {
        get { Set(expandedRaw.split(separator: ",").compactMap { Int64($0) }) }
        nonmutating set { expandedRaw = newValue.map(String.init).sorted().joined(separator: ",") }
    }

    var body: some View {
        List(selection: scopeSelection) {
            Section(L.tr("Smart")) {
                smartRow(.all, label: L.tr("All Bookmarks"), icon: "tray.full", count: lib.counts.all)
                smartRow(.starred, label: L.tr("Starred"), icon: "star", count: lib.counts.starred)
                smartRow(.trash, label: L.tr("Trash"), icon: "trash", count: lib.counts.trash)
                smartRow(.mindMaps, label: L.tr("Mind Maps"), icon: "point.3.connected.trianglepath.dotted", count: lib.mindMapCount)
            }

            Section {
                // پوشهٔ مجازی «بدون پوشه»: همیشه اولین و بالاترین ردیف، سنجاق‌شده
                unfiledRow
                FolderTreeView(list: lib.folders, depth: 0,
                               expandedRaw: $expandedRaw,
                               onNewSubfolder: { id in
                                   newFolderParent = id
                                   newFolderName = ""
                                   showNewFolder = true
                               },
                               onRename: { folder in
                                   renameTarget = folder
                                   renameText = folder.name
                               },
                               onAppearance: { appearanceTarget = $0 })
            } header: {
                HStack {
                    Text(L.tr("Folders"))
                    Spacer()
                    Button {
                        newFolderParent = 0
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(L.tr("New Folder (⌘⇧N)"))
                }
            }

            Section {
                if lib.savedFilters.isEmpty {
                    Text(L.tr("No saved filters yet"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lib.savedFilters) { filter in
                        filterRow(filter)
                    }
                }
            } header: {
                HStack {
                    Text(L.tr("Saved Filters"))
                    Spacer()
                    Button {
                        filterName = suggestedFilterName
                        showSaveFilter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(L.tr("Save current filter (search + scope + sort)"))
                }
            }

            if !lib.tags.isEmpty {
                Section(L.tr("Tags")) {
                    ForEach(lib.tags) { tag in
                        tagRow(tag)
                    }
                }
            }

            Section(L.tr("Tools")) {
                toolsRow
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .onReceive(NotificationCenter.default.publisher(for: .newFolder)) { _ in
            newFolderParent = 0
            newFolderName = ""
            showNewFolder = true
        }
        .onChange(of: lib.scope) { scope in
            if case .folder(let id) = scope {
                expandAncestors(of: id)
            }
        }
        .sheet(item: $appearanceTarget) { folder in
            FolderAppearanceSheet(folder: folder)
        }
        .alert(L.tr("New Folder"), isPresented: $showNewFolder) {
            TextField(L.tr("New Folder Name"), text: $newFolderName)
            Picker(L.tr("Inside"), selection: $newFolderParent) {
                Text(L.tr("Root of List")).tag(Int64(0))
                ForEach(lib.folderOptions().filter { $0.id != 0 }) { option in
                    Text(option.label).tag(option.id)
                }
            }
            Button(L.tr("Create")) {
                let parent: Int64? = newFolderParent == 0 ? nil : newFolderParent
                lib.addFolder(name: newFolderName, parent: parent)
                if let parent { expandAncestors(of: parent) }
                newFolderName = ""
                newFolderParent = 0
            }
            Button(L.tr("Cancel"), role: .cancel) {
                newFolderName = ""
                newFolderParent = 0
            }
        } message: {
            Text(parentName(newFolderParent))
        }
        .alert(
            L.tr("Rename Folder"),
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField(L.tr("Name"), text: $renameText)
            Button(L.tr("Save")) {
                if let f = renameTarget { lib.renameFolder(id: f.id, name: renameText) }
                renameTarget = nil
            }
            Button(L.tr("Cancel"), role: .cancel) { renameTarget = nil }
        }
        .alert(L.tr("Save Current Filter"), isPresented: $showSaveFilter) {
            TextField(L.tr("Filter Name"), text: $filterName)
            Button(L.tr("Save")) {
                lib.saveCurrentFilter(name: filterName)
                filterName = ""
            }
            Button(L.tr("Cancel"), role: .cancel) { filterName = "" }
        } message: {
            Text(L.tr("The current search, scope and sort will be saved with this name."))
        }
        .alert(
            L.tr("Rename Filter"),
            isPresented: Binding(
                get: { renameFilterTarget != nil },
                set: { if !$0 { renameFilterTarget = nil } }
            )
        ) {
            TextField(L.tr("Name"), text: $renameFilterText)
            Button(L.tr("Save")) {
                if let f = renameFilterTarget { lib.renameFilter(id: f.id, name: renameFilterText) }
                renameFilterTarget = nil
            }
            Button(L.tr("Cancel"), role: .cancel) { renameFilterTarget = nil }
        }
    }

    /// نام پیشنهادی برای فیلترِ در حال نمایش
    private var suggestedFilterName: String {
        if !lib.query.isBlank { return lib.query.trimmed }
        switch lib.scope {
        case .folder(let id):
            return lib.flattenFolders(lib.folders).first { $0.id == id }?.name ?? L.tr("Folder")
        case .unfiled: return L.tr("Unfiled")
        case .tag(let name): return name
        case .starred: return L.tr("Starred")
        case .trash: return L.tr("Trash")
        case .mindMaps: return L.tr("Mind Maps")
        case .all: return L.tr("All Bookmarks")
        }
    }

    // MARK: انتخاب Scope

    private var scopeSelection: Binding<Library.Scope?> {
        Binding(
            get: { lib.scope },
            set: { newValue in
                if let newValue { lib.scope = newValue }
            }
        )
    }

    // MARK: ردیف‌های هوشمند

    private func smartRow(_ scope: Library.Scope, label: String, icon: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            if count > 0 {
                Text(Digits.fa(count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .tag(scope)
    }

    // MARK: پوشهٔ مجازی «بدون پوشه»

    /// نشانک‌هایی که در هیچ پوشه‌ای نیستند؛ همیشه اولین ردیف بخش پوشه‌ها (سنجاق‌شده)
    private var unfiledRow: some View {
        HStack(spacing: 5) {
            Spacer().frame(width: 16)
            Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
            Text(L.tr("Unfiled"))
                .lineLimit(1)
            Spacer()
            if lib.unfiledCount > 0 {
                Text(Digits.fa(lib.unfiledCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .tag(Library.Scope.unfiled)
        .help(L.tr("Bookmarks not in any folder"))
    }

    // MARK: پوشه‌ها (درخت دستی با حالت باز/بستهٔ پایدار)

    /// نام والد برای پیام دیالوگ پوشهٔ جدید
    private func parentName(_ id: Int64) -> String {
        if id == 0 { return L.tr("Folder will be created at the root level.") }
        let name = lib.flattenFolders(lib.folders).first { $0.id == id }?.name ?? L.tr("Folder")
        return L.tf("A subfolder of “%@” will be created.", name)
    }

    /// باز کردن زنجیرهٔ والدها تا پوشهٔ داده‌شده دیده شود
    private func expandAncestors(of id: Int64) {
        var parentOf: [Int64: Int64] = [:]
        for f in lib.flattenFolders(lib.folders) {
            if let p = f.parentId { parentOf[f.id] = p }
        }
        var ids = expandedIds
        var cur: Int64? = parentOf[id] ?? (id == 0 ? nil : nil)
        // خود پوشه هم اگر فرزند دارد باز بماند تا نتیجه دیده شود
        cur = id
        while let c = cur {
            ids.insert(c)
            cur = parentOf[c]
        }
        expandedIds = ids
    }

    private func toggleExpanded(_ id: Int64) {
        var ids = expandedIds
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        expandedIds = ids
    }

}

// MARK: - درخت پوشه‌ها (بازگشتی؛ حالت باز/بسته در AppStorage می‌ماند)

/// ردیف‌های تودرتو با شورون اختصاصی — با هر reload جمع نمی‌شوند (برخلاف OutlineGroup).
private struct FolderTreeView: View {
    @ObservedObject private var lib = Library.shared

    var list: [Folder]
    var depth: Int
    @Binding var expandedRaw: String
    var onNewSubfolder: (Int64) -> Void
    var onRename: (Folder) -> Void
    var onAppearance: (Folder) -> Void

    private var expandedIds: Set<Int64> {
        get { Set(expandedRaw.split(separator: ",").compactMap { Int64($0) }) }
        nonmutating set { expandedRaw = newValue.map(String.init).sorted().joined(separator: ",") }
    }

    private func toggle(_ id: Int64) {
        var ids = expandedIds
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        expandedIds = ids
    }

    var body: some View {
        ForEach(list) { folder in
            VStack(spacing: 0) {
                row(folder)
                if expandedIds.contains(folder.id), !folder.children.isEmpty {
                    FolderTreeView(list: folder.children, depth: depth + 1,
                                   expandedRaw: $expandedRaw,
                                   onNewSubfolder: onNewSubfolder,
                                   onRename: onRename,
                                   onAppearance: onAppearance)
                }
            }
            // برچسب انتخاب باید روی «کل ردیف» باشد، نه فقط محتوای داخلی آن؛
            // وگرنه List انتخاب را ثبت نمی‌کند و هایلایت فوری مثل بقیهٔ ردیف‌ها نمی‌آید.
            .tag(Library.Scope.folder(folder.id))
        }
    }

    private func row(_ folder: Folder) -> some View {
        let expanded = expandedIds.contains(folder.id)
        let hasKids = !folder.children.isEmpty
        return HStack(spacing: 5) {
            if hasKids {
                Button {
                    toggle(folder.id)
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(expanded ? L.tr("Collapse Subfolders") : L.tr("Show Subfolders"))
            } else {
                Spacer().frame(width: 16)
            }

            Image(systemName: folder.uiIcon)
                .foregroundStyle(folder.uiColor)
            Text(folder.name)
                .lineLimit(1)
            if folder.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .help(L.tr("Pinned"))
            }
            Spacer()
            if let c = lib.folderCounts[folder.id], c > 0 {
                Text(Digits.fa(c))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, CGFloat(depth) * 14)
        .contentShape(Rectangle())
        // دقیقاً مثل بقیهٔ ردیف‌های سایدبار: انتخاب و هایلایت فوری با خودِ List انجام می‌شود.
        // هیچ ژست اضافه‌ای اینجا نیست تا کلیک بدون تأخیر انتخاب کند (باز/بستن شاخه با شورون).
        .tag(Library.Scope.folder(folder.id))
        .contextMenu {
            Button(folder.pinned ? L.tr("Unpin") : L.tr("Pin to Top")) {
                lib.setFolderPinned(id: folder.id, pinned: !folder.pinned)
            }
            Button(L.tr("New Subfolder…")) { onNewSubfolder(folder.id) }
            Button(L.tr("Rename")) { onRename(folder) }
            Button(L.tr("Folder Appearance…")) { onAppearance(folder) }
            Button(L.tr("Add Bookmark Here")) {
                lib.editing = .new(folderId: folder.id)
            }
            if hasKids {
                    Button(expanded ? L.tr("Collapse Subfolders") : L.tr("Expand Subfolders")) {
                    toggle(folder.id)
                }
            }
            Divider()
            Button(L.tr("Delete Folder"), role: .destructive) {
                lib.deleteFolder(id: folder.id)
            }
        }
    }
}

extension SidebarView {
    // MARK: ابزارها

    /// نقطهٔ ورود ابزار «طراحی نقشه ذهنی»؛ نشانک انتخاب‌شده به‌صورت خودکار پر می‌شود.
    private var toolsRow: some View {
        Button {
            let selected = lib.selectedId.flatMap { lib.bookmark(id: $0) }
            MindMapToolWindow.shared.show(bookmark: selected)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(L.tr("Mind Map Designer"))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L.tr("Separate window: turn a web page into a mind map"))
    }

    // MARK: فیلترهای ذخیره‌شده

    private func filterRow(_ filter: Library.SavedFilter) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(filter.name)
                .lineLimit(1)
            Spacer()
            if !filter.query.isBlank {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { lib.apply(filter) }
        .contextMenu {
            Button(L.tr("Apply Filter")) { lib.apply(filter) }
            Button(L.tr("Rename")) {
                renameFilterTarget = filter
                renameFilterText = filter.name
            }
            Divider()
            Button(L.tr("Delete Filter"), role: .destructive) {
                lib.deleteFilter(id: filter.id)
            }
        }
    }

    // MARK: برچسب‌ها

    private func tagRow(_ tag: TagCount) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tag")
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(tag.name)
                .lineLimit(1)
            Spacer()
            Text(Digits.fa(tag.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .tag(Library.Scope.tag(tag.name))
        .contextMenu {
            Button(L.tr("Remove Tag from All Bookmarks")) {
                // حذف از ردیف‌های نتایج جاری
                for b in lib.results where b.tags.contains(tag.name) {
                    lib.removeTag(bookmarkId: b.id, name: tag.name)
                }
            }
        }
    }

    // MARK: نوار پایین سایدبار

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Button {
                    newFolderParent = 0
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help(L.tr("New Folder"))

                Button {
                    FilePanels.pickImport { url in
                        Task { await lib.importHTML(from: url) }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help(L.tr("Import Browser HTML File"))

                Button {
                    FilePanels.pickExport { url in
                        lib.exportHTML(to: url)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .help(L.tr("Export HTML…"))

                Button {
                    AppActions.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help(L.tr("Settings (⌘,)"))

                Spacer()

                if lib.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(Digits.fa(Int(lib.checkProgress * 100)) + (AppLanguage.current == .persian ? "٪" : "%"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .leading)
                } else {
                    Button {
                        Task { await lib.checkAllLinks() }
                    } label: {
                        Image(systemName: "bolt.horizontal.circle")
                    }
                    .help(L.tr("Check Dead Links"))
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
    }
}
