import Foundation

// MARK: - JSON do `CodexBarCLI usage --json`

struct RateWindow: Decodable {
    let usedPercent: Double
    let resetsAt: Date?
    let resetDescription: String?
}

struct ExtraRateWindow: Decodable {
    let id: String?
    let title: String
    let window: RateWindow
}

struct PaceInfo: Decodable {
    let etaSeconds: Double?
    let willLastToReset: Bool?
}

struct ResetCreditItem: Decodable {
    let id: String?
    let title: String?
    let status: String?
    let expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, title, status
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        expiresAt = try? c.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}

struct ResetCreditsInfo: Decodable {
    let availableCount: Int?
    let credits: [ResetCreditItem]?
}

struct ProviderIdentity: Decodable {
    let accountEmail: String?
    let loginMethod: String?
    let providerID: String?
}

struct UsageSnapshot: Decodable {
    let primary: RateWindow?
    let secondary: RateWindow?
    let tertiary: RateWindow?
    let extraRateWindows: [ExtraRateWindow]?
    let loginMethod: String?
    let accountEmail: String?
    let identity: ProviderIdentity?
    let codexResetCredits: ResetCreditsInfo?
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case primary, secondary, tertiary, extraRateWindows, loginMethod, accountEmail, identity, codexResetCredits, updatedAt
    }

    // Tolerante: um campo com formato inesperado não derruba o provedor inteiro.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primary = try? c.decodeIfPresent(RateWindow.self, forKey: .primary)
        secondary = try? c.decodeIfPresent(RateWindow.self, forKey: .secondary)
        tertiary = try? c.decodeIfPresent(RateWindow.self, forKey: .tertiary)
        extraRateWindows = try? c.decodeIfPresent([ExtraRateWindow].self, forKey: .extraRateWindows)
        loginMethod = try? c.decodeIfPresent(String.self, forKey: .loginMethod)
        accountEmail = try? c.decodeIfPresent(String.self, forKey: .accountEmail)
        identity = try? c.decodeIfPresent(ProviderIdentity.self, forKey: .identity)
        codexResetCredits = try? c.decodeIfPresent(ResetCreditsInfo.self, forKey: .codexResetCredits)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

struct ProviderErrorInfo: Decodable {
    let message: String?
}

struct ProviderPayload: Decodable {
    let provider: String
    let usage: UsageSnapshot?
    let rateWindowLabels: [String: String]?
    let pace: [String: PaceInfo]?
    let error: ProviderErrorInfo?

    private enum CodingKeys: String, CodingKey {
        case provider, usage, rateWindowLabels, pace, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decode(String.self, forKey: .provider)
        usage = try? c.decodeIfPresent(UsageSnapshot.self, forKey: .usage)
        rateWindowLabels = try? c.decodeIfPresent([String: String].self, forKey: .rateWindowLabels)
        pace = try? c.decodeIfPresent([String: PaceInfo].self, forKey: .pace)
        error = try? c.decodeIfPresent(ProviderErrorInfo.self, forKey: .error)
    }
}

struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

// MARK: - Modelo de exibição

struct UsageWindow: Identifiable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    /// Quando o limite acaba no ritmo atual (só se acabar antes de renovar).
    let runsOutAt: Date?
}

struct ProviderUsage: Identifiable {
    let id: String
    let name: String
    let plan: String?
    let accountEmail: String?
    let resetCreditsCount: Int?
    let resetCreditsExpireAt: Date?
    let windows: [UsageWindow]
    let errorMessage: String?
    let updatedAt: Date?

    /// Janela de curto prazo / sessão (ex.: 5h, diária, sessão atual).
    var sessionWindow: UsageWindow? {
        let candidates = windows.filter {
            $0.id == "primary" ||
            $0.label.lowercased().contains("5 hora") ||
            $0.label.lowercased().contains("5-hour") ||
            $0.label.lowercased().contains("sessão") ||
            $0.label.lowercased().contains("session") ||
            $0.label.lowercased().contains("diári")
        }
        if !candidates.isEmpty {
            return candidates.max(by: { $0.usedPercent < $1.usedPercent })
        }
        return windows.first
    }

    /// Janela de longo prazo / semanal (ex.: semana atual, todos os modelos).
    var weeklyWindow: UsageWindow? {
        let candidates = windows.filter {
            $0.id == "secondary" ||
             $0.label.lowercased().contains("semanal") ||
             $0.label.lowercased().contains("week") ||
             $0.label.lowercased().contains("todos os modelos")
        }
        if !candidates.isEmpty {
            return candidates.max(by: { $0.usedPercent < $1.usedPercent })
        }
        return nil
    }

    /// Janela principal retrocompatível.
    var main: UsageWindow? { sessionWindow ?? windows.first }

    /// Janela mais apertada entre as outras (anel interno).
    var tightestOther: UsageWindow? {
        windows.dropFirst().max(by: { $0.usedPercent < $1.usedPercent })
    }

    /// Indica se qualquer uma das cotas está esgotada (>= 99%)
    var isDepleted: Bool {
        (sessionWindow?.usedPercent ?? 0) >= 99 || (weeklyWindow?.usedPercent ?? 0) >= 99
    }

    var depletionMessage: String? {
        if let w = weeklyWindow, w.usedPercent >= 99 {
            if let reset = Fmt.reset(w, now: Date()) {
                return "Cota semanal esgotada (\(reset))"
            }
            return "Cota semanal esgotada"
        }
        if let s = sessionWindow, s.usedPercent >= 99 {
            if let reset = Fmt.reset(s, now: Date()) {
                return "Cota da sessão esgotada (\(reset))"
            }
            return "Cota da sessão esgotada"
        }
        return nil
    }

    var tooltip: String {
        if windows.isEmpty { return "\(name): \(errorMessage ?? "sem dados")" }
        let parts = windows.map { "\($0.label) \(Fmt.pct($0.usedPercent))" }
        return "\(name) — " + parts.joined(separator: " · ")
    }

    init(id: String, name: String, plan: String? = nil, accountEmail: String? = nil, resetCreditsCount: Int? = nil, resetCreditsExpireAt: Date? = nil, windows: [UsageWindow] = [], errorMessage: String? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.plan = plan
        self.accountEmail = accountEmail
        self.resetCreditsCount = resetCreditsCount
        self.resetCreditsExpireAt = resetCreditsExpireAt
        self.windows = windows
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    init(payload p: ProviderPayload) {
        id = p.provider
        name = Names.display(p.provider)
        let rawPlan = p.usage?.loginMethod ?? p.usage?.identity?.loginMethod
        plan = rawPlan.flatMap(Names.plan)
        accountEmail = p.usage?.accountEmail ?? p.usage?.identity?.accountEmail
        resetCreditsCount = p.usage?.codexResetCredits?.availableCount
        resetCreditsExpireAt = p.usage?.codexResetCredits?.credits?
            .filter { ["available", "unused"].contains($0.status?.lowercased() ?? "") }
            .compactMap(\.expiresAt).min()
        updatedAt = p.usage?.updatedAt

        var list: [UsageWindow] = []
        if let u = p.usage {
            let base = u.updatedAt ?? Date()
            if let extras = u.extraRateWindows, !extras.isEmpty {
                for (i, e) in extras.enumerated() {
                    list.append(UsageWindow(
                        id: e.id ?? "extra-\(i)",
                        label: Names.label(e.title, provider: p.provider, slot: "extra"),
                        usedPercent: e.window.usedPercent,
                        resetsAt: e.window.resetsAt,
                        runsOutAt: nil))
                }
            } else {
                let slots: [(String, RateWindow?)] = [
                    ("primary", u.primary), ("secondary", u.secondary), ("tertiary", u.tertiary),
                ]
                for (slot, window) in slots {
                    guard let window else { continue }
                    let raw = p.rateWindowLabels?[slot] ?? Names.defaultLabel(slot)
                    var runsOut: Date?
                    if let pace = p.pace?[slot], pace.willLastToReset == false, let eta = pace.etaSeconds {
                        runsOut = base.addingTimeInterval(eta)
                    }
                    list.append(UsageWindow(
                        id: slot,
                        label: Names.label(raw, provider: p.provider, slot: slot),
                        usedPercent: window.usedPercent,
                        resetsAt: window.resetsAt,
                        runsOutAt: runsOut))
                }
            }
        }
        windows = list
        errorMessage = list.isEmpty ? (p.error?.message ?? "Sem dados de uso") : nil
    }
}

struct RecentProject: Identifiable {
    let id: String
    let name: String
    /// Pasta-mãe (o repositório, no caso de worktrees).
    let parent: String
    let lastUsed: Date
    let sessionId: String?
    let provider: String?
    let summary: String?

    init(id: String, name: String, parent: String, lastUsed: Date, sessionId: String? = nil, provider: String? = nil, summary: String? = nil) {
        self.id = id
        self.name = name
        self.parent = parent
        self.lastUsed = lastUsed
        self.sessionId = sessionId
        self.provider = provider
        self.summary = summary
    }
}

// MARK: - Nomes em português

enum Names {
    private static let known: [String: String] = [
        "claude": "Claude", "codex": "Codex", "openai": "OpenAI", "gemini": "Gemini",
        "antigravity": "Antigravity", "cursor": "Cursor", "copilot": "Copilot", "zai": "z.ai",
        "kimi": "Kimi", "kiro": "Kiro", "factory": "Droid", "opencode": "OpenCode", "amp": "Amp",
        "minimax": "MiniMax", "deepseek": "DeepSeek", "openrouter": "OpenRouter",
    ]

    static func display(_ id: String) -> String {
        known[id] ?? (id.prefix(1).uppercased() + id.dropFirst())
    }

    static func plan(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    static func defaultLabel(_ slot: String) -> String {
        ["primary": "Session", "secondary": "Weekly", "tertiary": "Modelo"][slot] ?? slot
    }

    static func label(_ raw: String, provider: String, slot: String) -> String {
        if raw.lowercased() == "weekly" { return "Limite semanal" }
        if provider == "claude", slot == "secondary", raw.lowercased().contains("week") {
            return "Todos os modelos"
        }
        if raw == "Session" { return "Sessão atual" }
        var s = raw
        let pairs = [
            ("5-hour", "5 horas"), ("Weekly", "Semanal"), ("weekly", "semanal"),
            ("Daily", "Diário"), ("daily", "diário"), ("Monthly", "Mensal"), ("monthly", "mensal"),
            ("Models", "modelos"), (" and ", " e "),
        ]
        for (a, b) in pairs { s = s.replacingOccurrences(of: a, with: b) }
        return s
    }
}

// MARK: - Formatação

enum Fmt {
    static func pct(_ v: Double) -> String {
        "\(Int(min(max(v, 0), 100).rounded()))%"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        let d = m / 1440, h = (m % 1440) / 60, mm = m % 60
        if d > 0 {
            let days = d == 1 ? "1 dia" : "\(d) dias"
            return h > 0 ? "\(days) \(h)h" : days
        }
        if h > 0 { return "\(h)h \(mm)m" }
        return "\(max(mm, 1))m"
    }

    static func reset(_ w: UsageWindow, now: Date) -> String? {
        guard let r = w.resetsAt else { return nil }
        let s = r.timeIntervalSince(now)
        return s > 0 ? "Renova em \(duration(s))" : "Renovando…"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .short
        return f
    }()

    static func ago(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "agora" }
        return relative.localizedString(for: date, relativeTo: now)
    }
}
