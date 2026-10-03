import SwiftUI

// MARK: - کارت راهنمای اتصال سرویس هوش مصنوعی (بار اول)

/// باکس راهنمای «اولین اتصال» — در صفحهٔ اصلی نقشهٔ ذهنی بالا می‌آید تا کاربر
/// همان‌جا آدرس پروایدر، کلید API و مدل را وارد کند؛ با «تأیید و اتصال»
/// (یک درخواست کوچک واقعی) ذخیره و بسته می‌شود. مقادیر مستقیم در
/// AppStorage می‌نشینند، پس با موفقیت این کارت، تنظیمات برنامه هم کامل است.
struct AISetupCard: View {

    /// وقتی خطا از سمت سرویس رخ داده باشد، کارت با هشدار قرمز باز می‌شود
    var problemHint: Bool = false
    /// پس از تأیید موفق اتصال صدا زده می‌شود (کارت بسته می‌شود)
    var onVerified: () -> Void

    @AppStorage(AIConfig.baseURLKey) private var baseURL = AIConfig.defaultBaseURL
    @AppStorage(AIConfig.apiKeyKey) private var apiKey = ""
    @AppStorage(AIConfig.modelKey) private var model = AIConfig.defaultModel
    @AppStorage(AIConfig.modelModeKey) private var modelMode = "manual"

    @State private var models: [String] = []
    @State private var busy = false
    @State private var fetchError: String?
    @State private var verified = false

    private var displayModels: [String] {
        var set = models
        if !model.isBlank, !set.contains(model) { set.append(model) }
        return set
    }

    private var readyToVerify: Bool {
        !baseURL.trimmed.isBlank && !apiKey.isBlank
            && (modelMode == "list" ? !model.isBlank : !model.trimmed.isBlank)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // ۱) آدرس پروایدر
            fieldLabel(L.tr("1. Provider Address (Base URL)"), icon: "globe")
            TextField(L.tr("Base URL (OpenAI-compatible)"), text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .textSelection(.enabled)
            Text(L.tr("Example: https://api.openai.com/v1 — /chat/completions and /models are added automatically."))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // ۲) کلید API
            fieldLabel(L.tr("2. API Key"), icon: "key.fill")
            SecureField(L.tr("Assistant API Key"), text: $apiKey)
                .textFieldStyle(.roundedBorder)

            // ۳) مدل — خودکار از سرویس یا دستی
            fieldLabel(L.tr("3. Model"), icon: "cpu.fill")
            Picker(L.tr("Model Selection Mode"), selection: $modelMode) {
                Text(L.tr("From Provider List")).tag("list")
                Text(L.tr("Manual Entry")).tag("manual")
            }
            .pickerStyle(.segmented)
            .onChange(of: modelMode) { mode in
                if mode == "list", models.isEmpty, readyToVerify { loadModels() }
            }

            if modelMode == "list" {
                VStack(alignment: .leading, spacing: 8) {
                    if models.isEmpty {
                        // هنوز فهرستی نیست — دکمهٔ واضح با نام گویا
                        HStack(spacing: 8) {
                            Button {
                                loadModels()
                            } label: {
                                Label(L.tr("Import Models"), systemImage: "square.and.arrow.down")
                                    .frame(minHeight: 26)
                            }
                            .buttonStyle(.bordered)
                            .disabled(busy || apiKey.isBlank || baseURL.trimmed.isBlank)
                            if busy { ProgressView().controlSize(.small) }
                        }
                        Text(L.tr("Fetches the model list from your provider using the address and key above."))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        HStack(spacing: 8) {
                            Picker(L.tr("Model"), selection: $model) {
                                ForEach(displayModels, id: \.self) { m in Text(m).tag(m) }
                            }
                            .labelsHidden()
                            Button {
                                loadModels()
                            } label: {
                                Label(L.tr("Update Models"), systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(busy || apiKey.isBlank || baseURL.trimmed.isBlank)
                            .help(L.tr("Fetch model list from provider"))
                            if busy { ProgressView().controlSize(.small) }
                        }
                        Text(L.tf("%@ models fetched from the provider and kept between launches. Some models may not support the chat protocol — verify with “Test This Model”.", Digits.fa(models.count)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let err = fetchError {
                        Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                    }
                }
            } else {
                TextField(L.tr("Model name (e.g. gpt-4o-mini)"), text: $model)
                    .textFieldStyle(.roundedBorder)
                    .textSelection(.enabled)
            }

            verifyRow
        }
        .padding(16)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.accentColor.opacity(problemHint ? 0.16 : 0.10),
                                              Color.accentColor.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(problemHint ? Color.red.opacity(0.45) : Color.accentColor.opacity(0.25),
                              lineWidth: 1)
        )
        .onAppear {
            if models.isEmpty,
               let cached = UserDefaults.standard.string(forKey: AIConfig.modelsCacheKey),
               !cached.isEmpty {
                models = cached.components(separatedBy: "\n").filter { !$0.isEmpty }
            }
            if modelMode == "list", models.isEmpty, readyToVerify { loadModels() }
        }
    }

    // MARK: سربرگ

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: problemHint ? "exclamationmark.shield.fill" : "wand.and.stars")
                .font(.system(size: 20))
                .foregroundStyle(problemHint ? Color.red : Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.tr("Connect the AI Assistant"))
                    .font(.system(size: 14, weight: .semibold))
                Text(problemHint
                     ? L.tr("The AI service reported a problem — check the address, key and model.")
                     : L.tr("To turn pages into mind maps, connect an OpenAI-compatible service: enter the provider address and API key, choose a model, then verify the connection."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func fieldLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    // MARK: تأیید و اتصال

    private var verifyRow: some View {
        HStack(spacing: 10) {
            Button {
                verify()
            } label: {
                Label(L.tr("Verify & Connect"), systemImage: verified ? "checkmark.circle.fill" : "bolt.horizontal.circle.fill")
                    .frame(minWidth: 130, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!readyToVerify || busy)

            if busy { ProgressView().controlSize(.small) }

            if verified {
                Label(L.tr("✅ Connected — mind maps are ready to build"), systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.25), value: verified)
    }

    /// یک درخواست کوچک واقعی با مقادیر همین فرم — موفقیت یعنی آدرس+کلید+مدل هر سه سالم‌اند
    private func verify() {
        guard !busy else { return }
        busy = true
        fetchError = nil
        let cfg = AIConfig(baseURL: baseURL, apiKey: apiKey, model: model, profile: "")
        Task {
            do {
                // در حالت فهرستی، اگر مدل خالی است اول مدل‌ها را بگیر
                if model.isBlank, modelMode == "list" {
                    let list = try await AIClient.fetchModels(config: cfg)
                    models = list
                    UserDefaults.standard.set(list.joined(separator: "\n"), forKey: AIConfig.modelsCacheKey)
                    model = list.first ?? model
                }
                try await AIClient.probeModel(config: cfg)
                withAnimation { verified = true }
                try? await Task.sleep(nanoseconds: 900_000_000)
                busy = false
                onVerified()
            } catch {
                fetchError = error.localizedDescription
                busy = false
            }
        }
    }

    private func loadModels() {
        guard !busy else { return }
        busy = true
        fetchError = nil
        let cfg = AIConfig(baseURL: baseURL, apiKey: apiKey, model: model, profile: "")
        Task {
            do {
                let list = try await AIClient.fetchModels(config: cfg)
                models = list
                UserDefaults.standard.set(list.joined(separator: "\n"), forKey: AIConfig.modelsCacheKey)
                if model.isBlank || !list.contains(model) {
                    model = list.first ?? model
                }
            } catch {
                fetchError = error.localizedDescription
            }
            busy = false
        }
    }
}
