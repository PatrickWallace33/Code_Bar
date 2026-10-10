import Foundation

/// Estado da barra compartilhado entre AppKit e SwiftUI: qual painel está aberto, se está colada na borda, etc.
@MainActor
final class BarState: ObservableObject {
    /// Provedor cujo painel está aberto (abre ao passar o mouse).
    @Published var openID: String?
    /// Colada na borda da tela.
    @Published var docked: Bool
    /// Borda da tela onde a barra está ancorada (direita, esquerda, topo, base ou flutuante).
    @Published var dockEdge: DockEdge {
        didSet {
            UserDefaults.standard.set(dockEdge.rawValue, forKey: Keys.dockEdge)
            docked = dockEdge.isDocked
        }
    }
    /// A foto de referência destaca o limite semanal abaixo de cada anel.
    @Published var showsWeeklyUsage: Bool {
        didSet { UserDefaults.standard.set(showsWeeklyUsage, forKey: Keys.showsWeeklyUsage) }
    }
    /// Só mostra a barra enquanto o Orca estiver aberto.
    @Published var onlyWithOrca: Bool {
        didSet { UserDefaults.standard.set(onlyWithOrca, forKey: Keys.onlyWithOrca) }
    }
    /// Só mostra a barra enquanto o Orca for o app ativo (oculta ao ir para Chrome, etc.).
    @Published var onlyWhenActive: Bool {
        didSet { UserDefaults.standard.set(onlyWhenActive, forKey: Keys.onlyWhenActive) }
    }
    /// Notifica quando o uso atinge limites de alerta (80% e 90%).
    @Published var notifyOnLimits: Bool {
        didSet { UserDefaults.standard.set(notifyOnLimits, forKey: Keys.notifyOnLimits) }
    }
    @Published var isDragging = false
    @Published var isPointerInsideBar = false
    private(set) var hoveredID: String?
    private var pinnedID: String?

    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?

    enum Keys {
        static let docked = "barDocked"
        static let dockEdge = "barEdge"
        static let showsWeeklyUsage = "showsWeeklyUsage"
        static let onlyWithOrca = "onlyWithOrca"
        static let onlyWhenActive = "onlyWhenActive"
        static let notifyOnLimits = "notifyOnLimits"
    }

    init() {
        let defaults = UserDefaults.standard
        docked = defaults.object(forKey: Keys.docked) as? Bool ?? true
        if let rawEdge = defaults.string(forKey: Keys.dockEdge), let edge = DockEdge(rawValue: rawEdge) {
            dockEdge = edge
        } else {
            dockEdge = (defaults.object(forKey: Keys.docked) as? Bool ?? true) ? .right : .floating
        }
        showsWeeklyUsage = defaults.object(forKey: Keys.showsWeeklyUsage) as? Bool ?? false
        onlyWithOrca = defaults.object(forKey: Keys.onlyWithOrca) as? Bool ?? false
        onlyWhenActive = defaults.object(forKey: Keys.onlyWhenActive) as? Bool ?? false
        notifyOnLimits = defaults.object(forKey: Keys.notifyOnLimits) as? Bool ?? true
    }

    func hoverItem(_ id: String, inside: Bool) {
        if inside {
            hoveredID = id
            closeWork?.cancel()
            guard !isDragging else { return }
            guard pinnedID == nil else { return }
            if openID == nil {
                // Pequeno atraso para não piscar quando o mouse só passa por cima.
                schedule(&openWork, after: 0.12) { [weak self] in self?.openID = id }
            } else {
                openID = id
            }
        } else {
            if hoveredID == id { hoveredID = nil }
            openWork?.cancel()
            scheduleClose()
        }
    }

    func togglePanel(_ id: String) {
        openWork?.cancel()
        closeWork?.cancel()
        if pinnedID == id {
            closeNow()
        } else {
            pinnedID = id
            openID = id
        }
    }

    /// Mouse dentro do painel mantém ele aberto.
    func hoverPanel(inside: Bool) {
        if inside { closeWork?.cancel() } else { scheduleClose() }
    }

    func closeNow() {
        openWork?.cancel()
        closeWork?.cancel()
        pinnedID = nil
        openID = nil
    }

    private func scheduleClose() {
        guard pinnedID == nil else { return }
        schedule(&closeWork, after: 0.35) { [weak self] in self?.openID = nil }
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ block: @escaping () -> Void) {
        slot?.cancel()
        let work = DispatchWorkItem(block: block)
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
