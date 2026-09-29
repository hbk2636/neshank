import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var lib = Library.shared

    @AppStorage("checkOnLaunch") private var checkOnLaunch = false
    @AppStorage("saveContent") private var saveContent = true
    @AppStorage("captureScreenshot") private var captureScreenshot = true
    @AppStorage("autoFetch") private var autoFetch = true
    @AppStorage("hotkey") private var hotkeyRaw = HotKeyChoice.space.rawValue
    @AppStorage("appearance") private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage("accentColor") private var accentRaw = AccentPreset.system.rawValue
    @AppStorage("appTheme") private var themeRaw = UITheme.classic.rawValue
    @AppStorage("density") private var densityRaw = Density.comfortable.rawValue

    @AppStorage(AIConfig.baseURLKey) private var aiBaseURL = AIConfig.defaultBaseURL
    @AppStorage(AIConfig.apiKeyKey) private var aiKey = ""
    @AppStorage(AIConfig.modelKey) private var aiModel = AIConfig.defaultModel
    @AppStorage(AIConfig.profileKey) private var aiProfile = ""
    @AppStorage(AIConfig.modelModeKey) private var aiModelMode = "manual"

    @State private var models: [String] = []
    @State private var modelsBusy = false
    @State private var modelsError: String?

    @State private var confirmPurge = false
    @State private var showDedupe = false
    @State private var dupCount = 0
    @State private var aiBusy = false
    @State private var aiResult: String?
    @State private var aiOK = false

    private let accentColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    private let themeColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    /// فهرست نمایشی انتخابگر مدل: مدل‌های سرویس + مقدار فعلی (اگر دستی و خارج از فهرست باشد)
    private var displayModels: [String] {
        var set = models
        if !aiModel.isBlank, !set.contains(aiModel) { set.append(aiModel) }
        return set.sorted()
    }

    var body: some View {
        Form {
            Section(L.tr("General")) {
                Picker(L.tr("App Language"), selection: $lib.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }

                Toggle(L.tr("Check links automatically on launch"), isOn: $checkOnLaunch)
                Toggle(L.tr("Auto-fetch title, description and image when adding"), isOn: $autoFetch)

                Picker(L.tr("Default View Mode"), selection: $lib.viewMode) {
                    ForEach(Library.ViewMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Picker(L.tr("Quick Add Shortcut"), selection: $hotkeyRaw) {
                    ForEach(HotKeyChoice.allCases) { choice in
                        Text(choice.label).tag(choice.rawValue)
                    }
                }
                .onChange(of: hotkeyRaw) { value in
                    HotKeyCenter.shared.apply(HotKeyChoice(rawValue: value) ?? .space)
                }

                Text(L.tr("Opens the Quick Add panel when pressed in any app — no system permission needed."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L.tr("AI Assistant")) {
                TextField(L.tr("Base URL (OpenAI-compatible)"), text: $aiBaseURL)
                    .textSelection(.enabled)
                Text(L.tr("Example: https://opencode.ai/zen/go/v1 or https://api.openai.com/v1 — /chat/completions and /models are added automatically."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                SecureField(L.tr("Assistant API Key"), text: $aiKey)
                    .textSelection(.enabled)

                Text(L.tr("Privacy note: when you use the assistant, the page's saved text, your profile and your question are sent to the assistant service above."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Picker(L.tr("Model Selection Mode"), selection: $aiModelMode) {
                    Text(L.tr("From Provider List")).tag("list")
                    Text(L.tr("Manual Entry")).tag("manual")
                }
                .pickerStyle(.segmented)
                .onChange(of: aiModelMode) { mode in
                    if mode == "list", models.isEmpty, !aiKey.isBlank {
                        loadModels()
                    }
                }

                if aiModelMode == "list" {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Picker(L.tr("Model"), selection: $aiModel) {
                                ForEach(displayModels, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 340)

                            Button {
                                loadModels()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(modelsBusy || aiKey.isBlank)
                            .help(L.tr("Fetch model list from provider"))

                            if modelsBusy {
                                ProgressView().controlSize(.small)
                            }
                        }

                        HStack {
                            Button(L.tr("Test This Model")) {
                                probeCurrentModel()
                            }
                            .disabled(probeBusy || aiKey.isBlank)
                            .controlSize(.small)
                            .help(L.tr("Sends a small request for this model only — checks compatibility with the chat protocol"))

                            if probeBusy {
                                ProgressView().controlSize(.small)
                            }

                            if let result = probeResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundStyle(probeOK ? Color.green : Color.red)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                        }

                        if let err = modelsError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        } else if !models.isEmpty {
                            Text(L.tf("%@ models fetched from the provider and kept between launches. Some models may not support the chat protocol — verify with “Test This Model”.", Digits.fa(models.count)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    TextField(L.tr("Model name (e.g. deepseek-v4.1-flash)"), text: $aiModel)
                        .textSelection(.enabled)
                }

                VStack(alignment: .trailing, spacing: 6) {
                    Text(L.tr("My Profile"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $aiProfile)
                        .font(.callout)
                        .frame(height: 84)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.12))
                        )

                    Text(L.tr("Write who you are, what you look for, your budget and technical level — e.g. “I'm a UI designer; budget up to 2M tomans; looking for a color-accurate monitor for the office”. The assistant weighs answers against this."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button {
                        testConnection()
                    } label: {
                        Label(L.tr("Test Connection"), systemImage: "bolt.horizontal.circle")
                    }
                    .disabled(aiBusy)

                    if aiBusy {
                        ProgressView().controlSize(.small)
                    }

                    if let result = aiResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(aiOK ? Color.green : Color.red)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }

                Text(L.tr("The Sparkle (✦) button or ⌘⇧D on the selected bookmark opens the assistant panel; quick questions and free chat are there too."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L.tr("Appearance")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L.tr("Theme"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: themeColumns, spacing: 12) {
                        ForEach(UITheme.allCases) { item in
                            Button {
                                themeRaw = item.rawValue
                            } label: {
                                VStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(item.background.map { AnyShapeStyle($0) }
                                              ?? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)))
                                        .frame(height: 46)
                                        .overlay(alignment: .bottomLeading) {
                                            Circle()
                                                .fill(item.accentColor ?? Color(nsColor: .controlAccentColor))
                                                .frame(width: 14, height: 14)
                                                .padding(6)
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9).strokeBorder(
                                                themeRaw == item.id
                                                    ? Color.primary.opacity(0.75)
                                                    : Color.primary.opacity(0.15),
                                                lineWidth: themeRaw == item.id ? 2 : 1
                                            )
                                        )
                                        .overlay(alignment: .topTrailing) {
                                            if themeRaw == item.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(.primary)
                                                    .padding(5)
                                            }
                                        }
                                    Text(item.label)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(item.label)
                        }
                    }

                    if UITheme(rawValue: themeRaw) != .classic {
                        Text(L.tr("The theme sets its own light/dark look; “Light Mode” applies to Classic only."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Picker(L.tr("Light Mode"), selection: $appearanceRaw) {
                    ForEach(AppearanceChoice.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                }

                Picker(L.tr("List Density"), selection: $densityRaw) {
                    ForEach(Density.allCases) { item in
                        Text(item.label).tag(item.rawValue)
                    }
                }

                VStack(alignment: .trailing, spacing: 8) {
                    Text(L.tr("App Color"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: accentColumns, spacing: 8) {
                        ForEach(AccentPreset.allCases) { preset in
                            Button {
                                accentRaw = preset.rawValue
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(preset.swatch)
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Circle().strokeBorder(
                                                accentRaw == preset.id
                                                    ? Color.primary.opacity(0.7)
                                                    : Color.primary.opacity(0.12),
                                                lineWidth: accentRaw == preset.id ? 2 : 1
                                            )
                                        )
                                    Text(preset.label)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Section(L.tr("Text Archive")) {
                Toggle(L.tr("Archive full page text when adding"), isOn: $saveContent)
                Text(L.tr("Page text is archived and feeds deep search and the AI assistant's context — even if the site goes offline."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L.tr("Capture real page screenshots for cards"), isOn: $captureScreenshot)
                Text(L.tr("A background screenshot is captured and replaces the favicon in cards and boxes."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L.tr("Data")) {
                LabeledContent(L.tr("Database")) {
                    Text(AppPaths.dbPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                HStack {
                    Button(L.tr("Show in Finder")) {
                        AppPaths.revealInFinder()
                    }
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

                // بک‌آپ روزانه خودکار + بک‌آپ فوری
                LabeledContent(L.tr("Backups")) {
                    HStack {
                        Button(L.tr("Back Up Now")) {
                            do {
                                let url = try lib.backUpNow()
                                lib.notify(L.tf("Backup created: %@", url.lastPathComponent))
                            } catch {
                                lib.notify(L.tf("Backup failed: %@", error.localizedDescription))
                            }
                        }
                        Button(L.tr("Show Backups in Finder")) {
                            NSApp.activate(ignoringOtherApps: true)
                            NSWorkspace.shared.open(AppPaths.backupsDir)
                        }
                    }
                }
                Text(L.tr("A snapshot is taken automatically once a day; the last 5 automatic copies are kept (each a few hundred KB). Manual backups are never deleted."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(L.tr("Find & Remove Duplicates…")) {
                        dupCount = lib.duplicateGroups().reduce(0) { $0 + ($1.count - 1) }
                        if dupCount == 0 {
                            lib.notify(L.tr("No duplicate bookmarks found"))
                        } else {
                            showDedupe = true
                        }
                    }

                    Button(L.tr("Empty Trash"), role: .destructive) {
                        confirmPurge = true
                    }
                    .disabled(lib.counts.trash == 0)
                }

                HStack {
                    Button(L.tr("Check All Links")) {
                        Task { await lib.checkAllLinks() }
                    }
                    .disabled(lib.isChecking)

                    if lib.isChecking {
                        ProgressView(value: lib.checkProgress)
                            .frame(width: 140)
                    }

                    Button(L.tr("Delete Dead Bookmarks"), role: .destructive) {
                        confirmPurgeDead = true
                    }
                    .disabled(lib.counts.dead == 0)
                }

                if let last = lib.lastCheck {
                    Text(L.tf("Last check: %@", Dates.persianDateTime(last)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L.tr("Statistics")) {
                LabeledContent(L.tr("Bookmarks"), value: Digits.fa(lib.counts.all))
                LabeledContent(L.tr("Starred"), value: Digits.fa(lib.counts.starred))
                LabeledContent(L.tr("Unread"), value: Digits.fa(lib.counts.unread))
                LabeledContent(L.tr("Trash"), value: Digits.fa(lib.counts.trash))
                LabeledContent(L.tr("Folders"), value: Digits.fa(lib.flattenFolders(lib.folders).count))
                LabeledContent(L.tr("Tags"), value: Digits.fa(lib.tags.count))
                LabeledContent(L.tr("Saved Filters"), value: Digits.fa(lib.savedFilters.count))
            }

            Section(L.tr("About")) {
                Text(L.tr("Neshank — native macOS bookmark manager, built with SwiftUI and SQLite."))
                Text(L.tr("Made by hosein shahraki"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 740)
        .tint(AppTheme.accent)
        .preferredColorScheme(AppTheme.appearance)
        .onAppear {
            if models.isEmpty {
                models = UserDefaults.standard.string(forKey: AIConfig.modelsCacheKey)?
                    .split(separator: "\n").map(String.init) ?? []
            }
            if aiModelMode == "list", models.isEmpty, !aiKey.isBlank {
                loadModels()
            }
        }
        .confirmationDialog(L.tr("Empty Trash?"), isPresented: $confirmPurge) {
            Button(L.tr("Delete Permanently"), role: .destructive) {
                lib.emptyTrash()
            }
        } message: {
            Text(L.tf("%@ bookmarks will be deleted permanently.", Digits.fa(lib.counts.trash)))
        }
        .confirmationDialog(L.tr("Remove duplicate bookmarks?"), isPresented: $showDedupe) {
                Button(L.tf("Delete %@ Extra Copies", Digits.fa(dupCount)), role: .destructive) {
                let n = lib.removeDuplicates()
                lib.notify(L.tf("%@ duplicate copies moved to Trash", Digits.fa(n)))
            }
        } message: {
            Text(L.tr("In each group the newest copy is kept and the rest go to Trash."))
        }
        .confirmationDialog(L.tr("Delete all dead bookmarks?"), isPresented: $confirmPurgeDead) {
                Button(L.tr("Delete"), role: .destructive) {
                lib.deleteDead()
            }
        } message: {
            Text(L.tf("%@ bookmarks will be deleted.", Digits.fa(lib.counts.dead)))
        }
    }

    @State private var confirmPurgeDead = false
    @State private var probeBusy = false
    @State private var probeResult: String?
    @State private var probeOK = false

    /// سنجش دستی سازگاری مدل فعلی — فقط با کلیک کاربر و یک درخواست کوچک
    private func probeCurrentModel() {
        guard !probeBusy else { return }
        probeBusy = true
        probeResult = nil
        let cfg = AIConfig(baseURL: aiBaseURL, apiKey: aiKey, model: aiModel, profile: aiProfile)
        Task {
            do {
                try await AIClient.probeModel(config: cfg)
                probeResult = L.tr("✅ This model supports chat")
                probeOK = true
            } catch {
                probeResult = L.tf("❌ %@", error.localizedDescription)
                probeOK = false
            }
            probeBusy = false
        }
    }

    /// دریافت فهرست مدل‌ها از سرویس با آدرس و کلیدِ همین لحظهٔ فرم + ذخیره در کش
    private func loadModels() {
        guard !modelsBusy else { return }
        modelsBusy = true
        modelsError = nil
        let cfg = AIConfig(baseURL: aiBaseURL, apiKey: aiKey, model: aiModel, profile: aiProfile)
        Task {
            do {
                let list = try await AIClient.fetchModels(config: cfg)
                models = list
                UserDefaults.standard.set(list.joined(separator: "\n"), forKey: AIConfig.modelsCacheKey)
                if aiModel.isBlank || !list.contains(aiModel) {
                    aiModel = list.first ?? aiModel
                }
            } catch {
                modelsError = error.localizedDescription
            }
            modelsBusy = false
        }
    }

    /// آزمایش زندهٔ اتصال به سرویس دستیار — با مقادیر همین لحظهٔ فرم، نه انبار
    private func testConnection() {
        aiBusy = true
        aiResult = nil
        let cfg = AIConfig(baseURL: aiBaseURL, apiKey: aiKey, model: aiModel, profile: aiProfile)
        let session = AIClient.newSession()
        Task {
            do {
                let answer = try await AIClient.chat(
                    config: cfg,
                    session: session,
                    messages: [.user("Reply with just the word «OK».")],
                    maxTokens: 3000
                )
                aiResult = L.tf("✅ Connected — “%@”", String(answer.prefix(60)))
                aiOK = true
            } catch {
                aiResult = L.tf("❌ %@", error.localizedDescription)
                aiOK = false
            }
            aiBusy = false
        }
    }
}
