import SwiftUI
import AppKit

// MARK: - طراحی «داشبورد» (Dashboard)
// خانهٔ ویجت‌محور با ریل آیکون عمودی سمت راست: کارت‌های آمار،
// قفسه‌های افقی «تازه‌ها / نخوانده‌ها»، کارت‌های پوشه و ابر برچسب.
// جزئیات در مودال گردِ وسط پنجره باز می‌شود.

struct DashboardShell: View {
    @ObservedObject private var lib = Library.shared
    @FocusState private var searchFocused: Bool

    private let iconSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 0) {
            rail
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)

            Group {
                if lib.scope == .all {
                    ScrollView { homePage }
                } else {
                    scopePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay { modal }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: lib.selectedId)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: lib.selectedMindMapId)
    }

    // MARK: ریل آیکون

    private var rail: some View {
        VStack(spacing: 10) {
            railButton(.all, icon: "house.fill", activeIcon: "house.fill", tint: Color.accentColor)

            VStack(spacing: 8) {
                railButton(.starred, icon: "star", tint: .yellow)
                railButton(.unfiled, icon: "tray", tint: .teal)
                railButton(.mindMaps, icon: "brain.head.profile", tint: .purple)
                railButton(.trash, icon: "trash", tint: .red)
            }

            Spacer()

            VStack(spacing: 8) {
                railCircle("plus", tint: Color.accentColor, big: true) { newAction() }
                railCircle("bubble.left.and.text.bubble.right.fill", tint: .green) {
                    NotificationCenter.default.post(name: .showChats, object: nil)
                }
                railCircle("command", tint: .indigo) {
                    NotificationCenter.default.post(name: .showPalette, object: nil)
                }
                railLabeled("arrow.down.circle.fill", tint: .orange, title: L.tr("Video Downloader")) {
                    ShellTools.openVideoDownload()
                }
                railSortMenu
                railMenuCircle
                railCircle("gearshape.fill", tint: .gray) { AppActions.openSettings() }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(width: 74)
        .background(.bar)
    }

    private func railButton(_ scope: Library.Scope, icon: String, activeIcon: String? = nil, tint: Color) -> some View {
        let active = lib.scope == scope
        return Button {
            lib.scope = scope
            lib.selectedId = nil
            lib.selectedMindMapId = nil
        } label: {
            Image(systemName: active ? (activeIcon ?? icon + ".fill") : icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(active ? Color.white : tint)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(active ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.13)))
                )
        }
        .buttonStyle(.plain)
        .help(scopeTitle(scope))
    }

    /// دکمهٔ ریل با عنوان کوچک زیر آیکون — برای ابزارهایی که باید دیده شوند
    private func railLabeled(_ icon: String, tint: Color, title: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.7)],
                                                     startPoint: .top, endPoint: .bottom))
                    )
                    .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
                Text(title)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 58)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func railCircle(_ icon: String, tint: Color, big: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: big ? 20 : 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: big ? 44 : 36, height: big ? 44 : 36)
                .background(
                    Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.7)],
                                                 startPoint: .top, endPoint: .bottom))
                )
                .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    /// دکمهٔ مرتب‌سازی و منوی سرریز با همان ظاهر دایره‌ای ریل
    private var railSortMenu: some View {
        ShellSortMenu()
            .fixedSize()
            .frame(width: 36, height: 36)
            .background(
                Circle().fill(LinearGradient(colors: [Color.primary.opacity(0.10), Color.primary.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom))
            )
    }

    private var railMenuCircle: some View {
        ShellMoreMenu()
            .fixedSize()
            .frame(width: 36, height: 36)
            .background(
                Circle().fill(LinearGradient(colors: [Color.primary.opacity(0.10), Color.primary.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom))
            )
    }

    private func scopeTitle(_ scope: Library.Scope) -> String {
        switch scope {
        case .all: return L.tr("All")
        case .starred: return L.tr("Starred")
        case .unfiled: return L.tr("Unfiled")
        case .mindMaps: return L.tr("Mind Maps")
        case .trash: return L.tr("Trash")
        case .folder(let id): return lib.flattenFolders(lib.folders).first { $0.id == id }?.name ?? ""
        case .tag(let name): return name
        }
    }

    // MARK: صفحهٔ خانه (ویجت‌ها)

    private var homePage: some View {
        VStack(alignment: .leading, spacing: 22) {
            homeHeader
            searchPill
            statCards
            if !recentItems.isEmpty { shelf(title: L.tr("Recently Added"), items: recentItems) }
            if !unreadItems.isEmpty { shelf(title: L.tr("Unread"), items: unreadItems) }
            if !lib.folders.isEmpty { folderCards }
            if !lib.tags.isEmpty { tagCloud }
            if !lib.savedFilters.isEmpty { savedFiltersCard }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)
    }

    // MARK: فیلترهای ذخیره‌شده

    private var savedFiltersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            shelfHeader(L.tr("Saved Filters"), count: lib.savedFilters.count)
            FlowLayout(spacing: 7) {
                ForEach(lib.savedFilters) { filter in
                    Button {
                        lib.apply(filter)
                        lib.selectedId = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 10))
                            Text(filter.name)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.05))
                        )
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [3])))
                    }
                    .buttonStyle(.plain)
                    .help(L.tr("Apply Filter"))
                }
            }
        }
    }

    private var homeHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.tr("Dashboard"))
                    .font(.system(size: 24, weight: .bold))
                Text(Dates.persianMonth(Date()) + " · " +
                     L.tf("%@ bookmarks", Digits.fa(lib.counts.all)))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var searchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField(L.tr("Search in title, URL, tag and note…"), text: $lib.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !lib.query.isEmpty {
                Button { lib.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Capsule().fill(.regularMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    // MARK: کارت‌های آمار

    private var statCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            statCard(value: lib.counts.all, label: L.tr("All Bookmarks"),
                     icon: "bookmark.fill", tint: Color.accentColor, scope: .all)
            statCard(value: lib.counts.starred, label: L.tr("Starred"),
                     icon: "star.fill", tint: .yellow, scope: .starred)
            statCard(value: lib.counts.unread, label: L.tr("Unread"),
                     icon: "circle.fill", tint: .teal, scope: .all)
            statCard(value: lib.counts.trash, label: L.tr("Trash"),
                     icon: "trash.fill", tint: .red, scope: .trash)
        }
    }

    private func statCard(value: Int, label: String, icon: String, tint: Color, scope: Library.Scope) -> some View {
        Button {
            lib.scope = scope
            lib.selectedId = nil
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(tint.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(Digits.fa(value))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(label)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    // MARK: قفسه‌های افقی

    private var recentItems: [Bookmark] {
        lib.results.sorted { $0.createdAt > $1.createdAt }.prefix(12).map { $0 }
    }

    private var unreadItems: [Bookmark] {
        lib.results.filter { !$0.isRead }.prefix(12).map { $0 }
    }

    private func shelf(title: String, items: [Bookmark]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            shelfHeader(title, count: items.count)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { bookmark in
                        DashboardMiniCard(bookmark: bookmark)
                            .onTapGesture { lib.selectedId = bookmark.id }
                            .onTapGesture(count: 2) { lib.open(bookmark) }
                            .contextMenu { ShellBookmarkMenu(bookmark: bookmark) }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func shelfHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.accentColor)
                .frame(width: 3.5, height: 15)
                .clipShape(Capsule())
            Text(title)
                .font(.system(size: 14, weight: .bold))
            Text(Digits.fa(count))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: کارت‌های پوشه

    private var folderCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            shelfHeader(L.tr("Folders"), count: lib.folders.count)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(lib.folders) { folder in
                    Button {
                        lib.scope = .folder(folder.id)
                        lib.selectedId = nil
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: folder.uiIcon)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 9).fill(folder.uiColor))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(folder.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(Digits.fa(lib.folderCounts[folder.id] ?? 0))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.regularMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(lib.scope == .folder(folder.id) ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: ابر برچسب

    private var tagCloud: some View {
        VStack(alignment: .leading, spacing: 10) {
            shelfHeader(L.tr("Tags"), count: lib.tags.count)
            FlowLayout(spacing: 7) {
                ForEach(lib.tags) { tag in
                    Button {
                        lib.scope = lib.scope == .tag(tag.name) ? .all : .tag(tag.name)
                        lib.selectedId = nil
                    } label: {
                        HStack(spacing: 5) {
                            Text("#").font(.system(size: 10, weight: .bold))
                            Text(tag.name).font(.system(size: 11.5))
                            Text(Digits.fa(tag.count)).font(.system(size: 9.5)).foregroundStyle(.secondary)
                        }
                        .foregroundStyle(lib.scope == .tag(tag.name) ? Color.white : Color.primary.opacity(0.8))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(
                            Capsule().fill(lib.scope == .tag(tag.name)
                                           ? AnyShapeStyle(Color.accentColor)
                                           : AnyShapeStyle(Color.primary.opacity(0.06)))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: صفحهٔ محدوده (پوشه/برچسب/ستاره/…)

    private var scopePage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    lib.scope = .all
                    lib.selectedId = nil
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 10))
                        Text(L.tr("Dashboard"))
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Text(scopeTitle(lib.scope))
                    .font(.system(size: 17, weight: .bold))
                if lib.scope != .mindMaps {
                    Text(Digits.fa(lib.results.count))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ShellCheckBadge()
                if lib.scope == .trash && lib.counts.trash > 0 {
                    Button(L.tr("Empty Trash"), role: .destructive) { lib.emptyTrash() }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // جستجو هم در صفحهٔ محدوده‌ها در دسترس باشد
            HStack {
                searchPill
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if lib.scope == .mindMaps {
                mapScopeBody
            } else if lib.results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                              spacing: 12) {
                        ForEach(lib.results) { bookmark in
                            DashboardMiniCard(bookmark: bookmark, detailed: true)
                                .onTapGesture { lib.selectedId = bookmark.id }
                                .onTapGesture(count: 2) { lib.open(bookmark) }
                                .contextMenu { ShellBookmarkMenu(bookmark: bookmark) }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var mapScopeBody: some View {
        Group {
            if lib.mindMaps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                              spacing: 12) {
                        ForEach(lib.mindMaps) { map in
                            Button {
                                lib.selectedMindMapId = map.id
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: "brain.head.profile.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.purple)
                                        .frame(width: 40, height: 40)
                                        .background(Circle().fill(Color.purple.opacity(0.12)))
                                    Text(map.displayTitle)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(map.sourceURL)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.regularMaterial))
                            }
                            .buttonStyle(.plain)
                            .contextMenu { ShellMindMapMenu(record: map) }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(lib.query.isBlank ? L.tr("No bookmarks here") : L.tr("No results found"))
                .font(.system(size: 14, weight: .semibold))
            Text(lib.query.isBlank ? L.tr("Press ⌘N to add your first bookmark.") : L.tr("Try different words or type a domain."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            if lib.query.isBlank {
                Button { newAction() } label: {
                    Label(L.tr("New Bookmark"), systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        lib.editing = .new(folderId: ShellSupport.currentFolderId(lib))
    }

    // MARK: مودال گرد جزئیات

    @ViewBuilder
    private var modal: some View {
        if lib.selectedId != nil || lib.selectedMindMapId != nil {
            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { closeDetail() }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        if let id = lib.selectedId, let b = lib.bookmark(id: id) {
                            FaviconView(path: b.favicon, size: 22)
                            Text(b.title.isBlank ? b.domain : b.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        } else {
                            Image(systemName: "brain.head.profile.fill")
                                .foregroundStyle(.purple)
                            Text(L.tr("Mind Maps"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Spacer()
                        Button { closeDetail() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(L.tr("Close"))
                    }
                    .padding(14)

                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)

                    DetailView()
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 740, height: 540)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.regularMaterial))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10)))
                .shadow(color: .black.opacity(0.3), radius: 34, y: 12)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
    }

    private func closeDetail() {
        lib.selectedId = nil
        lib.selectedMindMapId = nil
    }
}

// MARK: - مینی‌کارت داشبورد

private struct DashboardMiniCard: View {
    let bookmark: Bookmark
    var detailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(bookmark: bookmark, height: detailed ? 96 : 72)
                if bookmark.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(4)
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(5)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.title.isBlank ? bookmark.domain : bookmark.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(bookmark.domain)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: detailed ? nil : 148)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.primary.opacity(0.045)))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

// MARK: - چیدمان جریانی (ابر برچسب) — قدیمی‌تر از Layout نگه‌داشته شد برای سازگاری macOS 13

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
