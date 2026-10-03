import SwiftUI
import AppKit

// MARK: - طراحی «کتابخانه» (Atlas)
// حس آرشیو/کاتالوگ: کاغذ کرمی، تایپ سریف، کارت‌های فهرستگان
// و تب‌های عمودیِ برزخی روی لبهٔ راست پنجره (مثل زبانهٔ دفترچهٔ فهرست).
// جزئیات مثل ورق زدن از سمت چپ باز می‌شود.

struct AtlasShell: View {
    @ObservedObject private var lib = Library.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                mainPane
                // فضای تب‌های برزخی
                Spacer().frame(width: 44)
            }

            // تب‌های عمودی کاتالوگ (لبهٔ راست)
            edgeTabs
        }
        .overlay(alignment: .leading) { detailOverlay }
        .animation(.easeInOut(duration: 0.22), value: lib.selectedId)
        .animation(.easeInOut(duration: 0.22), value: lib.selectedMindMapId)
    }

    // MARK: پنل اصلی

    private var mainPane: some View {
        VStack(spacing: 0) {
            headerBand
            searchBand
            Divider()
            catalog
            statusBar
        }
    }

    // MARK: نوار سربرگ کاتالوگ

    private var headerBand: some View {
        HStack(alignment: .center, spacing: 14) {
            // مُهر کاتالوگ
            VStack(alignment: .leading, spacing: 1) {
                Text("NESHANKYAR")
                    .font(.system(size: 8, weight: .bold))
                    .kerning(2.5)
                    .foregroundStyle(.tertiary)
                Text(sectionTitle)
                    .font(.system(size: 22, weight: .medium, design: .serif))
            }

            Spacer()

            // دسته‌بندی به‌صورت پیوند متنی ردیفی
            HStack(spacing: 14) {
                sectionLink(.all, label: L.tr("All"))
                sectionLink(.starred, label: L.tr("Starred"))
                sectionLink(.unfiled, label: L.tr("Unfiled"))
                sectionLink(.mindMaps, label: L.tr("Mind Maps"))
                sectionLink(.trash, label: L.tr("Trash"))
            }

            Divider().frame(height: 18)

            HStack(spacing: 10) {
                ShellCheckBadge()
                toolIcon("bubble.left.and.bubble.right", L.tr("Chats (⌘⇧C)")) {
                    NotificationCenter.default.post(name: .showChats, object: nil)
                }
                toolIcon("folder.badge.plus", L.tr("New Folder (⌘⇧N)")) {
                    NotificationCenter.default.post(name: .newFolder, object: nil)
                }
                toolIcon("arrow.down.circle", L.tr("Video Downloader"), title: L.tr("Video Downloader")) {
                    ShellTools.openVideoDownload()
                }
                sortTool
                moreTool
                toolIcon("plus.square.dashed", lib.scope == .mindMaps ? L.tr("New Map") : L.tr("New Bookmark")) {
                    newAction()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.03))
    }

    private func toolIcon(_ icon: String, _ help: String, title: String? = nil,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                if let title {
                    Text(title)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(title == nil ? Color.secondary : Color.accentColor)
            .frame(height: 26)
            .padding(.horizontal, title == nil ? 0 : 9)
            .frame(minWidth: title == nil ? 26 : 0)
            .background(
                Group {
                    if title != nil {
                        Capsule().fill(Color.accentColor.opacity(0.10))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// مرتب‌سازی و ابزارها با همان سبک سربرگ
    private var sortTool: some View {
        ShellSortMenu()
            .fixedSize()
            .frame(width: 26, height: 26)
    }

    private var moreTool: some View {
        ShellMoreMenu()
            .fixedSize()
            .frame(width: 26, height: 26)
    }

    private func sectionLink(_ scope: Library.Scope, label: String) -> some View {
        let active = lib.scope == scope
        return Button {
            lib.scope = scope
            lib.selectedId = nil
            lib.selectedMindMapId = nil
        } label: {
            Text(label)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(active ? Color.primary : .secondary)
                .underline(active, color: Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var sectionTitle: String {
        switch lib.scope {
        case .all: return L.tr("Archive")
        case .starred: return L.tr("Starred")
        case .unfiled: return L.tr("Unfiled")
        case .mindMaps: return L.tr("Mind Maps")
        case .trash: return L.tr("Trash")
        case .folder(let id): return lib.flattenFolders(lib.folders).first { $0.id == id }?.name ?? L.tr("Folders")
        case .tag(let name): return name
        }
    }

    // MARK: نوار جستجو

    private var searchBand: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField(lib.scope == .mindMaps
                      ? L.tr("Search mind maps by name, URL or text…")
                      : L.tr("Search in title, URL, tag and note…"),
                      text: $lib.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .serif))
                .focused($searchFocused)
            if !lib.query.isEmpty {
                Button { lib.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 16)

            // شمارش نسخه‌ها به سبک کاتالوگ
            Text(lib.scope == .mindMaps
                 ? L.tf("%@ items", Digits.fa(lib.mindMaps.count))
                 : L.tf("%@ items", Digits.fa(lib.results.count)))
                .font(.system(size: 10.5))
                .kerning(0.5)
                .foregroundStyle(.tertiary)
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .frame(height: 38)
        .background(Color.primary.opacity(0.045))
    }

    // MARK: فهرستگان (کارت‌های آرشیوی)

    private var catalog: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if lib.scope == .mindMaps {
                    if lib.mindMaps.isEmpty { AtlasEmpty(isMap: true) }
                    ForEach(lib.mindMaps) { map in
                        AtlasMapRow(record: map,
                                    selected: lib.selectedMindMapId == map.id,
                                    onSelect: { lib.selectedMindMapId = map.id })
                            .onTapGesture(count: 2) { ShellSupport.openURL(map.sourceURL) }
                    }
                } else if lib.results.isEmpty {
                    AtlasEmpty()
                } else {
                    ForEach(lib.results) { bookmark in
                        AtlasRow(bookmark: bookmark,
                                 selected: lib.selectedId == bookmark.id,
                                 onSelect: { lib.selectedId = bookmark.id })
                            .onTapGesture(count: 2) { lib.open(bookmark) }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 0) {
            // برگه‌های موضوعی کاتالوگ (پوشه‌ها و برچسب‌ها به‌صورت نوار اسکرول افقی)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    ForEach(lib.folders) { folder in
                        atlasPill(folder.name, active: lib.scope == .folder(folder.id)) {
                            lib.scope = .folder(folder.id)
                            lib.selectedId = nil
                        }
                    }
                    if !lib.tags.isEmpty {
                        pillDivider
                        ForEach(lib.tags) { tag in
                            atlasPill("#" + tag.name, active: lib.scope == .tag(tag.name)) {
                                lib.scope = lib.scope == .tag(tag.name) ? .all : .tag(tag.name)
                                lib.selectedId = nil
                            }
                        }
                    }

                    if !lib.savedFilters.isEmpty {
                        pillDivider
                        ForEach(lib.savedFilters) { filter in
                            atlasFilterPill(filter)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 12)

            Button {
                AppActions.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L.tr("Settings (⌘,)"))
            .padding(.horizontal, 16)
        }
        .frame(height: 32)
        .background(Divider().opacity(0).background(Color.primary.opacity(0.04)))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private var pillDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 6)
    }

    /// برگهٔ کوچک نوار پایین با گوشهٔ بالایی گرد
    private func atlasPill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, design: .serif))
                .foregroundStyle(active ? Color.white : .secondary)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(RoundedCorners(top: 6).fill(
                    active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06))
                ))
        }
        .buttonStyle(.plain)
    }

    /// برگهٔ فیلتر ذخیره‌شده (حاشیهٔ نقطه‌چین تا از پوشه/برچسب متمایز شود)
    private func atlasFilterPill(_ filter: Library.SavedFilter) -> some View {
        Button {
            lib.apply(filter)
            lib.selectedId = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 9))
                Text(filter.name)
                    .font(.system(size: 11, design: .serif))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(RoundedCorners(top: 6).fill(Color.primary.opacity(0.06)))
            .overlay(
                RoundedCorners(top: 6)
                    .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3]))
            )
        }
        .buttonStyle(.plain)
        .help(L.tr("Apply Filter"))
    }

    private func newAction() {
        if lib.scope == .mindMaps {
            MindMapToolWindow.shared.show(url: "")
        } else {
            lib.editing = .new(folderId: ShellSupport.currentFolderId(lib))
        }
    }

    // MARK: تب‌های لبهٔ راست

    /// زبانه‌های عمودی داخل اسکرول تا با تعداد زیاد پوشه از ارتفاع پنجره بیرون نزنند
    private var edgeTabs: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                edgeTab(.all, label: L.tr("All"), color: .brown)
                edgeTab(.starred, label: L.tr("Starred"), color: .yellow)
                edgeTab(.unfiled, label: L.tr("Unfiled"), color: .teal)
                edgeTab(.mindMaps, label: L.tr("Mind Maps"), color: .purple)
                edgeTab(.trash, label: L.tr("Trash"), color: .red)

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 14, height: 1)
                    .padding(.vertical, 7)

                edgeFolderTabs
            }
            .padding(.top, 56)
            .padding(.bottom, 36)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var edgeFolderTabs: some View {
        // حداکثر ۸ پوشهٔ اول به‌صورت زبانه‌های رنگی
        ForEach(Array(lib.folders.prefix(8))) { folder in
            let active = lib.scope == .folder(folder.id)
            Button {
                lib.scope = .folder(folder.id)
                lib.selectedId = nil
            } label: {
                ZStack {
                    RoundedCorners(top: 7, bottom: 7)
                        .fill(folder.uiColor.opacity(active ? 1 : 0.55))
                    // برچسب عمودی
                    Text(folder.name)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                        .frame(width: 84)
                        .rotationEffect(.degrees(90))
                }
                .frame(width: 26, height: 72)
            }
            .buttonStyle(.plain)
            .help(folder.name)
            .padding(.bottom, 5)
        }
    }

    private func edgeTab(_ scope: Library.Scope, label: String, color: Color) -> some View {
        let active = lib.scope == scope
        return Button {
            lib.scope = scope
            lib.selectedId = nil
            lib.selectedMindMapId = nil
        } label: {
            ZStack {
                RoundedCorners(top: 7, bottom: 7)
                    .fill(active ? AnyShapeStyle(color) : AnyShapeStyle(Color.primary.opacity(0.08)))
                Text(label)
                    .font(.system(size: 9.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Color.white : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .frame(width: 84)
                    .rotationEffect(.degrees(90))
            }
            .frame(width: 26, height: 74)
        }
        .buttonStyle(.plain)
        .help(label)
        .padding(.bottom, 4)
    }

    // MARK: جزئیات — ورق زدن از سمت چپ

    @ViewBuilder
    private var detailOverlay: some View {
        if lib.selectedId != nil || lib.selectedMindMapId != nil {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack {
                        // «پشت جلد» جزئیات
                        Text(sectionTitle)
                            .font(.system(size: 11, design: .serif))
                            .kerning(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            lib.selectedId = nil
                            lib.selectedMindMapId = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .help(L.tr("Close"))
                    }
                    .padding(12)

                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

                    DetailView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 460)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .trailing) {
                    // «شیار صحافی» سمت راست پنل
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle()
                                .fill(Color.primary.opacity(0.15))
                                .frame(width: 3, height: 3)
                        }
                    }
                    .frame(width: 12)
                    .frame(maxHeight: .infinity)
                    .background(Color.primary.opacity(0.04))
                }
                .shadow(color: .black.opacity(0.16), radius: 22, x: -6)
            }
            .transition(.move(edge: .leading))
        }
    }
}

// MARK: - گوشه‌های ناهم‌قرینه (زبانه‌ها)

private struct RoundedCorners: Shape {
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + top))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottom))
        path.closeSubpath()
        return path
    }
}

// MARK: - ردیف فهرستگان

private struct AtlasRow: View {
    @ObservedObject private var lib = Library.shared
    let bookmark: Bookmark
    let selected: Bool
    var onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // شمارهٔ ردیف به سبک کاتالوگ
            Text(bookmark.starred ? "★" : "·")
                .font(.system(size: 12))
                .foregroundStyle(bookmark.starred
                                 ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(Color.primary.opacity(0.25)))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title.isBlank ? bookmark.domain : bookmark.title)
                    .font(.system(size: 14, design: .serif))
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(bookmark.domain)
                        .foregroundStyle(.secondary)
                    if !bookmark.isRead {
                        Text(L.tr("Unread"))
                            .foregroundStyle(Color.accentColor)
                    }
                    if bookmark.isDead {
                        Text(L.tr("Dead link"))
                            .foregroundStyle(.red.opacity(0.75))
                    }
                    Text("—")
                        .foregroundStyle(.tertiary)
                    Text(Dates.persian(bookmark.createdAt))
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 10.5, design: .serif))

                if !bookmark.note.isBlank {
                    Text(bookmark.note)
                        .font(.system(size: 11, design: .serif))
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !bookmark.tags.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(bookmark.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, design: .serif))
                            .kerning(0.5)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary.opacity(0.15)))
                    }
                }
            }

            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(selected
                                 ? AnyShapeStyle(Color.accentColor)
                                 : AnyShapeStyle(Color.primary.opacity(0.15)))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(selected ? Color.accentColor.opacity(0.07) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu { ShellBookmarkMenu(bookmark: bookmark) }
    }
}

// MARK: - ردیف نقشهٔ ذهنی

private struct AtlasMapRow: View {
    @ObservedObject private var lib = Library.shared
    let record: MindMapRecord
    let selected: Bool
    var onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("◍")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.displayTitle)
                    .font(.system(size: 14, design: .serif))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(record.sourceURL).foregroundStyle(.secondary).lineLimit(1)
                    Text("—").foregroundStyle(.tertiary)
                    Text(Dates.persian(record.createdAt)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 10.5, design: .serif))
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(selected ? Color.accentColor.opacity(0.07) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu { ShellMindMapMenu(record: record) }
    }
}

// MARK: - حالت خالی

private struct AtlasEmpty: View {
    /// در محدودهٔ نقشه‌های ذهنی دکمهٔ ساخت نقشه هم دارد
    var isMap = false

    var body: some View {
        VStack(spacing: 10) {
            Text("❧")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(L.tr("No bookmarks here"))
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(.secondary)
            Text(L.tr("Press ⌘N to add your first bookmark."))
                .font(.system(size: 11, design: .serif))
                .foregroundStyle(.tertiary)
            if isMap {
                Button {
                    MindMapToolWindow.shared.show(url: "")
                } label: {
                    Label(L.tr("Design New Mind Map"), systemImage: "plus")
                        .font(.system(size: 12, design: .serif))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 6)
            } else {
                Button {
                    NotificationCenter.default.post(name: .newBookmark, object: nil)
                } label: {
                    Text("+ " + L.tr("New Bookmark"))
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}
