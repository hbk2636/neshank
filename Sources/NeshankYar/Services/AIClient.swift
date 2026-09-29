import Foundation
import Security

// MARK: - پیکربندی دستیار هوشمند

/// ابزار Keychain — امروز فقط برای «مهاجرت خروج» از نسخهٔ ۱.۴ استفاده می‌شود.
/// با امضای ad-hoc (تغییر هش در هر بیلد) Keychain مدام پنجرهٔ رمز باز می‌کند،
/// برای همین کلید API در prefs کاربر نگه داشته می‌شود؛ اگر روزی با Developer ID
/// امضا/notarize شد، ذخیرهٔ Keychain با همین ابزار دوباره فعال می‌شود.
enum KeychainStore {
    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// حذف آیتم (برای جلوگیری از واگرایی دو انبار وقتی نوشتن Keychain شکست می‌خورد)
    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// مقدار خالی = حذف آیتم. true یعنی عملیات Keychain موفق بود.
    @discardableResult
    static func write(_ value: String, service: String, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return true }
        var attrs = base
        attrs[kSecValueData as String] = Data(value.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}

/// تنظیمات اتصال دستیار (پروتکل سازگار با OpenAI).
///
/// کاربر آدرس پایه، کلید و مدل را در تنظیمات می‌دهد؛ مدل یا دستی وارد می‌شود
/// یا از فهرست مدل‌های همان سرویس (GET /models) انتخاب می‌شود.
struct AIConfig: Sendable {
    static let defaultBaseURL = "https://opencode.ai/zen/go/v1"
    static let defaultModel = "deepseek-v4.1-flash"

    static let baseURLKey = "aiBaseURL"
    /// کلید API دیگر در UserDefaults ذخیره نمی‌شود؛ این کلید فقط برای مهاجرتِ
    /// یک‌بارهٔ نسخه‌های قدیمی به Keychain استفاده می‌شود.
    static let apiKeyKey = "aiApiKey"
    static let modelKey = "aiModel"
    static let profileKey = "aiProfile"
    /// حالت انتخاب مدل: "list" = از فهرست سرویس، "manual" = ورود دستی
    static let modelModeKey = "aiModelMode"
    static let modelsCacheKey = "aiModelsCache"

    static let keychainService = "com.gozaresh.neshankyar.assistant"
    static let keychainAccount = "api-key"

    var baseURL: String
    var apiKey: String
    var model: String
    /// پروفایل کاربر: تخصص، نیازها، بودجه و شرایط — مبنای قضاوت دستیار
    var profile: String

    /// آدرس کامل «گفتگو»
    var endpoint: URL? {
        Self.url(baseURL, path: "chat/completions")
    }

    /// آدرس کامل «فهرست مدل‌ها»
    var modelsEndpoint: URL? {
        Self.url(baseURL, path: "models")
    }

    private static func url(_ raw: String, path: String) -> URL? {
        var base = raw.trimmed
        while base.hasSuffix("/") { base = String(base.dropLast()) }
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/" + path)
    }

    var isConfigured: Bool { !apiKey.isBlank && endpoint != nil }

    static func load() -> AIConfig {
        let d = UserDefaults.standard
        var key = d.string(forKey: apiKeyKey) ?? ""
        if key.isEmpty {
            // مهاجرت یک‌باره از نسخهٔ ۱.۴ که کلید موقتاً در Keychain بود.
            // آیتم ناموجود بدون هیچ پنجره‌ای رد می‌شود؛ فقط اگر واقعاً آیتمی باشد
            // (نصب قدیمی) ممکن است سیستم یک بار مجوز بخواهد و بلافاصله حذف می‌شود.
            if let migrated = KeychainStore.read(service: keychainService, account: keychainAccount),
               !migrated.isEmpty {
                key = migrated
                d.set(migrated, forKey: apiKeyKey)
                KeychainStore.delete(service: keychainService, account: keychainAccount)
            }
        }
        return AIConfig(
            baseURL: d.string(forKey: baseURLKey) ?? defaultBaseURL,
            apiKey: key,
            model: d.string(forKey: modelKey) ?? defaultModel,
            profile: d.string(forKey: profileKey) ?? ""
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: Self.baseURLKey)
        d.set(apiKey, forKey: Self.apiKeyKey)
        d.set(model, forKey: Self.modelKey)
        d.set(profile, forKey: Self.profileKey)
        // Keychain با امضای ad-hoc (تغییر در هر بیلد) مدام پنجرهٔ رمز باز می‌کند و
        // کاربر را می‌ترساند؛ کلید مثل بقیهٔ تنظیمات در prefs کاربر می‌ماند و
        // آیتم احتمالی Keychain پاک می‌شود تا دیگر هرگز درخواست رمز نداشته باشیم.
        KeychainStore.delete(service: Self.keychainService, account: Self.keychainAccount)
    }
}

// MARK: - کلاینت دستیار

enum AIClient {
    struct Message: Codable, Equatable, Sendable {
        let role: String    // system | user | assistant
        let content: String

        static func system(_ t: String) -> Message { Message(role: "system", content: t) }
        static func user(_ t: String) -> Message { Message(role: "user", content: t) }
        static func assistant(_ t: String) -> Message { Message(role: "assistant", content: t) }
    }

    enum Failure: LocalizedError {
        case notConfigured
        case badURL
        case network(String)
        case http(Int, String)
        case empty
        case truncated
        case badList(String)
        case noModels
        case unsupportedModel(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return L.tr("Assistant key is not set (Settings → AI Assistant).")
            case .badURL:
                return L.tr("The assistant service address is invalid.")
            case .network(let m):
                return L.tf("Network error: %@", m)
            case .http(let code, let m):
                return L.tf("Service response (%@): %@", Digits.fa(code), m)
            case .empty:
                return L.tr("The response was empty; please try again.")
            case .truncated:
                return L.tr("The model could not finish within the token limit (its internal reasoning got too long); try again or shorten the page text.")
            case .badList(let m):
                return L.tf("The model list could not be read: %@", m)
            case .noModels:
                return L.tr("The service returned no models; enter the model name manually.")
            case .unsupportedModel(let m):
                return L.tf("This model is not compatible with the service chat protocol — in Settings → AI Assistant, pick another model from the list (e.g. deepseek-v4.1-flash). Service message: %@", m)
            }
        }

        /// تشخیص ردشدن مدل به‌خاطر ناسازگاری پروتکل (مثال واقعی opencode:
        /// «Model does not support this protocol.» برای muse-spark)
        static func unsupportedIfProtocolRejected(_ code: Int, _ msg: String) -> Failure? {
            guard code == 400 else { return nil }
            let lower = msg.lowercased()
            if lower.contains("does not support") || lower.contains("not supported")
                || lower.contains("protocol") {
                return .unsupportedModel(msg)
            }
            return nil
        }
    }

    // MARK: ساخت درخواست (تست‌پذیر، بدون شبکه)

    /// شناسهٔ نشست برای هدر `x-opencode-session` — برای هر گفتگو یکتا.
    static func newSession() -> String { UUID().uuidString.lowercased() }

    /// فهرست مدل‌های ارائه‌دهنده (پروتکل سازگار با OpenAI: GET …/models).
    /// خروجی مرتب و بدون تکرار؛ برای پر کردن انتخابگر مدل در تنظیمات.
    static func fetchModels(config: AIConfig) async throws -> [String] {
        guard !config.apiKey.isBlank else { throw Failure.notConfigured }
        guard let url = config.modelsEndpoint else { throw Failure.badURL }

        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("Neshank/1.0 (macOS bookmark assistant)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw Failure.badList(L.tr("Invalid HTTP response"))
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw Failure.http(http.statusCode, body.isEmpty ? L.tr("Fetching the model list failed") : body)
        }

        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Failure.badList(L.tr("The response was not JSON"))
        }
        var ids: [String] = []
        if let dict = obj as? [String: Any], let list = dict["data"] as? [[String: Any]] {
            ids = list.compactMap { ($0["id"] as? String)?.isEmpty == false ? $0["id"] as? String : nil }
        } else if let list = obj as? [[String: Any]] {
            ids = list.compactMap { ($0["id"] as? String)?.isEmpty == false ? $0["id"] as? String : nil }
        } else if let list = obj as? [String] {
            ids = list
        }
        let cleaned = Array(Set(ids)).sorted()
        guard !cleaned.isEmpty else { throw Failure.noModels }
        return cleaned
    }

    /// `reasoningEffort`: مدل استدلال‌گر است و بدون محدودیت، کل بودجهٔ توکن را صرف `reasoning_content`
    /// می‌کند و `content` خالی می‌ماند. آزمایش: با `low` استدلال از ۱۸۱۵۴ به ۶۸۲۷ نویسه رسید و پاسخ کامل شد.
    static func makeRequest(config: AIConfig,
                            session: String,
                            messages: [Message],
                            maxTokens: Int = 2400,
                            reasoningEffort: String? = nil,
                            temperature: Double? = nil) -> URLRequest? {
        guard let url = config.endpoint else { return nil }

        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let max_tokens: Int
            let reasoning_effort: String?
            let temperature: Double?
            let stream = false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        // سرویس Go برای مسیریابی به این هدر نیاز دارد (مستندات opencode.ai/docs/go)
        req.setValue(session, forHTTPHeaderField: "x-opencode-session")
        req.setValue("Neshank/1.0 (macOS bookmark assistant)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONEncoder().encode(Body(model: config.model,
                                                      messages: messages,
                                                      max_tokens: maxTokens,
                                                      reasoning_effort: reasoningEffort,
                                                      temperature: temperature))
        return req
    }

    /// سنجش دستی سازگاری «همین یک مدل» با پروتکل گفتگو — فقط با کلیک کاربر اجرا می‌شود،
    /// بدون رشد خودکار توکن و بدون تست سایر مدل‌ها.
    static func probeModel(config: AIConfig) async throws {
        guard !config.apiKey.isBlank else { throw Failure.notConfigured }
        guard let req = makeRequest(config: config, session: newSession(),
                                    messages: [.user("Reply with just «OK».")],
                                    maxTokens: 256)
        else { throw Failure.badURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.error?.message
                ?? String(raw.prefix(240))
            if let rejected = Failure.unsupportedIfProtocolRejected(code, msg) {
                throw rejected
            }
            throw Failure.http(code, msg)
        }
    }

    // MARK: فراخوانی

    static func chat(config: AIConfig,
                     session: String,
                     messages: [Message],
                     maxTokens: Int = 2400,
                     reasoningEffort: String? = nil,
                     temperature: Double? = nil) async throws -> String {
        guard config.isConfigured else { throw Failure.notConfigured }
        guard let req = makeRequest(config: config, session: session,
                                    messages: messages, maxTokens: maxTokens,
                                    reasoningEffort: reasoningEffort,
                                    temperature: temperature)
        else { throw Failure.badURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure.network(error.localizedDescription)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let raw = String(data: data, encoding: .utf8) ?? ""

        // فقط پاسخ‌های غیرموفق خطای سرویس‌اند؛ در پاسخ موفق کلیدی به نام error نیست
        guard (200..<300).contains(code) else {
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.error?.message
                ?? String(raw.prefix(240))
            if let rejected = Failure.unsupportedIfProtocolRejected(code, msg) {
                throw rejected
            }
            if code == 400 {
                let lower = msg.lowercased()
                // برخی مدل‌ها/سرویس‌ها پارامتر reasoning_effort را نمی‌پذیرند — بدون آن تلاش کن
                if reasoningEffort != nil,
                   lower.contains("reasoning") || lower.contains("effort") {
                    return try await chat(config: config, session: session, messages: messages,
                                          maxTokens: maxTokens, reasoningEffort: nil,
                                          temperature: temperature)
                }
                // برخی سرویس‌ها سقف max_tokens کمتری دارند — با نصف‌کردن بودجه تلاش کن
                if lower.contains("max_tokens") || lower.contains("max tokens")
                    || lower.contains("context length"), maxTokens > 1_024 {
                    return try await chat(config: config, session: session, messages: messages,
                                          maxTokens: maxTokens / 2, reasoningEffort: reasoningEffort,
                                          temperature: temperature)
                }
            }
            throw Failure.http(code, msg)
        }

        guard let out = try? JSONDecoder().decode(ChatResponse.self, from: data) else {
            throw Failure.http(code, String(raw.prefix(240)))
        }
        let choice = out.choices.first
        let text = choice?.message.content?.trimmed ?? ""

        // پاسخ خالی یا ناقص (`finish_reason=length`) را success حساب نکن؛
        // بودجه را زیاد کن و reasoning را محدود کن، وگرنه JSON نیمه‌کاره به UI می‌رسد.
        if (text.isEmpty || choice?.finish_reason == "length"), maxTokens < Self.maxTokenCeiling {
            let bigger = min(Self.maxTokenCeiling, maxTokens * 3)
            do {
                return try await chat(config: config,
                                      session: session,
                                      messages: messages,
                                      maxTokens: bigger,
                                      reasoningEffort: reasoningEffort ?? "low",
                                      temperature: temperature)
            } catch Failure.http(let code, _) where code == 400 {
                // پروایدر فیلد reasoning_effort را نمی‌پذیرد؛ فقط بودجه را زیاد می‌کنیم.
                return try await chat(config: config,
                                      session: session,
                                      messages: messages,
                                      maxTokens: bigger,
                                      reasoningEffort: nil,
                                      temperature: temperature)
            }
        }
        guard !text.isEmpty else {
            if choice?.finish_reason == "length" {
                throw Failure.truncated
            }
            throw Failure.empty
        }
        if choice?.finish_reason == "length" {
            throw Failure.truncated
        }
        return text
    }

    /// مدل استدلال‌گر است؛ برای JSON بلند بودجهٔ کافی لازم است (آزمایش: ۴۲۰۰ کم بود، ۱۲۰۰۰ کافی بود).
    private static let maxTokenCeiling = 16_000

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Msg: Decodable {
                let content: String?
                let reasoning_content: String?
            }
            let message: Msg
            let finish_reason: String?
        }
        let choices: [Choice]
    }

    private struct APIError: Decodable {
        struct E: Decodable {
            let message: String?
        }
        let error: E?
    }

    // MARK: پرامپت (بر پایهٔ نیاز کاربر)

    /// برش متن بلند (برای نگه‌داشتن پاسخ در بودجهٔ زمینه) — خروجی هرگز از سقف بیشتر نمی‌شود
    static func clip(_ s: String, _ max: Int) -> String {
        guard s.count > max else { return s }
        guard max > 1 else { return "…" }
        return String(s.prefix(max - 1)) + "…"
    }

    /// پرامپت سیستم: زمینهٔ کاربر + مشخصات نشانک + متن صفحه + قواعد پاسخ
    static func systemPrompt(profile: String,
                             title: String,
                             url: String,
                             domain: String,
                             note: String,
                             tags: [String],
                             savedAt: String,
                             pageContent: String?,
                             maxContent: Int = 14_000) -> String {
        let who = profile.isBlank
            ? "(هنوز پروفایلی ثبت نشده — در تنظیمات ← «دستیار هوشمند» بنویسید که چه کسی هستید و دنبال چه می‌گردید)"
            : profile.trimmed

        var page = "متن ذخیره‌شده‌ای از این صفحه موجود نیست."
        if let text = pageContent, !text.isBlank {
            page = clip(text.trimmed, maxContent)
        }

        return """
        تو «دستیار نشانک» هستی؛ دستیار خرید و تصمیم‌گیری کاربر. وظیفه‌ات این است با توجه به شرایط \
        و نیازهای او دربارهٔ همین صفحه قضاوت کنی تا بفهمد این لینک (محصول، مقاله یا ابزار) به دردش می‌خورد یا نه.

        پروفایل کاربر (مبنای قضاوت):
        \(who)

        نشانکِ در دست:
        - عنوان: \(title.isBlank ? "(بدون عنوان)" : title)
        - آدرس: \(url)
        - دامنه: \(domain)
        - ذخیره‌شده در: \(savedAt)
        - برچسب‌ها: \(tags.isEmpty ? "—" : tags.joined(separator: "، "))
        - یادداشت کاربر: \(note.isBlank ? "—" : note)

        متن ذخیره‌شدهٔ صفحه:
        \(page)

        قواعد پاسخ:
        ۱) پاسخ همیشه به زبان \(AppLanguage.current.promptLanguageName) باشد؛ کوتاه و بدون حشو، بدون تعارف و بدون تکرار سؤال.
        ۲) قضاوت را بر اساس نیاز و شرایط کاربر بالا بده. اگر نیازش نامشخص است، اول ۱ تا ۲ سؤال کوتاه بپرس.
        ۳) ساختار پاسخ: یک خط «جمع‌بندی»، بعد «به درد می‌خورد اگر… / نمی‌خورد اگر…» با ۳ تا ۵ تیر، \
        و در پایان یک توصیهٔ روشن (بخر / نخر / اول این را روشن کن).
        ۴) قیمت، موجودی و شرایط ارسال را فقط اگر در متن صفحه آمده بگو و حتماً بنویس «طبق همین صفحه»؛ \
        اطلاعات ناقص را حدس نزن و اگر چیزی در صفحه نیست بگو «در صفحه نیامده».
        ۵) اگر متن صفحه ناکافی بود، از عنوان و دامنه کمک بگیر و این را شفاف اعلام کن.
        ۶) کمتر از ۱۵۰ کلمه جواب بده، مگر اینکه کاربر صراحتاً بیشتر خواسته باشد.
        ۷) در ادعاهای پزشکی، حقوقی یا مالی احتیاط کن و به کاربر یادآوری کن که تصمیم نهایی با خودش/متخصص است.
        """
    }

    static func systemPrompt(profile: String, bookmark: Bookmark, pageContent: String?) -> String {
        systemPrompt(profile: profile,
                     title: bookmark.displayTitle,
                     url: bookmark.url,
                     domain: bookmark.domain,
                     note: bookmark.note,
                     tags: bookmark.tags,
                     savedAt: Dates.persian(bookmark.createdAt),
                     pageContent: pageContent)
    }

    // MARK: پرسش‌های سریع

    struct QuickAction: Identifiable, Equatable, Sendable {
        let id: String
        let icon: String
        let title: String
        let prompt: String

        /// پیش‌فرض‌ها — برای شروع هدفمند بدون نیاز به فکر‌کردن
        /// (computed تا ترجمه‌ها با تغییر زبان برنامه زنده به‌روز شوند)
        static var all: [QuickAction] { [
            QuickAction(id: "fit", icon: "cart",
                        title: L.tr("Is this useful for me?"),
                        prompt: L.tr("Given my profile, is this product/topic useful for me or not? Start with a one-line summary.")),
            QuickAction(id: "summary", icon: "list.bullet.rectangle",
                        title: L.tr("5-point summary"),
                        prompt: L.tr("Summarize this page in 5 short points; one sentence each.")),
            QuickAction(id: "proscons", icon: "scalemass",
                        title: L.tr("Pros and Cons"),
                        prompt: L.tr("Write the pros and cons as two short lists and say which matters more for me.")),
            QuickAction(id: "risks", icon: "exclamationmark.triangle",
                        title: L.tr("Risks and Downsides"),
                        prompt: L.tr("List the possible risks and downsides; mark any that are not mentioned on the page.")),
            QuickAction(id: "compare", icon: "target",
                        title: L.tr("Compare with my needs and budget"),
                        prompt: L.tr("Compare this with my needs, expertise and budget and say whether it is worth paying for.")),
            QuickAction(id: "questions", icon: "questionmark.circle",
                        title: L.tr("Questions to ask before buying"),
                        prompt: L.tr("Write 5 questions I should ask the seller or maker before buying/using it."))
        ] }
    }
}
