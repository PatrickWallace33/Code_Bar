import AppKit
import Combine
import CoreGraphics
import ServiceManagement
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onClick: (() -> Void)?

    /// Captura o gesto antes dos subviews SwiftUI, inclusive quando começa sobre um logo.
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown else {
            super.sendEvent(event)
            return
        }
        let startMouse = convertPoint(toScreen: event.locationInWindow)
        let startOrigin = frame.origin
        var didDrag = false
        while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            let mouse = NSEvent.mouseLocation
            let delta = NSPoint(x: mouse.x - startMouse.x, y: mouse.y - startMouse.y)
            if !didDrag {
                guard hypot(delta.x, delta.y) > 4 else { continue }
                didDrag = true
                onDragStart?()
            }
            setFrameOrigin(NSPoint(x: startOrigin.x + delta.x, y: startOrigin.y + delta.y))
        }
        if didDrag { onDragEnd?() } else { onClick?() }
    }
}

final class BarHostingView: NSHostingView<BarView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = UsageStore()
    private let state = BarState()
    private var panel: BarPanel!
    private var hosting: BarHostingView!
    private var cancellables = Set<AnyCancellable>()
    /// Mostra a barra mesmo sem o Orca, quando o usuário abre o app manualmente.
    private var forceVisible = false

    private let orcaBundleID = "com.stablyai.orca"
    private let snapDistance: CGFloat = 36
    private var lastOrcaFrame: NSRect?
    private var placement = BarPlacement.load()
    private var isPositioningPanel = false
    private var pendingMove: DispatchWorkItem?

    private enum Keys {
        static let loginItemSetup = "loginItemSetup"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let placement {
            state.docked = placement.docked
            if let edge = placement.edge {
                state.dockEdge = edge
            }
        }
        hosting = BarHostingView(rootView: BarView(store: store, state: state))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel = BarPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.onDragStart = { [weak self] in
            self?.state.isDragging = true
            self?.state.closeNow()
        }
        panel.onDragEnd = { [weak self] in self?.finishDrag() }
        panel.onClick = { [weak self] in
            guard let self, let id = self.state.hoveredID else { return }
            self.state.togglePanel(id)
        }
        panel.contentView = hosting
        panel.delegate = self
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

        state.$dockEdge
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] edge in self?.repositionToEdge(edge) }
            .store(in: &cancellables)

        store.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        forceVisible = true
        syncWithOrca()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingMove?.cancel()
        if state.isDragging { finishDrag() }
    }

    /// O AppKit pode arrastar a janela sem chamar mouseUp no NSHostingView.
    func windowDidMove(_ notification: Notification) {
        guard !isPositioningPanel, let moved = notification.object as? NSWindow,
              moved === panel else { return }
        if !state.isDragging {
            state.isDragging = true
            state.closeNow()
        }
        recordPlacement()
        scheduleMoveCompletion()
    }

    private func scheduleMoveCompletion() {
        pendingMove?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 {
                self.scheduleMoveCompletion()
            } else {
                self.finishDrag()
            }
        }
        pendingMove = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
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
            let orca = state.onlyWithOrca ? currentOrcaWindowFrame() : nil
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

    private func screen(containing frame: NSRect) -> NSScreen? {
        NSScreen.screens.filter { $0.frame.intersects(frame) }.max {
            let a = $0.frame.intersection(frame)
            let b = $1.frame.intersection(frame)
            return a.width * a.height < b.width * b.height
        }
    }

    private func detectEdge(frame: NSRect, target: NSRect) -> DockEdge {
        let distRight: CGFloat = frame.maxX >= target.maxX ? 0 : (target.maxX - frame.maxX)
        let distLeft: CGFloat = frame.minX <= target.minX ? 0 : (frame.minX - target.minX)
        let distTop: CGFloat = frame.maxY >= target.maxY ? 0 : (target.maxY - frame.maxY)
        let distBottom: CGFloat = frame.minY <= target.minY ? 0 : (frame.minY - target.minY)

        let candidates: [(edge: DockEdge, dist: CGFloat)] = [
            (.right, distRight),
            (.left, distLeft),
            (.top, distTop),
            (.bottom, distBottom),
        ]

        let minDistance = candidates.map(\.dist).min() ?? CGFloat.infinity
        guard minDistance < snapDistance else {
            return .floating
        }

        // Se houver empate próximo (ex: canto da tela), preserva a orientação atual
        let bestCandidates = candidates.filter { abs($0.dist - minDistance) < 4 }
        if bestCandidates.count > 1 {
            if let sameEdge = bestCandidates.first(where: { $0.edge == state.dockEdge }) {
                return sameEdge.edge
            }
            if let sameOrientation = bestCandidates.first(where: { $0.edge.isHorizontal == state.dockEdge.isHorizontal }) {
                return sameOrientation.edge
            }
        }
        return candidates.min(by: { $0.dist < $1.dist })?.edge ?? .floating
    }

    private func recordPlacement() {
        guard let screen = screen(containing: panel.frame) ?? panel.screen ?? NSScreen.main else { return }
        let orca = (state.onlyWithOrca ? currentOrcaWindowFrame() : nil)
            .flatMap { $0.intersects(panel.frame) ? $0 : nil }
        let targetBounds = orca ?? screen.visibleFrame
        let edge = state.isDragging ? detectEdge(frame: panel.frame, target: targetBounds) : state.dockEdge
        let saved = BarPlacement(
            frame: panel.frame,
            docked: edge.isDocked,
            edge: edge,
            orcaFrame: orca,
            screenID: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )
        placement = saved
        saved.save()
    }

    private func finishDrag() {
        pendingMove?.cancel()
        pendingMove = nil
        guard let screen = screen(containing: panel.frame) ?? panel.screen ?? NSScreen.main else {
            state.isDragging = false
            return
        }
        let orca = (state.onlyWithOrca ? currentOrcaWindowFrame() : nil)
            .flatMap { $0.intersects(panel.frame) ? $0 : nil }
        let targetBounds = orca ?? screen.visibleFrame
        let newEdge = detectEdge(frame: panel.frame, target: targetBounds)
        let orientationChanged = newEdge.isHorizontal != state.dockEdge.isHorizontal

        state.dockEdge = newEdge
        state.docked = newEdge.isDocked

        let saved = BarPlacement(
            frame: panel.frame,
            docked: newEdge.isDocked,
            edge: newEdge,
            orcaFrame: orca,
            screenID: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        )
        placement = saved
        saved.save()

        if orientationChanged {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let size = self.hosting.fittingSize
                let frame = saved.restoredFrame(size: size, visibleFrame: screen.visibleFrame, orcaFrame: orca)
                self.isPositioningPanel = true
                self.panel.setFrame(frame, display: true)
                self.isPositioningPanel = false
                self.recordPlacement()
                self.state.isDragging = false
            }
        } else {
            let frame = saved.restoredFrame(size: panel.frame.size, visibleFrame: screen.visibleFrame, orcaFrame: orca)
            isPositioningPanel = true
            panel.setFrame(frame, display: true)
            isPositioningPanel = false
            recordPlacement()
            state.isDragging = false
        }
    }

    private func repositionToEdge(_ edge: DockEdge) {
        guard !state.isDragging, !isPositioningPanel else { return }
        guard let screen = screen(containing: panel.frame) ?? panel.screen ?? NSScreen.main else { return }
        let orca = (state.onlyWithOrca ? currentOrcaWindowFrame() : nil)
            .flatMap { $0.intersects(panel.frame) ? $0 : nil }
        let target = orca ?? screen.visibleFrame

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.state.isDragging else { return }
            let size = self.hosting.fittingSize
            guard size.width > 0, size.height > 0 else { return }

            var newX = self.panel.frame.minX
            var newTop = self.panel.frame.maxY

            switch edge {
            case .right:
                newX = target.maxX - size.width
                if newTop < target.minY + size.height || newTop > target.maxY {
                    newTop = target.midY + size.height / 2
                }
            case .left:
                newX = target.minX
                if newTop < target.minY + size.height || newTop > target.maxY {
                    newTop = target.midY + size.height / 2
                }
            case .top:
                newTop = target.maxY
                if newX < target.minX || newX > target.maxX - size.width {
                    newX = target.midX - size.width / 2
                }
            case .bottom:
                newTop = target.minY + size.height
                if newX < target.minX || newX > target.maxX - size.width {
                    newX = target.midX - size.width / 2
                }
            case .floating:
                break
            }

            let newFrame = CGRect(x: newX, y: newTop - size.height, width: size.width, height: size.height)
            let saved = BarPlacement(
                frame: newFrame,
                docked: edge.isDocked,
                edge: edge,
                orcaFrame: orca,
                screenID: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            )
            self.placement = saved
            saved.save()

            let restored = saved.restoredFrame(size: size, visibleFrame: screen.visibleFrame, orcaFrame: orca)
            self.isPositioningPanel = true
            self.panel.setFrame(restored, display: true)
            self.isPositioningPanel = false
        }
    }

    /// Restaura a última posição; o local padrão só é usado antes do primeiro arraste.
    private func layoutPanel(orcaFrame: NSRect? = nil) {
        guard !state.isDragging else { return }
        let orca = state.onlyWithOrca ? (orcaFrame ?? currentOrcaWindowFrame()) : nil
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let followsOrca = placement == nil || placement?.relativeX != nil || placement?.relativeTop != nil
        let anchor = followsOrca ? orca : nil
        let savedScreen = placement?.screenID.flatMap { id in
            NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
        }
        let savedFrame = placement.map { NSRect(x: $0.x, y: $0.top - size.height, width: size.width, height: size.height) }
        guard let screen = anchor.flatMap({ self.screen(containing: $0) })
                ?? savedScreen ?? savedFrame.flatMap({ self.screen(containing: $0) })
                ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let bounds = anchor ?? screen.visibleFrame
        let initialEdge = placement?.edge ?? state.dockEdge
        let initial = BarPlacement(
            frame: NSRect(x: bounds.maxX - size.width, y: bounds.midY - size.height / 2,
                          width: size.width, height: size.height),
            docked: initialEdge.isDocked,
            edge: initialEdge,
            orcaFrame: anchor,
            screenID: nil)
        let frame = (placement ?? initial).restoredFrame(
            size: size, visibleFrame: screen.visibleFrame, orcaFrame: anchor)
        isPositioningPanel = true
        panel.setFrame(frame, display: true)
        isPositioningPanel = false
    }
}
