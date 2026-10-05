import Foundation

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var providers: [ProviderUsage] = []
    @Published private(set) var recent: [String: [RecentProject]] = [:]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    /// Barra escondida (Orca fechado): não busca nada até aparecer de novo.
    var isPaused = false

    private var timer: Timer?
    private let cacheKey = "lastPayload"
    private let cacheDateKey = "lastUpdated"

    init() {
        // Mostra o último resultado na hora, enquanto a primeira busca (≈15 s) roda.
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: cacheKey), let list = try? UsageFetcher.decode(data) {
            providers = Self.ordered(list)
            lastUpdated = defaults.object(forKey: cacheDateKey) as? Date
        }
    }

    /// 5 min, igual ao padrão do CodexBar, para não martelar as APIs de uso.
    func start(interval: TimeInterval = 300) {
        if !isPaused { refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.refresh()
            }
        }
    }

    func refreshIfStale(maxAge: TimeInterval = 120) {
        if let last = lastUpdated, Date().timeIntervalSince(last) < maxAge { return }
        refresh()
    }

    /// Mantém estritamente Claude, Codex e Antigravity na ordem de referência (Gemini removido).
    private static func ordered(_ list: [ProviderUsage]) -> [ProviderUsage] {
        let allowed = ["claude", "codex", "antigravity"]
        return allowed.compactMap { id in
            if let found = list.first(where: { $0.id.lowercased() == id }) {
                return found
            }
            return ProviderUsage(
                id: id,
                name: Names.display(id),
                plan: nil,
                windows: [],
                errorMessage: "Não conectado",
                updatedAt: nil
            )
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            // Projetos vêm de arquivos locais (rápido): mostra antes de esperar o CodexBar.
            recent = await Task.detached(priority: .utility) { RecentProjects.loadAll() }.value
            do {
                let data = try await UsageFetcher.fetchRaw()
                let list = try UsageFetcher.decode(data)
                let now = Date()
                providers = Self.ordered(list)
                lastUpdated = now
                lastError = nil
                UserDefaults.standard.set(data, forKey: cacheKey)
                UserDefaults.standard.set(now, forKey: cacheDateKey)
                checkLimitNotifications()
            } catch {
                lastError = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func checkLimitNotifications() {
        guard UserDefaults.standard.object(forKey: BarState.Keys.notifyOnLimits) as? Bool ?? true else { return }
        for provider in providers {
            for window in provider.windows {
                let pct = window.usedPercent
                guard pct >= 80 else { continue }
                let tier = pct >= 95 ? 95 : (pct >= 90 ? 90 : 80)
                let resetKey = window.resetsAt.map { "\(Int($0.timeIntervalSince1970))" } ?? "noreset"
                let key = "notif_\(provider.id)_\(window.id)_\(tier)_\(resetKey)"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    let resetMsg = Fmt.reset(window, now: Date()) ?? ""
                    let body = "\(window.label) atingiu \(Int(pct))% de uso\(resetMsg.isEmpty ? "" : " · " + resetMsg)."
                    Self.sendNotification(title: "Uso IA — Alerta: \(provider.name)", message: body)
                }
            }
        }
    }

    private static func sendNotification(title: String, message: String) {
        let cleanTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let cleanMsg = message.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(cleanMsg)\" with title \"\(cleanTitle)\" sound name \"default\""
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
        }
    }
}
