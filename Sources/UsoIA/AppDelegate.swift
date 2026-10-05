import AppKit
import Combine
import CoreGraphics
import ServiceManagement
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Arrastar em qualquer ponto da barra move a janela (o clique esquerdo não é usado para mais nada).
final class BarHostingView: NSHostingView<BarView> {
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    private var startMouse: NSPoint = .zero
    private var startOrigin: NSPoint = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: startOrigin.x + mouse.x - startMouse.x,
            y: startOrigin.y + mouse.y - startMouse.y))
    }

    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private let state = BarState()
    private var panel: BarPanel!
    private var hosting: BarHostingView!
    private var cancellables = Set<AnyCancellable>()
    /// Mostra a barra mesmo sem o Orca, quando o usuário abre o app manualmente.
    private var forceVisible = false

    private let orcaBundleID = "com.stablyai.orca"
    private let snapDistance: CGFloat = 24
    private var lastOrcaFrame: NSRect?

    private enum Keys {
        static let top = "barTop"
        static let x = "barX"
        static let relativeTop = "barRelativeTop"
        static let relativeX = "barRelativeX"
        static let loginItemSetup = "loginItemSetup"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hosting = BarHostingView(rootView: BarView(store: store, state: state))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.onDragStart = { [weak self] in
            self?.state.isDragging = true
            self?.state.closeNow()
        }
        hosting.onDragEnd = { [weak self] in self?.finishDrag() }

        panel = BarPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        // Abre o app no login (escondido); a barra aparece quando o Orca abre.
        if !UserDefaults.standard.bool(forKey: Keys.loginItemSetup) {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: Keys.loginItemSetup)
        }

        layoutPanel()
        syncWithOrca()

        store.$providers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.layoutPanel() }
            }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        Publishers.MergeMany([
            workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification),
            workspace.publisher(for: NSWorkspace.didActivateApplicationNotification),
            workspace.publisher(for: NSWorkspace.didDeactivateApplicationNotification),
            workspace.publisher(for: NSWorkspace.didHideApplicationNotification),
            workspace.publisher(for: NSWorkspace.didUnhideApplicationNotification),
            workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               front != self.orcaBundleID && front != Bundle.main.bundleIdentifier {
                self.forceVisible = false
            }
            self.syncWithOrca()
        }
        .store(in: &cancellables)

        Publishers.Merge(
            state.$onlyWithOrca.dropFirst().map { _ in () },
            state.$onlyWhenActive.dropFirst().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.syncWithOrca() }
        .store(in: &cancellables)

        // Monitoramento dinâmico (a cada 150ms) para acompanhar movimentação e divisão de tela do Orca
        Timer.publish(every: 0.15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.syncWithOrca() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layoutPanel() }
            .store(in: &cancellables)

        store.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        forceVisible = true
        syncWithOrca()
        return false
    }

    private var isOrcaRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == orcaBundleID }
    }

    private var isOrcaActive: Bool {
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return front == orcaBundleID || front == Bundle.main.bundleIdentifier
    }

    /// Obtém o frame da janela principal do Orca em coordenadas Cocoa.
    private func currentOrcaWindowFrame() -> NSRect? {
        let orcaApps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == orcaBundleID }
        guard !orcaApps.isEmpty else { return nil }
        let pids = Set(orcaApps.map { $0.processIdentifier })

        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryHeight = primary.frame.height

        var bestRect: NSRect?
        var maxArea: Double = 0

        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  pids.contains(pid),
                  let layer = w[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  let qX = bounds["X"] as? Double,
                  let qY = bounds["Y"] as? Double,
                  width > 150, height > 150
            else { continue }

            let area = width * height
            if area > maxArea {
                maxArea = area
                let cocoaX = CGFloat(qX)
                let cocoaY = primaryHeight - CGFloat(qY) - CGFloat(height)
                bestRect = NSRect(x: cocoaX, y: cocoaY, width: CGFloat(width), height: CGFloat(height))
            }
        }
        return bestRect
    }

    private var shouldShow: Bool {
        if forceVisible { return true }
        guard state.onlyWithOrca else { return true }
        guard isOrcaRunning else { return false }
        guard currentOrcaWindowFrame() != nil else { return false }
        if state.onlyWhenActive {
            guard isOrcaActive else { return false }
        }
        return true
    }

    /// Sincroniza a visibilidade e a posição do indicador diretamente com a janela do Orca.
    private func syncWithOrca() {
        let show = shouldShow
        store.isPaused = !show
        if show {
            let orca = currentOrcaWindowFrame()
            if orca != lastOrcaFrame {
                lastOrcaFrame = orca
                layoutPanel(orcaFrame: orca)
            }
            if !panel.isVisible {
                layoutPanel(orcaFrame: orca)
                panel.orderFrontRegardless()
                store.refreshIfStale()
            }
        } else {
            lastOrcaFrame = nil
            if panel.isVisible {
                state.closeNow()
                panel.orderOut(nil)
            }
        }
    }

    private func finishDrag() {
        state.isDragging = false
        var frame = panel.frame
        let orca = currentOrcaWindowFrame()

        guard let screen = orca.flatMap({ targetRect in
            NSScreen.screens.first { $0.frame.intersects(targetRect) }
        }) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let visible = screen.visibleFrame
        let targetBounds = orca ?? visible

        // Checa se está próximo da borda direita da janela do Orca (ou da tela)
        let distanceToRight = abs(targetBounds.maxX - frame.maxX)
        let docked = distanceToRight < snapDistance

        if docked {
            frame.origin.x = targetBounds.maxX - frame.width
        }
        panel.setFrameOrigin(frame.origin)

        let defaults = UserDefaults.standard
        defaults.set(Double(frame.maxY), forKey: Keys.top)
        defaults.set(Double(frame.minX), forKey: Keys.x)
        defaults.set(docked, forKey: BarState.Keys.docked)
        state.docked = docked

        if let orca {
            // Salva a posição relativa à janela do Orca para acompanhá-lo
            defaults.set(Double(orca.maxY - frame.maxY), forKey: Keys.relativeTop)
            defaults.set(Double(frame.minX - orca.minX), forKey: Keys.relativeX)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.layoutPanel() }
    }

    /// Tamanho do conteúdo; posiciona alinhado à janela do Orca (ou à tela), sempre acompanhando divisões de tela.
    private func layoutPanel(orcaFrame: NSRect? = nil) {
        guard !state.isDragging else { return }
        let orca = orcaFrame ?? currentOrcaWindowFrame()

        guard let screen = orca.flatMap({ targetRect in
            NSScreen.screens.first { $0.frame.intersects(targetRect) }
        }) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let visible = screen.visibleFrame
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let defaults = UserDefaults.standard
        let targetBounds = orca ?? visible

        var x: CGFloat
        if state.docked {
            // Fixado na borda direita da janela do Orca
            x = targetBounds.maxX - size.width
        } else {
            if let savedRelX = defaults.object(forKey: Keys.relativeX) as? Double, orca != nil {
                x = targetBounds.minX + CGFloat(savedRelX)
            } else if let savedX = defaults.object(forKey: Keys.x) as? Double {
                x = CGFloat(savedX)
            } else {
                x = targetBounds.maxX - size.width
            }
        }
        // Garante que não saia dos limites horizontais da tela
        x = min(max(x, visible.minX), visible.maxX - size.width)

        var top: CGFloat
        if let savedRelTop = defaults.object(forKey: Keys.relativeTop) as? Double, orca != nil {
            top = targetBounds.maxY - CGFloat(savedRelTop)
        } else if let savedTop = defaults.object(forKey: Keys.top) as? Double {
            top = CGFloat(savedTop)
        } else {
            top = targetBounds.midY + size.height / 2
        }

        // Restringe a posição vertical dentro dos limites do Orca (quando visível) e da tela
        let minY = max(visible.minY + size.height, targetBounds.minY + size.height)
        let maxY = min(visible.maxY, targetBounds.maxY)
        if maxY >= minY {
            top = min(max(top, minY), maxY)
        } else {
            top = min(max(top, visible.minY + size.height), visible.maxY)
        }

        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}
