import SwiftUI
import AppKit

// MARK: - طراحی «شفق» (Aurora)
// پوستهٔ مدرن شیشه‌ای: تب‌های کپسولی بالا، جستجوی شناور بزرگ،
// چیپ‌های افقی پوشه/برچسب و گرید کارت‌های تصویری بزرگ.
// جزئیات در پنل شیشه‌ای لبهٔ چپ (trailing در چیدمان راست‌به‌چپ) باز می‌شود.

struct AuroraShell: View {
    @ObservedObject private var lib = Library.shared
    @FocusState private var searchFocused: Bool
    @State private var hoverCard: Int64?
    /// انتخاب چندتایی (⌘/⇧ + کلیک) مثل چیدمان کلاسیک
    @State private var selection = Set<Bookmark.ID>()
    /// عرض واقعی «سطر اقدامات» (دکمه‌های سمتِ نشان برنامه) و «کپسول تب‌ها».
    /// چون تب‌ها وسط‌چین‌اند و اقدامات به لبه چسبیده‌اند، در پنجره‌های میانی
    /// ممکن است به هم برسند؛ این دو مقدار فاصلهٔ لازم را حساب می‌کنند.
    @State private var actionsWidth: CGFloat = 0
    @State private var tabsWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.4)
            searchRow
            chipRows
            content
        }
        .background(detailScrim)
        .overlay(alignment: .trailing) { detailPanel }
        .overlay(alignment: .bottom) { bulkBar }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: lib.selectedId)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: lib.selectedMindMapId)
    }

    // MARK: نوار بالا — نشان برنامه + تب‌های محدوده + اقدامات

    private var topBar: some View {
        GeometryReader { geo in
            // در پنجره‌های باریک‌تر، برچسب تب‌ها جمع می‌شود (فقط آیکون) تا
            // نوار بالا هیچ‌وقت عریض‌تر از پنجره نشود و محتوا از صفحه بیرون نزند
            let wide = geo.size.width >= 1280

            ZStack {
                // دو سرِ نوار: نشان برنامه (راست در RTL) و دکمه‌های اقدامات (چپ)
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 26, height: 26)
                            .overlay(Image(systemName: "bookmark.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white))
                        Text(L.tr("Aurora"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(1)
                    }
                    .fixedSize()

                    Spacer(minLength: 6)

                    HStack(spacing: 6) {
                        ShellCheckBadge()
                        circleButton("bubble.left.and.bubble.right.fill", help: L.tr("Chats (⌘⇧C)")) {
                            NotificationCenter.default.post(name: .showChats, object: nil)
                        }
                        circleButton("command", help: L.tr("Command Palette (⌘K)")) {
                            NotificationCenter.default.post(name: .showPalette, object: nil)
                        }
                        if wide {
                            labelChip("arrow.down.circle.fill", title: L.tr("Video Downloader")) {
                                ShellTools.openVideoDownload()
                            }
                        } else {
                            circleButton("arrow.down.circle.fill", help: L.tr("Video Downloader")) {
                                ShellTools.openVideoDownload()
                            }
                        }
                        sortButton
                        moreButton

                        Button {
                            newAction()
                        } label: {
                            Group {
                                if wide {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                        Text(lib.scope == .mindMaps ? L.tr("New Map") : L.tr("New Bookmark"))
                                    }
                                    .padding(.horizontal, 13)
                                } else {
                                    Image(systemName: "plus")
                                        .frame(width: 32, height: 32)
                                }
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(height: 32)
                            .background(
                                Capsule().fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                                              startPoint: .top, endPoint: .bottom))
                            )
                            .shadow(color: Color.accentColor.opacity(0.35), radius: 7, y: 3)
                        }
                        .buttonStyle(.plain)
                        .help(lib.scope == .mindMaps ? L.tr("New Map") : L.tr("New Bookmark (⌘N)"))
                        .fixedSize()
                    }
                    .fixedSize()
                    // اندازه‌گیری عرض واقعی سطر اقدامات برای محاسبهٔ فاصلهٔ ایمن تب‌ها
                    .background(measured(.actions))
                }

                // تب‌ها دقیقاً روی محور مرکزی پنجره — اما تا جایی که با سطر
                // اقدامات برخورد نکنند (padding دوطرفه نصفش جابه‌جایی خالص است)
                HStack {
                    Spacer(minLength: 0)
                    tabCapsule(labelled: wide)
                        .background(measured(.tabs))
                    Spacer(minLength: 0)
                }
                .padding(.trailing, tabsShift(width: geo.size.width) * 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(.bar)
    }

    // MARK: فاصلهٔ ایمن بین کپسول تب‌ها و سطر اقدامات

    private enum BarMetric { case actions, tabs }

    /// عرض یکی از دو سرِ نوار را ثبت می‌کند (هر بار که تغییر کند)
    private func measured(_ metric: BarMetric) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { record(metric, proxy.size.width) }
                .onChange(of: proxy.size.width) { record(metric, $0) }
        }
    }

    private func record(_ metric: BarMetric, _ width: CGFloat) {
        guard width > 0 else { return }
        switch metric {
        case .actions where abs(width - actionsWidth) > 0.5: actionsWidth = width
        case .tabs where abs(width - tabsWidth) > 0.5: tabsWidth = width
        default: break
        }
    }

    /// چقدر باید کپسول تب‌ها را به سمتِ «سرِ نوار» (کنار نشان برنامه) بلغد تا
    /// با دکمه‌های سطر اقدامات برخورد نکند. صفر یعنی همه‌چیز جا هست.
    /// محاسبه در مختصات «فاصله از لبهٔ اقدامات» انجام می‌شود، پس در هر دو
    /// جهت چیدمان (راست‌به‌چپ/چپ‌به‌راست) درست است.
    private func tabsShift(width: CGFloat) -> CGFloat {
        guard width > 0, tabsWidth > 0, actionsWidth > 0 else { return 0 }
        let gap: CGFloat = 16            // حداقل فاصلهٔ خواسته‌شده
        let logoAllowance: CGFloat = 140 // عرض نشان برنامه + حاشیه (جلوی بلغدیدنِ بیش از حد)
        // برخورد = لبهٔ نزدیکِ تب‌ها به لبهٔ اقدامات، منهای فاصلهٔ خواسته
        let collision = actionsWidth + tabsWidth / 2 + gap - width / 2
        guard collision > 0 else { return 0 }
        let maxShift = width / 2 - tabsWidth / 2 - gap - logoAllowance
        return min(collision, max(0, maxShift))
    }

    /// کپسول تب‌ها: با برچسب (پنجرهٔ عریض) یا فقط آیکون (پنجرهٔ باریک)
    private func tabCapsule(labelled: Bool) -> some View {
        HStack(spacing: 4) {
            if labelled {
                tabButton(.all, title: L.tr("All"), icon: "square.grid.2x2.fill")
                tabButton(.starred, title: L.tr("Starred"), icon: "star.fill")
                tabButton(.unfiled, title: L.tr("Unfiled"), icon: "tray")
                tabButton(.mindMaps, title: L.tr("Mind Maps"), icon: "brain.head.profile")
                tabButton(.trash, title: L.tr("Trash"), icon: "trash.fill")
            } else {
                iconTabButton(.all, icon: "square.grid.2x2.fill", help: L.tr("All"))
                iconTabButton(.starred, icon: "star.fill", help: L.tr("Starred"))
                iconTabButton(.unfiled, icon: "tray", help: L.tr("Unfiled"))
                iconTabButton(.mindMaps, icon: "brain.head.profile", help: L.tr("Mind Maps"))
                iconTabButton(.trash, icon: "trash.fill", help: L.tr("Trash"))
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 3)

            if labelled {
                settingsTab
            } else {
                iconTabButton(nil, icon: "gearshape", help: L.tr("Settings (⌘,)"), isSettings: true)
            }
        }
        .padding(4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .fixedSize()
    }

    /// تب فقط‌آیکونی برای پنجرهٔ باریک
    private func iconTabButton(_ scope: Library.Scope?, icon: String, help: String, isSettings: Bool = false) -> some View {
        let active = !isSettings && lib.scope == scope
        return Button {
            if isSettings {
                AppActions.openSettings()
            } else if let scope {
                lib.scope = scope
                lib.selectedId = nil
                lib.selectedMindMapId = nil
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.secondary)
                .frame(width: 32, height: 30)
                .background(
                    Capsule().fill(active
                                   ? AnyShapeStyle(Color.accentColor)
                                   : AnyShapeStyle(Color.primary.opacity(0.05)))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func tabButton(_ scope: Library.Scope, title: String, icon: String) -> some View {
        let active = lib.scope == scope
        return Button {
            lib.scope = scope
            lib.selectedId = nil
            lib.selectedMindMapId = nil
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Color.white : Color.secondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(Color.accentColor)
                               : AnyShapeStyle(Color.primary.opacity(0.05)))
            )
        }
        .buttonStyle(.plain)
    }

    /// دکمهٔ تنظیمات در ردیف تب‌ها (هم‌شکل تب‌ها، با ترجمهٔ هر زبان)
    private var settingsTab: some View {
        Button {
            AppActions.openSettings()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "gearshape")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(L.tr("Settings"))
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(L.tr("Settings (⌘,)"))
    }

    private func circleButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// دکمهٔ کپسولی با آیکون + عنوان (برای ابزارهایی که باید دیده شوند)
    private func labelChip(_ icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(title)
        .fixedSize()
    }

    /// دکمهٔ مرتب‌سازی و منوی سرریز — هم‌شکل دکمه‌های دایره‌ای دیگر
    private var sortButton: some View {
        ShellSortMenu()
            .fixedSize()
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.primary.opacity(0.06)))
    }

    private var moreButton: some View {
        ShellMoreMenu()
            .fixedSize()
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.primary.opacity(0.06)))
    }

    // MARK: جستجوی شناور بزرگ

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField(lib.scope == .mindMaps
                      ? L.tr("Search mind maps by name, URL or text…")
                      : L.tr("Search in title, URL, tag and note…"),
                      text: $lib.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($searchFocused)
            if !lib.query.isEmpty {
                Button { lib.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: چیپ‌های افقی پوشه‌ها و برچسب‌ها

    private var chipRows: some View {
        VStack(spacing: 6) {
            // بدون ScrollView افقی: در RTL مک، جای اولیهٔ اسکرول افقی به‌هم می‌ریزد و
            // چیپ‌ها از صفحه بیرون می‌زنند. ViewThatFits اگر جا شد همه را می‌چیند،
            // وگرنه چند تای اول + منوی «پوشه‌ها» — همیشه داخل صفحه.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    folderChip(nil, name: L.tr("Unfiled"), count: lib.unfiledCount)
                    ForEach(lib.folders) { folder in
                        folderChip(folder.id, name: folder.name, count: lib.folderCounts[folder.id] ?? 0,
                                   color: folder.uiColor)
                    }
                }
                HStack(spacing: 6) {
                    folderChip(nil, name: L.tr("Unfiled"), count: lib.unfiledCount)
                    ForEach(Array(lib.folders.prefix(3))) { folder in
                        folderChip(folder.id, name: folder.name, count: lib.folderCounts[folder.id] ?? 0,
                                   color: folder.uiColor)
                    }
                    moreFoldersChip
                }
            }
            .padding(.horizontal, 16)

            if !lib.tags.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        ForEach(lib.tags) { tag in
                            tagChip(tag.name, count: tag.count)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(Array(lib.tags.prefix(4))) { tag in
                            tagChip(tag.name, count: tag.count)
                        }
                        moreTagsChip
                    }
                }
                .padding(.horizontal, 16)
            }

            if !lib.savedFilters.isEmpty {
                HStack(spacing: 6) {
                    ForEach(lib.savedFilters) { filter in
                        savedFilterChip(filter)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
    }

    /// چیپ منوی «پوشه‌ها» برای وقتی همه در ردیف جا نمی‌شوند
    private var moreFoldersChip: some View {
        Menu {
            ForEach(lib.folders) { folder in
                Button(folder.name) {
                    lib.scope = .folder(folder.id)
                    lib.selectedId = nil
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 10.5))
                Text(L.tr("Folders"))
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// چیپ منوی «برچسب‌ها» برای وقتی همه در ردیف جا نمی‌شوند
    private var moreTagsChip: some View {
        Menu {
            ForEach(lib.tags) { tag in
                Button("#" + tag.name) {
                    lib.scope = lib.scope == .tag(tag.name) ? .all : .tag(tag.name)
                    lib.selectedId = nil
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text("⋯")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L.tr("Tags"))
    }

    private func savedFilterChip(_ filter: Library.SavedFilter) -> some View {
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
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3])))
        }
        .buttonStyle(.plain)
        .help(L.tr("Apply Filter"))
    }

    private func folderChip(_ id: Int64?, name: String, count: Int, color: Color = .secondary) -> some View {
        let active = lib.scope == .folder(id ?? -1)
        return Button {
            if let id { lib.scope = .folder(id) } else { lib.scope = .unfiled }
            lib.selectedId = nil
        } label: {
            HStack(spacing: 5) {
                Circle().fill(active ? Color.accentColor : color)
                    .frame(width: 6, height: 6)
                Text(name)
                    .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                    .lineLimit(1)
                Text(Digits.fa(count))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(Color.accentColor.opacity(0.16))
                               : AnyShapeStyle(Color.primary.opacity(0.06)))
            )
            .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.5) : .clear))
        }
        .buttonStyle(.plain)
    }

    private func tagChip(_ name: String, count: Int) -> some View {
        let active = lib.scope == .tag(name)
        return Button {
            lib.scope = active ? .all : .tag(name)
            lib.selectedId = nil
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.system(size: 9, weight: .bold))
                Text(name).font(.system(size: 11.5)).lineLimit(1)
                Text(Digits.fa(count))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(active ? Color.accentColor : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule().fill(active
                               ? AnyShapeStyle(Color.accentColor.opacity(0.14))
                               : AnyShapeStyle(Color.primary.opacity(0.05)))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: محتوا — گرید کارت‌های تصویری

    private var content: some View {
        Group {
            if lib.scope == .mindMaps {
                mapGrid
            } else if lib.results.isEmpty {
                emptyState
            } else {
                cardGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardGrid: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVGrid(columns: adaptiveColumns(width: geo.size.width, min: 236, spacing: 14),
                          spacing: 14) {
                    ForEach(lib.results) { bookmark in
                        AuroraCard(bookmark: bookmark,
                                   selected: selection.contains(bookmark.id),
                                   hovered: hoverCard == bookmark.id,
                                   isTrash: lib.scope == .trash,
                                   onOpen: { lib.open(bookmark) },
                                   onEdit: { lib.editing = .edit(bookmark) })
                            .onTapGesture { select(bookmark) }
                            .onTapGesture(count: 2) { lib.open(bookmark) }
                            .onHover { inside in hoverCard = inside ? bookmark.id : nil }
                            .contextMenu { ShellBookmarkMenu(bookmark: bookmark) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .onChange(of: lib.scope) { _ in selection = [] }
    }

    /// با ⌘ یا ⇧ کلیک = افزودن/حذف از انتخاب؛ بدون آن = انتخاب تکی (مثل چیدمان کلاسیک)
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
            lib.selectedMindMapId = nil
        }
    }

    // MARK: نوار اقدامات گروهی شناور

    /// با انتخاب بیش از یک کارت ظاهر می‌شود
    @ViewBuilder
    private var bulkBar: some View {
        if selection.count > 1 && lib.scope != .mindMaps {
            HStack(spacing: 10) {
                Text(L.tf("%@ selected", Digits.fa(selection.count)))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                Divider().frame(height: 16)

                Menu {
                    ForEach(lib.folderOptions()) { option in
                        Button(option.label) {
                            lib.setFolder(Array(selection), folderId: option.id == 0 ? nil : option.id)
                            lib.notify(L.tr("Moved to folder"))
                            selection = []
                        }
                    }
                } label: {
                    Label(L.tr("Folder"), systemImage: "folder")
                        .font(.system(size: 11.5))
                }

                Menu {
                    ForEach(lib.tags) { tag in
                        Button("#" + tag.name) {
                            lib.addTagBulk(Array(selection), name: tag.name)
                            selection = []
                        }
                    }
                } label: {
                    Label(L.tr("Tag"), systemImage: "tag")
                        .font(.system(size: 11.5))
                }

                if lib.scope == .trash {
                    Button {
                        lib.restore(ids: Array(selection))
                        selection = []
                    } label: {
                        Label(L.tr("Restore"), systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11.5))
                    }
                    Button(role: .destructive) {
                        lib.purge(ids: Array(selection))
                        selection = []
                    } label: {
                        Label(L.tr("Delete Permanently"), systemImage: "trash")
                            .font(.system(size: 11.5))
                    }
                } else {
                    Button(role: .destructive) {
                        lib.delete(ids: Array(selection))
                        selection = []
                    } label: {
                        Label(L.tr("Delete Selected"), systemImage: "trash")
                            .font(.system(size: 11.5))
                    }
                }

                Button {
                    selection = []
                    lib.selectedId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L.tr("Clear Selection"))
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                Capsule().fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
            )
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func adaptiveColumns(width: CGFloat, min: CGFloat, spacing: CGFloat) -> [GridItem] {
        let usable = max(width - 32, min)
        let count = max(1, Int((usable + spacing) / (min + spacing)))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

    // MARK: کارت‌های نقشهٔ ذهنی

    private var mapGrid: some View {
        Group {
            if lib.mindMaps.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    ScrollView {
                        LazyVGrid(columns: adaptiveColumns(width: geo.size.width, min: 236, spacing: 14),
                                  spacing: 14) {
                            ForEach(lib.mindMaps) { map in
                                AuroraMapCard(record: map,
                                              selected: lib.selectedMindMapId == map.id)
                                    .onTapGesture { lib.selectedMindMapId = map.id }
                                    .contextMenu { ShellMindMapMenu(record: map) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
    }

    // MARK: حالت خالی

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: 96, height: 96)
                Image(systemName: lib.scope == .mindMaps ? "brain.head.profile" : "sparkles")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(lib.query.isBlank ? L.tr("No bookmarks here") : L.tr("No results found"))
                .font(.system(size: 16, weight: .medium))
            Text(lib.query.isBlank ? L.tr("Press ⌘N to add your first bookmark.") : L.tr("Try different words or type a domain."))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            if lib.query.isBlank && lib.scope != .mindMaps {
                Button { newAction() } label: {
                    Label(L.tr("New Bookmark"), systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newAction() {
        if lib.scope == .mindMaps {
            MindMapToolWindow.shared.show(url: "")
        } else {
            lib.editing = .new(folderId: ShellSupport.currentFolderId(lib))
        }
    }

    // MARK: پنل جزئیات شیشه‌ای (لبهٔ چپ)

    /// پس‌زمینهٔ تیرهٔ ملایم پشت پنل — فقط وقتی پنل باز است
    @ViewBuilder
    private var detailScrim: some View {
        if lib.selectedId != nil || lib.selectedMindMapId != nil {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .onTapGesture { closeDetail() }
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        if lib.selectedId != nil || lib.selectedMindMapId != nil {
                DetailView()
                    // maxHeight لازم است تا پنل تا بالا/پایینِ پنجره بکشد و
                    // نوار بالای شفق از پشتش بیرون نزند؛ بستن با ✕ سربرگ،
                    // کلیک روی پس‌زمینهٔ تیره یا Esc انجام می‌شود
                    .frame(width: 430)
                    .frame(maxHeight: .infinity)
                    .background(.regularMaterial)
                    .opaquePanelBacking()
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .shadow(color: .black.opacity(0.18), radius: 24, x: 4)
        }
    }

    private func closeDetail() {
        lib.selectedId = nil
        lib.selectedMindMapId = nil
    }
}

// MARK: - کارت تصویری شفق

private struct AuroraCard: View {
    let bookmark: Bookmark
    let selected: Bool
    let hovered: Bool
    let isTrash: Bool
    var onOpen: () -> Void = {}
    var onEdit: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(bookmark: bookmark, height: 138)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                HStack(spacing: 4) {
                    starBadge
                    if bookmark.isDead {
                        deadBadge
                    }
                }
                .padding(7)

                // اکشن‌های شیشه‌ای هنگام هاور: باز کردن + ویرایش
                if hovered && !isTrash {
                    HStack(spacing: 6) {
                        glassAction("arrow.up.forward", help: L.tr("Open")) { onOpen() }
                        glassAction("square.and.pencil", help: L.tr("Edit Bookmark")) { onEdit() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(8)
                    .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.title.isBlank ? bookmark.domain : bookmark.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    FaviconView(path: bookmark.favicon, size: 12)
                    Text(bookmark.domain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !bookmark.tags.isEmpty {
                        Text("#" + bookmark.tags[0])
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected
                              ? Color.accentColor.opacity(0.85)
                              : Color.primary.opacity(hovered ? 0.16 : 0.07),
                              lineWidth: selected ? 2 : 1)
        )
        .scaleEffect(hovered && !selected ? 1.015 : 1)
        .shadow(color: .black.opacity(hovered ? 0.14 : 0.05), radius: hovered ? 12 : 5, y: hovered ? 6 : 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovered)
    }

    private var starBadge: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(.ultraThinMaterial))
            .opacity(bookmark.starred ? 1 : 0)
    }

    private var deadBadge: some View {
        Image(systemName: "bolt.slash.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Circle().fill(Color.red.opacity(0.85)))
            .help(L.tr("Dead link"))
    }

    /// دکمهٔ گرد شیشه‌ای روی تصویر کارت
    private func glassAction(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - کارت نقشهٔ ذهنی شفق

private struct AuroraMapCard: View {
    let record: MindMapRecord
    let selected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.05)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 138)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.displayTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(record.sourceURL)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.07),
                              lineWidth: selected ? 2 : 1)
        )
    }
}
