import Foundation

/// Estado da barra compartilhado entre AppKit e SwiftUI: qual painel está aberto, se está colada na borda, etc.
@MainActor
final class BarState: ObservableObject {
    /// Provedor cujo painel está aberto (abre ao passar o mouse).
    @Published var openID: String?
    /// Colada na borda direita da tela (cantos arredondados só do lado esquerdo).
    @Published var docked: Bool
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
    var isDragging = false

    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?

    enum Keys {
        static let docked = "barDocked"
        static let onlyWithOrca = "onlyWithOrca"
        static let onlyWhenActive = "onlyWhenActive"
        static let notifyOnLimits = "notifyOnLimits"
    }

    init() {
        let defaults = UserDefaults.standard
        docked = defaults.object(forKey: Keys.docked) as? Bool ?? true
        onlyWithOrca = defaults.object(forKey: Keys.onlyWithOrca) as? Bool ?? true
        onlyWhenActive = defaults.object(forKey: Keys.onlyWhenActive) as? Bool ?? true
        notifyOnLimits = defaults.object(forKey: Keys.notifyOnLimits) as? Bool ?? true
    }

    func hoverItem(_ id: String, inside: Bool) {
        if inside {
            closeWork?.cancel()
            guard !isDragging else { return }
            if openID == nil {
                // Pequeno atraso para não piscar quando o mouse só passa por cima.
                schedule(&openWork, after: 0.12) { [weak self] in self?.openID = id }
            } else {
                openID = id
            }
        } else {
            openWork?.cancel()
            scheduleClose()
        }
    }

    /// Mouse dentro do painel mantém ele aberto.
    func hoverPanel(inside: Bool) {
        if inside { closeWork?.cancel() } else { scheduleClose() }
    }

    func closeNow() {
        openWork?.cancel()
        closeWork?.cancel()
        openID = nil
    }

    private func scheduleClose() {
        schedule(&closeWork, after: 0.35) { [weak self] in self?.openID = nil }
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after delay: TimeInterval, _ block: @escaping () -> Void) {
        slot?.cancel()
        let work = DispatchWorkItem(block: block)
        slot = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
